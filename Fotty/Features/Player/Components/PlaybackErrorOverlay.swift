import SwiftUI
import Foundation

struct PlaybackErrorOverlay: View {
    let title: String
    let message: String
    var viewModel: LivePlayerViewModel
    let sourceRecoveryButtonTitle: String
    let dismiss: () -> Void
    let isCompact: Bool
    let onRetry: () -> Void
    let onShowBroadcastSources: () -> Void
    @State private var showsFeedback = false

    // Focus/compact layouts need the same recovery route as the full player.
    var offersAlternateSource: Bool { viewModel.sources.count > 1 }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
              VStack(spacing: isCompact ? 8 : 16) {
                Image(systemName: "tv.slash")
                    .font(.fottyScaled(size: isCompact ? 26 : 40))
                    .foregroundStyle(FottyTheme.textTertiary)

                Text(title)
                    .font(isCompact ? FottyTheme.typeModuleTitle : FottyTheme.typeSectionTitle)
                    .foregroundStyle(FottyTheme.textPrimary)

                Text(message)
                    .font(isCompact ? FottyTheme.typeCaption : FottyTheme.typeBody)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: isCompact ? 310 : 420)

                if !viewModel.sources.isEmpty {
                    Button {
                        onRetry()
                    } label: {
                        Label(isCompact ? "Retry" : "Try this source again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(FottyPrimaryButtonStyle())
                    .accessibilityIdentifier("playback-error-retry")

                    if offersAlternateSource {
                        Button {
                            onShowBroadcastSources()
                        } label: {
                            Label(isCompact ? "Sources" : sourceRecoveryButtonTitle, systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .buttonStyle(FottySecondaryButtonStyle())
                        .accessibilityLabel(sourceRecoveryButtonTitle)
                        .accessibilityIdentifier("playback-error-sources")
                    }
                }

                if !isCompact {
                    Button { showsFeedback = true } label: {
                        Text("Report this problem")
                            .font(FottyTheme.typeAction)
                            .foregroundStyle(FottyTheme.accentText)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(FottyPressButtonStyle())
                    Button { dismiss() } label: {
                        Text("Close player")
                            .font(FottyTheme.typeAction)
                            .foregroundStyle(FottyTheme.textSecondary)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(FottyPressButtonStyle())
                }
              }
              .padding(isCompact ? 12 : 32)
              .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.center, for: .alignment)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("playback-error")
        .sheet(isPresented: $showsFeedback) {
            FottyFeedbackSheet(
                area: .playback,
                initialExpected: "I was watching a live broadcast and expected playback to continue.",
                initialActual: "Playback stopped or did not start, and Fotty showed the recovery screen."
            )
        }
    }
}
