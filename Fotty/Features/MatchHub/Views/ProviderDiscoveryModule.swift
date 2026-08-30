import SwiftUI

struct ProviderDiscoveryModule: View {
    let providers: [String]
    
    var body: some View {
        Group {
            if providers.isEmpty {
                compactScanningRow
            } else {
                providersCard
            }
        }
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    /// Single-line status so Arena tab leaves more vertical room for chat.
    private var compactScanningRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FottyTheme.accentText)
            ProgressView()
                .scaleEffect(0.78)
            Text("Scanning global sources…")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FottyTheme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, FottyTheme.spacingMD)
        .padding(.vertical, 10)
    }
    
    private var providersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(FottyTheme.accentText)
                Text("AVAILABLE SOURCES")
                    .font(.system(size: 12, weight: .black))
                    .tracking(1)
                
                Spacer()
                
                Text("\(providers.count) PROVIDERS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FottyTheme.textTertiary)
            }
            
            FlowLayout(spacing: 8) {
                ForEach(providers, id: \.self) { provider in
                    providerBadge(provider)
                }
            }
        }
        .padding()
    }
    
    private func providerBadge(_ name: String) -> some View {
        Text(name.uppercased())
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(FottyTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(color(for: name).opacity(0.15))
                    .overlay(
                        Capsule()
                            .strokeBorder(color(for: name).opacity(0.35), lineWidth: 1)
                    )
            )
    }
    
    private func color(for provider: String) -> Color {
        let p = provider.lowercased()
        if p.contains("streamex") { return .red }
        if p.contains("vip") { return .blue }
        if p.contains("meth") { return .green }
        if p.contains("p2p") { return .orange }
        return FottyTheme.accent
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, currentX)
        }
        
        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
