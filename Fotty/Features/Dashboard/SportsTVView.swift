import SwiftUI

/// TV uses the same retained-single presentation contract as Home/Matchday.
/// A channel is canonical navigation identity, not a live fixture claim.
@MainActor
enum SportsTVWatchPolicy {
    static func watch(_ event: EventReference, using viewing: ViewingSessionCoordinator,
                      catalog: [EventReference]) {
        watch(event, using: viewing, currentCatalog: { catalog })
    }

    static func watch(_ event: EventReference, using viewing: ViewingSessionCoordinator,
                      currentCatalog: @escaping @MainActor () -> [EventReference]) {
        viewing.watchSingle(event, admission: { requested in
            guard let current = CurrentEventBroadcastPolicy.currentEvent(for: requested, in: currentCatalog()),
                  MatchStartPolicy(event: current).timingAllowsPlayback else { return nil }
            return current
        })
    }
}

struct SportsTVView: View {
    var isActive = true
    let onWatch: (EventReference) -> Void
    @Environment(ViewingSessionCoordinator.self) private var viewing
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var library = SportsTVLibrary.shared
    @State private var registry = BroadcastRegistryClient.shared
    @State private var discovery = FixtureStreamDiscoveryIndex.shared
    @State private var query = ""
    @State private var filter = SportsTVLibrary.Filter.all
    @AppStorage(CommentaryPreference.storageKey) private var commentary = CommentaryPreference.english.rawValue

