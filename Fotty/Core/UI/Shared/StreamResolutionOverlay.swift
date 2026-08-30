import SwiftUI

struct StreamResolutionOverlay: View {
    let statusMessage: String
    let subtitle: String?
    let technicalSummary: String?
    let isMultiStream: Bool
    let multiTitles: [String]
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            
            VStack(spacing: FottyTheme.spacingMD) {
                FootballLoadingView(size: 60, label: "")
                    .tint(FottyTheme.liveAccent)
                    .scaleEffect(1.5)
                
                Text(statusMessage)
                    .lineLimit(2)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                
                if isMultiStream {
                    VStack(spacing: 6) {
                        ForEach(multiTitles, id: \.self) { title in
                            Text(title)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.68))
                                .multilineTextAlignment(.center)
                        }
                    }
                } else if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                    
                    if let technicalSummary = technicalSummary, !technicalSummary.isEmpty {
                        Text(technicalSummary)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                }
                
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.top, 8)
            }
            .padding(FottyTheme.spacingXL)
            .glassBackground(cornerRadius: FottyTheme.radiusLG)
            .padding(FottyTheme.spacingLG)
        }
        .transition(.opacity)
        .environment(\.colorScheme, .dark)
    }
}
