import SwiftUI

private struct FottyStreamLookupBusyKey: EnvironmentKey {
    static let defaultValue = false
}

private struct FottySceneOwnsSingleWatchKey: EnvironmentKey {
    static let defaultValue = false
}

private struct FottyPendingWatchEventIDKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// Only playback/selection controls pause while a browsing surface owns a
    /// lookup. Scrolling, filtering, details and opt-in reminders stay usable.
    var fottyStreamLookupBusy: Bool {
        get { self[FottyStreamLookupBusyKey.self] }
        set { self[FottyStreamLookupBusyKey.self] = newValue }
    }

    /// Normal browsing delegates tap-time admission to the scene owner after
    /// visible acknowledgement. Other consumers retain their local guards.
    var fottySceneOwnsSingleWatch: Bool {
        get { self[FottySceneOwnsSingleWatchKey.self] }
        set { self[FottySceneOwnsSingleWatchKey.self] = newValue }
    }

    var fottyPendingWatchEventID: String? {
        get { self[FottyPendingWatchEventIDKey.self] }
        set { self[FottyPendingWatchEventIDKey.self] = newValue }
    }
}

/// Gives SwiftUI one bounded presentation window before provider discovery
/// begins. Watch is a user-initiated action, so its acknowledgement must win
/// the first frame even when catalog matching has synchronous work to do.
enum StreamResolutionPresentation {
    static func waitForFeedbackFrame() async throws {
        await Task.yield()
        try await Task.sleep(for: .milliseconds(60))
    }
}

/// A nonblocking acknowledgement anchored in the browsing surface's bottom
/// safe-area inset. No dimmer or gesture layer sits above the catalog/player.
struct StreamResolutionPanel: View {
    let sportCategory: String
    var competition: FootballCompetitionID? = nil
    let statusMessage: String
    let subtitle: String?
    let isMultiStream: Bool
    let multiTitles: [String]
    let onCancel: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var informationWidth: CGFloat = 180
    
    var body: some View {
        MatchRowLayout(minimumInformationWidth: informationWidth, forceStack: typeSize.isAccessibilitySize, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                // SportLoadingView owns a 2.8×2.1 canvas. Size the canvas itself;
                // an outer frame alone would let its artwork overlap the label.
                SportLoadingView(category: sportCategory, size: 18.5, label: "", competition: competition)
                    .frame(width: 52, height: 52)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FottyTheme.textPrimary)
                    if isMultiStream {
                        ForEach(Array(multiTitles.enumerated()), id: \.offset) { _, title in
                            Text(title).font(FottyTheme.typeCaption)
                                .foregroundStyle(FottyTheme.textSecondary)
                        }
                    } else if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(FottyTheme.typeCaption)
                            .foregroundStyle(FottyTheme.textSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            Button("Cancel", action: onCancel)
                .font(FottyTheme.typeAction)
                .foregroundStyle(FottyTheme.accentText)
                .padding(.horizontal, 8)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(FottyPressButtonStyle())
                .accessibilityLabel(isMultiStream ? "Cancel two-match stream lookup" : "Cancel stream lookup")
                .accessibilityIdentifier("stream-resolution-cancel")
        }
        .padding(12)
        .background(FottyTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: FottyTheme.radiusLG))
        .overlay {
            RoundedRectangle(cornerRadius: FottyTheme.radiusLG)
                .strokeBorder(FottyTheme.borderStrong, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, FottyTheme.bentoInset)
        .padding(.vertical, 8)
        .transition(.opacity)
        .accessibilityIdentifier("stream-resolution-panel")
    }
}
