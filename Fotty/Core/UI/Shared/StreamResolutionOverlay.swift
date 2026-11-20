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
                    if let subtitle, !subtitle.isEmpty {
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
                .accessibilityLabel("Cancel stream lookup")
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

/// A failed Watch lookup stays where its "looking" panel was, names the match
/// and offers what can actually happen next. It is not modal: browsing,
/// reminders and the rest of the lineup stay usable while it is shown.
/// Actions only reuse the existing owner paths (Retry, source settings,
/// details); this view never decides which source is tried or in what order.
struct WatchFailurePanel: View {
    static let title = "No stream found yet"

    let matchTitle: String
    let message: String
    var onRetry: (() -> Void)? = nil
    var onManageSources: (() -> Void)? = nil
    var onDetails: (() -> Void)? = nil
    let onDismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "play.slash")
                    .font(.title3)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FottyTheme.textPrimary)
                    Text(matchTitle)
                        .font(FottyTheme.typeCaption)
                        .foregroundStyle(FottyTheme.textPrimary)
                    Text(message)
                        .font(FottyTheme.typeCaption)
                        .foregroundStyle(FottyTheme.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FottyTheme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FottyPressButtonStyle())
                .padding(.top, -10).padding(.trailing, -10)
                .accessibilityLabel("Dismiss")
                .accessibilityIdentifier("watch-failure-dismiss")
            }

            if onRetry != nil || onManageSources != nil || onDetails != nil {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) { actions }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { actions; Spacer(minLength: 0) }
                        VStack(alignment: .leading, spacing: 4) { actions }
                    }
                }
            }
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch-failure-panel")
        .onAppear {
            // The alert this replaces took VoiceOver focus by itself.
            AccessibilityNotification.Announcement("\(Self.title). \(matchTitle)").post()
        }
    }

    @ViewBuilder
    private var actions: some View {
        if let onRetry {
            Button(action: onRetry) {
                Label("Try again", systemImage: "arrow.clockwise")
                    .font(FottyTheme.typeAction)
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(FottyTheme.accent, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusFull))
            .accessibilityLabel("Try again: \(matchTitle)")
            .accessibilityIdentifier("watch-failure-retry")
        }
        if let onManageSources {
            secondaryButton("Sources", identifier: "watch-failure-sources", action: onManageSources)
                .accessibilityHint("Opens playback source settings")
        }
        if let onDetails {
            secondaryButton("Match details", identifier: "watch-failure-details", action: onDetails)
        }
    }

    private func secondaryButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(FottyTheme.typeAction)
            .foregroundStyle(FottyTheme.accentText)
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .buttonStyle(FottyPressButtonStyle())
            .accessibilityIdentifier(identifier)
    }
}
