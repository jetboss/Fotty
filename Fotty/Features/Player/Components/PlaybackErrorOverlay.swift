import SwiftUI
import Foundation

struct PlaybackErrorOverlay: View {
    let title: String
    let message: String
    var viewModel: LivePlayerViewModel
    let sourceRecoveryButtonTitle: String
    let dismiss: DismissAction
    let isCompact: Bool
    let onRetry: () -> Void
    let onShowBroadcastSources: () -> Void
    @State private var showsFeedback = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
                    .lineLimit(isCompact ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: isCompact ? 310 : 420)

                if !viewModel.sources.isEmpty {
                    Button {
                        onRetry()
                    } label: {
                        Label("Try this source again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(FottyPrimaryButtonStyle())

                    if viewModel.sources.count > 1 && !isCompact {
                        Button {
                            onShowBroadcastSources()
                        } label: {
                            Label(sourceRecoveryButtonTitle, systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .buttonStyle(FottySecondaryButtonStyle())
                    }
                }

                if !isCompact {
                    Button("Report this problem") { showsFeedback = true }
                        .font(FottyTheme.typeAction)
                        .foregroundStyle(FottyTheme.accentText)
                        .frame(minHeight: 44)
                    Button("Close player") { dismiss() }
                        .font(FottyTheme.typeAction)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .frame(minHeight: 44)
                }
            }
            .padding(isCompact ? 12 : 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("playback-error")
        .sheet(isPresented: $showsFeedback) { FottyFeedbackSheet(area: .playback) }
    }
}
