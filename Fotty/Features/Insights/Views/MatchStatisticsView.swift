import SwiftUI

struct MatchStatisticsView: View {
    let stats: [FottyStatistic]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(FottyTheme.accentText)
                Text("MATCH STATISTICS")
                    .font(.system(size: 12, weight: .black))
                    .tracking(1)
            }
            
            VStack(spacing: 20) {
                if stats.isEmpty {
                    Text("Detailed stats available after kickoff")
                        .font(.system(size: 12))
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
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(stat.homeValue)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                Spacer()
                Text(stat.type.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FottyTheme.textSecondary)
                Spacer()
                Text(stat.awayValue)
                    .font(.system(size: 14, weight: .black, design: .rounded))
            }
            
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
        }
    }
}