    private var enabled: Bool { discovery.enabledProviderCodes.contains(ReviewedTVPlaylistClient.providerCode) }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(at: context.date)
        }
    }

    private func content(at now: Date) -> some View {
        let visibleGroups = library.sections(commentary: CommentaryPreference(rawValue: commentary) ?? .english,
            filter: filter, query: query, snapshot: registry.snapshot, at: now)
        return NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !enabled {
                            NavigationLink {
                                StreamPluginsSettingsView()
                            } label: { Label("Enable TV sources", systemImage: "tv").frame(minHeight: 44) }
                        }
                        Picker("Channel filter", selection: $filter) {
                            ForEach(SportsTVLibrary.Filter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("sports-tv-filter")
                        if visibleGroups.isEmpty {
                            ContentUnavailableView {
                                Label(filter == .favourites && query.isEmpty ? "Your favourite channels" : "No matching channels",
                                      systemImage: filter == .favourites ? "star" : "magnifyingglass")
                            } description: {
                                Text(filter == .favourites && query.isEmpty ? "Tap the star beside a channel to keep it here." : "Try a channel name or a programme from the guide.")
                            } actions: {
                                Button("Show all channels") { query = ""; filter = .all }
                                    .frame(minHeight: 44)
                                    .accessibilityIdentifier("sports-tv-reset")
                            }
                        }
                        ForEach(visibleGroups) { group in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(group.id).font(.title3.weight(.semibold))
                                        .accessibilityAddTraits(.isHeader)
                                    Spacer()
                                    if group.id == "Recently watched" {
                                        Button("Clear") { library.clearRecent() }
                                            .frame(minWidth: 44, minHeight: 44)
                                            .accessibilityLabel("Clear recently watched channels")
                                    }
                                }
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16),
                                    count: geometry.size.width >= 760 && !typeSize.isAccessibilitySize ? 2 : 1), spacing: 16) {
                                    ForEach(group.stations) { station in stationRow(station, at: now) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, geometry.size.width >= 760 ? 24 : 16)
                    .padding(.vertical, 16)
                }
            }
            .scrollContentBackground(.hidden)
            .background(FottyTheme.background)
            .tint(FottyTheme.accentText)
            .navigationTitle("Sports TV")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, prompt: "Channels and programmes")
            .refreshable { _ = await registry.refresh() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let pending = viewing.pendingSingleEvent, let message = viewing.resolutionMessage {
                    StreamResolutionPanel(sportCategory: pending.normalizedCategory,
                        competition: SportMotionContext.competition(for: pending), statusMessage: message,
                        subtitle: pending.displayTitle, isMultiStream: false, multiTitles: [],
                        onCancel: { viewing.cancelPendingSingleDiscovery() })
                }
            }
            .task(id: now) {
                guard isActive, scenePhase == .active, !viewing.expanded else { return }
                // The client coalesces refreshes and enforces its existing five-
                // minute interval. A visible guide must not age out while idle.
                _ = await registry.refresh(at: now)
            }
            .task(id: isActive) {
                guard isActive else { return }
                await StreamPluginRegistry.shared.refreshDiscoveryAvailability()
                _ = await registry.refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { viewing.cancelPendingSingleDiscovery() }
                if phase == .active && isActive {
                    Task {
                        await StreamPluginRegistry.shared.refreshDiscoveryAvailability()
                        _ = await registry.refresh()
                    }
                }
            }
            .onChange(of: isActive) { _, active in
                if !active { viewing.cancelPendingSingleDiscovery() }
            }
            .onDisappear { viewing.cancelPendingSingleDiscovery() }
        }
        .accessibilityIdentifier("sports-tv")
    }

    private func stationRow(_ station: SportsTVStation, at now: Date) -> some View {
        let entries = SportsTVGuidePolicy.entries(for: station, snapshot: registry.snapshot, at: now)
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 5) {
                Text(station.title).font(.headline).foregroundStyle(FottyTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if station.language != .any { Text(station.language.title).font(.subheadline).foregroundStyle(.secondary) }
                if let current = entries.first(where: { $0.isOnNow(at: now) }) {
                    Text("Now · \(current.title)").font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    if let progress = current.progress(at: now) {
                        ProgressView(value: progress).tint(FottyTheme.accentText)
                            .accessibilityLabel("Scheduled programme progress")
                    }
                }
                if let next = entries.first(where: { $0.start > now }) {
                    Text("Next · \(next.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())) · \(next.title)")
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button { library.toggleFavourite(station.id) } label: {
                    Image(systemName: library.favourites.contains(station.id) ? "star.fill" : "star")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(library.favourites.contains(station.id) ? "Remove \(station.title) from favourites" : "Favourite \(station.title)")
                Button { onWatch(station.event) } label: {
                    Label {
                        Text(viewing.pendingSingleEvent?.id == station.event.id ? "Opening…" : "Watch")
                    } icon: {
                        if viewing.pendingSingleEvent?.id == station.event.id {
                            ProgressView().controlSize(.small).tint(FottyTheme.textOnAccent)
                        } else { Image(systemName: "play.fill") }
                    }
                    .frame(minHeight: 44)
                }
                    .buttonStyle(.borderedProminent).tint(FottyTheme.accent)
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .disabled(!canWatch(station) || viewing.pendingSingleEvent != nil)
                    .accessibilityLabel("Watch \(station.title)")
                    .accessibilityValue(viewing.pendingSingleEvent?.id == station.event.id ? "Opening broadcast" : "")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(FottyTheme.surface, in: .rect(cornerRadius: 16))
    }
    private func canWatch(_ station: SportsTVStation) -> Bool {
        SportsTVStation.canWatchNow(station, discoveryIndex: discovery)
    }
}

struct SportsPlaybackPreferencesView: View {
    @AppStorage(CommentaryPreference.storageKey) private var commentary = CommentaryPreference.english.rawValue
    @AppStorage(WatchingSpoilerProtection.preferenceKey) private var spoilerSafe = false
    var body: some View {
        Form {
            Section {
                Picker("Preferred language", selection: $commentary) {
                    ForEach(CommentaryPreference.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } header: { Text("Commentary") } footer: {
                Text("Automatic selection prefers a known matching language. Other streams remain available.")
            }
            Section {
                Toggle("Hide scores & goal alerts", isOn: $spoilerSafe)
            } header: { Text("While watching") } footer: {
                Text("Hide external scores and pause Fotty goal alerts for the match you’re watching. The broadcaster’s own scoreboard stays visible.")
            }
        }
        .navigationTitle("Playback preferences").navigationBarTitleDisplayMode(.inline)
        .onChange(of: spoilerSafe) { _, enabled in WatchingSpoilerProtection.shared.enabled = enabled }
        .onAppear { WatchingSpoilerProtection.shared.enabled = spoilerSafe }
        .tint(FottyTheme.accentText)
    }
}
