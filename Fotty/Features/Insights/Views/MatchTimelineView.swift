import SwiftUI

struct MatchTimelineView: View {
    let events: [FottyMatchEvent]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(FottyTheme.accentText)
                Text("MATCH TIMELINE")
                    .font(.system(size: 12, weight: .black))
                    .tracking(1)
            }
            
            VStack(spacing: 0) {
                if events.isEmpty {
                    Text("Timeline will update with match events")
                        .font(.system(size: 12))
                        .foregroundStyle(FottyTheme.textTertiary)
                        .padding()
                } else {
                    ForEach(events.sorted(by: { $0.minute < $1.minute })) { event in
                        TimelineEventRow(event: event)
                    }
                }
            }
            .background(FottyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }
}

struct TimelineEventRow: View {
    let event: FottyMatchEvent
    
    var body: some View {
        HStack(spacing: 16) {
            Text("\(event.minute)'")
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundStyle(FottyTheme.textSecondary)
                .frame(width: 32)
            
            Circle()
                .fill(eventColor)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(FottyTheme.border, lineWidth: 1)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.player ?? "Action")
                    .font(.system(size: 14, weight: .bold))
                
                if let detail = event.detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(FottyTheme.textTertiary)
                }
            }
            
            Spacer()
            
            Text(eventIcon)
                .font(.system(size: 16))
        }
        .padding()
    }
    
    private var eventColor: Color {
        switch event.type {
        case .goal, .penalty: return .green
        case .redCard: return .red
        case .yellowCard: return .yellow
        case .substitution: return .blue
        default: return FottyTheme.textTertiary
        }
    }
    
    private var eventIcon: String {
        switch event.type {
        case .goal, .penalty: return "⚽️"
        case .redCard: return "🟥"
        case .yellowCard: return "🟨"
        case .substitution: return "🔄"
        case .varDecision: return "🖥️"
        default: return "•"
        }
    }
}
