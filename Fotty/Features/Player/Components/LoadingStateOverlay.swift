import SwiftUI

struct LoadingStateOverlay: View {
    var viewModel: LivePlayerViewModel
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.97)
                .ignoresSafeArea()

            PlaybackLoadingContent(
                phase: viewModel.connectionPhase,
                category: viewModel.event.normalizedCategory,
                competition: SportMotionContext.competition(for: viewModel.event)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("stream-loading")
        .environment(\.colorScheme, .dark)
    }
}

/// Adapt only the loading chrome, never the retained media surface or its owner.
/// A narrow 16:9 surface may not hold full artwork plus accessibility text.
struct PlaybackLoadingContent: View {
    let phase: String
    let category: String
    var competition: FootballCompetitionID? = nil

    var body: some View {
        ViewThatFits(in: .vertical) {
            fullPresentation
            compactPresentation
            // Preserve the complete current phase when even the compact row
            // cannot fit. Text remains scalable rather than being truncated.
            ScrollView(.vertical) {
                phaseText
                    .padding(12)
                    .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.center, for: .alignment)
            .accessibilityIdentifier("stream-loading-scrollable-status")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var fullPresentation: some View {
        VStack(spacing: 12) {
            artwork(size: 48)
            phaseText
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("stream-loading-full")
    }

    var compactPresentation: some View {
        HStack(spacing: 12) {
            artwork(size: 22)
            phaseText.frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("stream-loading-compact")
    }

    private func artwork(size: CGFloat) -> some View {
        SportLoadingView(category: category, size: size, label: "", competition: competition)
            .accessibilityHidden(true)
    }

    private var phaseText: some View {
        Text(phase.isEmpty ? "Connecting…" : phase)
            .font(.headline)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}
