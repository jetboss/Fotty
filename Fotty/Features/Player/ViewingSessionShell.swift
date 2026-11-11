import SwiftUI

/// The media ForEach never moves into a TabView accessory, cover or another
/// player hierarchy. Empty layout slots change its geometry, not its identity.
struct ViewingSessionShell<Content: View>: View {
    let viewing: ViewingSessionCoordinator
    @ViewBuilder let content: () -> Content
    @State private var surfaceBounds: [UUID: CGRect] = [:]
    @State private var currentSlotIDs: Set<UUID> = []
    @State private var expandedSizes: [UUID: CGSize] = [:]
    @State private var contentViewport = CGRect.zero
    @State private var showsPlaybackSourceSettings = false

    var body: some View {
        GeometryReader { rootGeometry in
            ZStack {
                // Keep this container mounted in every presentation. UIKit
                // navigation needs an actual AX boundary before hiding its
                // inactive controls; do not move or remove the tab/media trees.
                ZStack { content() }
                    .accessibilityElement(children: .contain)
                    .accessibilityHidden(viewing.isActive && viewing.expanded)
                    .allowsHitTesting(!(viewing.isActive && viewing.expanded))
                // The chrome and actual media are one permanent accessibility
                // region. Making chrome alone modal would exclude its sibling
                // video controls. The media ForEach never moves between states.
                ZStack {
                    if viewing.isActive && viewing.expanded { ViewingExperienceView().zIndex(1) }
                    ForEach(viewing.panes) { pane in
                        retainedSurface(pane, root: rootGeometry.frame(in: .global)).zIndex(2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    if let message = viewing.resolutionMessage, viewing.pendingSingleEvent == nil {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(message).font(.subheadline)
                            Spacer()
                            Button("Cancel") { viewing.cancelResolution() }.frame(minHeight: 44)
                        }
                        .padding(.horizontal, 16).background(.regularMaterial, in: .rect(cornerRadius: 16)).padding(12)
                        .accessibilityIdentifier("viewing-resolution")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(viewing.isActive && viewing.expanded ? .isModal : [])
            }
            .onPreferenceChange(ViewingSurfaceBoundsKey.self) { next in
                let admitted = next.filter { id, rect in
                    viewing.panes.contains { $0.id == id } && rect.width > 0 && rect.height > 0
                        && rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite
                }
                let nextIDs = Set(admitted.keys)
                if currentSlotIDs != nextIDs { currentSlotIDs = nextIDs }
                var updated = surfaceBounds.filter { id, _ in viewing.panes.contains { $0.id == id } }
                updated.merge(admitted, uniquingKeysWith: { _, new in new })
                if updated != surfaceBounds { surfaceBounds = updated }
                var sizes = expandedSizes.filter { id, _ in viewing.panes.contains { $0.id == id } }
                if viewing.expanded { for (id, rect) in admitted where rect.width > 150 { sizes[id] = rect.size } }
                if sizes != expandedSizes { expandedSizes = sizes }
            }
            .onPreferenceChange(ViewingViewportBoundsKey.self) { value in
                if contentViewport != value { contentViewport = value }
            }
        }
        .environment(viewing)
        .onChange(of: viewing.panes.filter { $0.model.isPictureInPictureActive || $0.model.isWebPictureInPictureActive }.map(\.id)) { _, _ in
            viewing.reconcilePictureInPictureOwnership()
        }
        .background(ViewingSceneLeaseMarker(onSceneDisconnect: { viewing.stop() })
            .frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true))
        .alert("Broadcast not ready", isPresented: Binding(get: { viewing.resolutionError != nil }, set: { if !$0 { viewing.resolutionError = nil } })) {
            if viewing.canRetrySingleAudio {
                Button("Retry audio") { viewing.retrySingleAudio() }
            }
            if viewing.canRetrySingleDiscovery {
                Button("Retry") { viewing.retrySingleDiscovery() }
            }
            if viewing.canManageSingleDiscoverySources {
                Button("Manage sources") {
                    if viewing.manageSingleDiscoverySources() { showsPlaybackSourceSettings = true }
                }
            }
            Button("OK") { viewing.resolutionError = nil }
        } message: { Text(viewing.resolutionError ?? "") }
        .sheet(isPresented: $showsPlaybackSourceSettings) {
            NavigationStack {
                StreamPluginsSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsPlaybackSourceSettings = false }
                        }
                    }
            }
        }
        .sheet(item: Binding(get: { viewing.incomingEvent }, set: { viewing.incomingEvent = $0 })) { event in
            NavigationStack {
                VStack(alignment: .leading, spacing: 20) {
                    Text(event.displayTitle).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text("Continue this match here?").font(.headline)
                    Text("A new broadcast will be checked on this device. The other device is not stopped automatically.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Watch here") { viewing.watchIncoming() }.buttonStyle(FottyPrimaryButtonStyle())
                    Button("Not now") { viewing.incomingEvent = nil; viewing.incomingHandoff = nil }.frame(minHeight: 44)
                }.padding(24)
                .navigationTitle("Continue watching").navigationBarTitleDisplayMode(.inline)
            }.presentationDetents([.medium, .large])
        }
    }

    private func retainedSurface(_ pane: ViewingSessionCoordinator.Pane, root: CGRect) -> some View {
        let target = surfaceBounds[pane.id] ?? CGRect(x: root.minX, y: root.minY, width: 320, height: 180)
        let viewport = viewing.expanded && !contentViewport.isEmpty ? contentViewport.intersection(root) : root
        let visible = target.intersection(viewport)
        let placementMatches = viewing.expanded ? target.width > 100 : target.width <= 100 && target.height <= 56
        let hasVisibleBounds = !visible.isNull && !visible.isEmpty && currentSlotIDs.contains(pane.id) && placementMatches
        let crop = hasVisibleBounds ? visible : CGRect(x: target.minX, y: target.minY, width: 1, height: 1)
        // In mini mode retain a useful WebKit viewport, scaling only the visual
        // result. The provider document doesn't reflow into a 46-point window.
        let source = viewing.expanded ? target.size : (expandedSizes[pane.id] ?? CGSize(width: 320, height: 180))
        return LivePlayerView(viewModel: pane.model, isSurfaceOnly: true,
            publishesLiveActivity: viewing.panes.count == 1, usesManagedAudio: viewing.isTwo,
            physicalMeasurementIdentifier: viewing.isTwo
                ? "native-measurement-pane-\((viewing.panes.firstIndex(where: { $0.id == pane.id }) ?? 0) + 1)"
                : "native-playback-measurement",
            onRetryDiscovery: viewing.isTwo ? nil : { viewing.retrySinglePlaybackDiscovery(for: pane.model) },
            retryDiscoveryMessage: viewing.singlePlaybackRetryMessage(for: pane.model),
            onCancelRetryDiscovery: { viewing.cancelSinglePlaybackRetry(for: pane.model) },
            onClose: { viewing.stop() })
            .frame(width: source.width, height: source.height)
            .scaleEffect(x: target.width / max(1, source.width), y: target.height / max(1, source.height), anchor: .topLeading)
            .frame(width: target.width, height: target.height, alignment: .topLeading)
            .clipShape(.rect(cornerRadius: viewing.expanded ? 16 : 8))
            .offset(x: target.minX - crop.minX, y: target.minY - crop.minY)
            .frame(width: crop.width, height: crop.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .position(x: crop.midX - root.minX, y: crop.midY - root.minY)
            .opacity(hasVisibleBounds ? 1 : 0)
            .allowsHitTesting(viewing.expanded && hasVisibleBounds)
            .accessibilityHidden(!viewing.expanded || !hasVisibleBounds)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("live-player")
    }
}
