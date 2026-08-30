import SwiftUI

/// Compact cross-sport “what’s on” strip — glanceable, not a second Home screen.
struct OnNowGlanceBar: View {
    let liveEvents: [AnalyticalDataEngine.EventReference]
    let soonEvents: [AnalyticalDataEngine.EventReference]
    let onSelect: (AnalyticalDataEngine.EventReference) -> Void
    var onSelectSport: ((String) -> Void)? = nil
    /// Optional “surprise me” pick (usually a live match, followed-first).
    var surpriseEvent: AnalyticalDataEngine.EventReference? = nil
    
    private var diversifiedLive: [AnalyticalDataEngine.EventReference] {
        Self.diversifyBySport(liveEvents, limit: 4)
    }
    
    private var diversifiedSoon: [AnalyticalDataEngine.EventReference] {
        let liveIDs = Set(diversifiedLive.map(\.id))
        return Self.diversifyBySport(
            soonEvents.filter { !liveIDs.contains($0.id) },
            limit: 3
        )
    }
    
    private var chips: [GlanceChip] {
        var items: [GlanceChip] = []
        
        if !liveEvents.isEmpty || !soonEvents.isEmpty {
            items.append(.summary(live: liveEvents.count, soon: soonEvents.count))
        }
        
        if let surpriseEvent, !liveEvents.isEmpty {
            items.append(.surprise(surpriseEvent))
        }
        
        for event in diversifiedLive {
            items.append(.event(event, kind: .live))
        }
        
        let remainingSlots = max(0, 7 - items.count)
        for event in diversifiedSoon.prefix(remainingSlots) {
            items.append(.event(event, kind: .soon))
        }
        
        return items
    }
    
    var body: some View {
        if chips.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        chipView(chip)
                    }
                }
            }
            .frame(height: 32)
        }
    }
    
    /// Prefer sport variety so football doesn’t bury basketball/NHL when mixed.
    static func diversifyBySport(
        _ events: [AnalyticalDataEngine.EventReference],
        limit: Int
    ) -> [AnalyticalDataEngine.EventReference] {
        guard !events.isEmpty else { return [] }
        var perSport: [String: [AnalyticalDataEngine.EventReference]] = [:]
        var sportOrder: [String] = []
        for event in events {
            let sport = event.normalizedCategory
            if perSport[sport] == nil {
                sportOrder.append(sport)
                perSport[sport] = []
            }
            perSport[sport]?.append(event)
        }
        
        var result: [AnalyticalDataEngine.EventReference] = []
        var indices = Dictionary(uniqueKeysWithValues: sportOrder.map { ($0, 0) })
        while result.count < limit {
            var added = false
            for sport in sportOrder {
                guard result.count < limit else { break }
                let idx = indices[sport] ?? 0
                let bucket = perSport[sport] ?? []
                guard idx < bucket.count else { continue }
                // Cap 2 per sport in the first pass of chips.
                if idx >= 2, result.count + 1 < limit, sportOrder.contains(where: {
                    (indices[$0] ?? 0) < (perSport[$0]?.count ?? 0) && $0 != sport
                }) {
                    continue
                }
                result.append(bucket[idx])
                indices[sport] = idx + 1
                added = true
            }
            if !added { break }
        }
        return result
    }
    
    @ViewBuilder
    private func chipView(_ chip: GlanceChip) -> some View {
        switch chip {
        case .summary(let live, let soon):
            HStack(spacing: 6) {
                if live > 0 {
                    Circle()
                        .fill(FottyTheme.accent)
                        .frame(width: 6, height: 6)
                    Text(live == 1 ? "1 live" : "\(live) live")
                        .font(.fottyScaled(size: 11, weight: .bold))
                        .foregroundStyle(FottyTheme.textPrimary)
                }
                if soon > 0 {
                    if live > 0 {
                        Text("·")
                            .font(.fottyScaled(size: 11, weight: .medium))
                            .foregroundStyle(FottyTheme.textTertiary)
                            .accessibilityHidden(true)
                    }
                    Text(soon == 1 ? "1 soon" : "\(soon) soon")
                        .font(.fottyScaled(size: 11, weight: .semibold))
                        .foregroundStyle(FottyTheme.textSecondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(FottyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            
        case .surprise(let event):
            Button {
                onSelectSport?(event.normalizedCategory)
                onSelect(event)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "shuffle")
                        .font(.fottyScaled(size: 9, weight: .bold))
                        .foregroundStyle(FottyTheme.accentText)
                    Text("Pick for me")
                        .font(.fottyScaled(size: 11, weight: .bold))
                        .foregroundStyle(FottyTheme.textPrimary)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(FottyTheme.accent.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(FottyTheme.accent.opacity(0.4), lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            
        case .event(let event, let kind):
            Button {
                onSelectSport?(event.normalizedCategory)
                onSelect(event)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: AnalyticalDataEngine.sportIconName(for: event.normalizedCategory))
                        .font(.fottyScaled(size: 9, weight: .bold))
                        .foregroundStyle(kind == .live ? FottyTheme.accentText : FottyTheme.textTertiary)
                        .accessibilityHidden(true)
                    
                    Text(chipTitle(for: event, kind: kind))
                        .font(.fottyScaled(size: 11, weight: .semibold))
                        .foregroundStyle(FottyTheme.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(FottyTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(
                            kind == .live ? FottyTheme.accent.opacity(0.35) : FottyTheme.border.opacity(0.6),
                            lineWidth: 0.5
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
    
    private func chipTitle(for event: AnalyticalDataEngine.EventReference, kind: GlanceKind) -> String {
        let home = MatchCardFormatting.compactTeamName(event.homeName)
        let away = MatchCardFormatting.compactTeamName(event.awayName)
        let matchup = "\(home) · \(away)"
        switch kind {
        case .live:
            return matchup
        case .soon:
            if let date = event.kickoffDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "h:mm a"
                return "\(formatter.string(from: date)) · \(matchup)"
            }
            return matchup
        }
    }
}

private enum GlanceKind {
    case live
    case soon
}

private enum GlanceChip: Identifiable {
    case summary(live: Int, soon: Int)
    case surprise(AnalyticalDataEngine.EventReference)
    case event(AnalyticalDataEngine.EventReference, kind: GlanceKind)
    
    var id: String {
        switch self {
        case .summary(let live, let soon):
            return "summary-\(live)-\(soon)"
        case .surprise(let event):
            return "surprise-\(event.id)"
        case .event(let event, let kind):
            return "\(kind)-\(event.id)"
        }
    }
}
