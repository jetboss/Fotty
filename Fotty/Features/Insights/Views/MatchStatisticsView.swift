import SwiftUI

struct MatchStatisticsView: View {
    let stats: [FottyStatistic]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(FottyTheme.accentText)
                Text("Match statistics")
                    .font(FottyTheme.typeModuleTitle)
                    .foregroundStyle(FottyTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            
            VStack(spacing: 20) {
                if stats.isEmpty {
                    Text("Detailed stats available after kickoff")
                        .font(FottyTheme.typeMeta)
                        .foregroundStyle(FottyTheme.textTertiary)
                        .padding()
                } else {
                    ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                        StatRow(stat: stat)
                    }
                }
            }
            .padding(20)
            .background(FottyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }
}

struct StatRow: View {
    let stat: FottyStatistic
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    var body: some View {
        VStack(spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                statisticTitle
            }
            HStack {
                Text(stat.homeValue)
                    .font(.body.weight(.semibold))
                Spacer()
                if !dynamicTypeSize.isAccessibilitySize { statisticTitle }
                Spacer()
                Text(stat.awayValue)
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(FottyTheme.textPrimary)
            .monospacedDigit()
            
            GeometryReader { geo in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(FottyTheme.accent)
                        .frame(width: geo.size.width * CGFloat(stat.homePercentage))
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(FottyTheme.textTertiary.opacity(0.3))
                        .frame(width: geo.size.width * CGFloat(1.0 - stat.homePercentage))
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stat.type)
        .accessibilityValue("Home \(stat.homeValue), away \(stat.awayValue)")
    }

    private var statisticTitle: some View {
        Text(stat.type)
            .font(FottyTheme.typeMeta.weight(.semibold))
            .foregroundStyle(FottyTheme.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}
