import SwiftUI

struct LoadingStateOverlay: View {
    var viewModel: LivePlayerViewModel
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.97)
                .ignoresSafeArea()

            if let source = viewModel.activeSource, viewModel.isP2PSource(source), !viewModel.isUsingWebEmbed {
                PlaybackWarmupView(
                    service: viewModel.warmupService,
                    source: source,
                    onCancel: {
                        viewModel.cancelLoading()
                    }
                )
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)

                    Text(viewModel.connectionPhase.isEmpty ? "Connecting..." : viewModel.connectionPhase)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Preparing broadcast \(viewModel.currentSourceIndex + 1)")
                        .font(FottyTheme.typeMeta)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .lineLimit(1)
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("stream-loading")
    }
}
