import SwiftUI

struct MatchTimelineView: View {
    let events: [FottyMatchEvent]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(FottyTheme.accentText)
                Text("Match timeline")
                    .font(FottyTheme.typeModuleTitle)
                    .foregroundStyle(FottyTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            
            VStack(spacing: 0) {
                if events.isEmpty {
                    Text("Timeline will update with match events")
                        .font(FottyTheme.typeMeta)
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
    @ScaledMetric(relativeTo: .caption) private var minuteWidth: CGFloat = 32
    
    var body: some View {
        HStack(spacing: 16) {
            Text("\(event.minute)'")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(FottyTheme.textSecondary)
                .frame(width: minuteWidth)
            
            Circle()
                .fill(eventColor)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(FottyTheme.border, lineWidth: 1)
                )
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.player ?? "Action")
                    .font(FottyTheme.typeModuleTitle)
                    .foregroundStyle(FottyTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let detail = event.detail {
                    Text(detail)
                        .font(FottyTheme.typeMeta)
                        .foregroundStyle(FottyTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Spacer()
            
            Text(eventIcon)
                .font(.body)
        }
        .padding()
        .accessibilityElement(children: .combine)
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
