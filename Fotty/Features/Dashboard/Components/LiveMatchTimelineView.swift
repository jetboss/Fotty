import SwiftUI

struct LiveMatchTimelineView: View {
    let events: [FootballMatchEvent]
    let homeTeamId: Int?
    let awayTeamId: Int?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if events.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
                        ForEach(events.sorted(by: { $0.sortOrder < $1.sortOrder })) { event in
                            LiveTimelineRow(event: event, isHome: event.teamId == homeTeamId)
                        }
                    }
                    .padding(.vertical, FottyTheme.spacingLG)
                    .padding(.horizontal, FottyTheme.spacingMD)
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: FottyTheme.spacingMD) {
            Spacer()
            Image(systemName: "clock.badge.exclamationmark")
                .font(.fottyScaled(size: 32))
                .foregroundStyle(FottyTheme.textSecondary)
                .opacity(0.5)
            
            Text("No major events yet")
                .font(.fottyScaled(size: 15, weight: .medium))
                .foregroundStyle(FottyTheme.textSecondary)
            
            Text("Detailed match highlights will appear here as they happen.")
                .font(.fottyScaled(size: 13))
                .foregroundStyle(FottyTheme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LiveTimelineRow: View {
    let event: FootballMatchEvent
    let isHome: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: FottyTheme.spacingMD) {
            // Minute
            Text("\(event.minute)'")
                .font(.fottyScaled(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(FottyTheme.accentText)
                .frame(width: 40, alignment: .trailing)
            
            // Icon / Line
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(FottyTheme.surfaceElevated)
                        .frame(width: 32, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(FottyTheme.border, lineWidth: 0.5)
                        )
                    
                    Text(event.type.icon)
                        .font(.fottyScaled(size: 16))
                }
            }
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(event.player ?? "Unknown Player")
                    .font(.fottyScaled(size: 15, weight: .semibold))
                    .foregroundStyle(FottyTheme.textPrimary)
                
                if let assist = event.assist, !assist.isEmpty {
                    Text("Assist: \(assist)")
                        .font(.fottyScaled(size: 12))
                        .foregroundStyle(FottyTheme.textSecondary)
                } else if let info = event.info, !info.isEmpty {
                    Text(info)
                        .font(.fottyScaled(size: 12))
                        .foregroundStyle(FottyTheme.textSecondary)
                }
            }
            
            Spacer()
        }
    }
}
