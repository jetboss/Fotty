import SwiftUI

/// Compact, read-only innings context. The parent supplies a currently
/// reconciled fixture; this view never polls, opens media or changes status.
struct CricketMatchContextView: View {
    let event: EventReference
    var at: Date = Date()
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let context = CricketMatchContextPolicy.context(for: event, at: at) {
            VStack(alignment: .leading, spacing: 12) {
                heading(context)
                ForEach(context.innings.sorted(by: { $0.number < $1.number })) { innings in
                    inningsLayout {
                        HStack(spacing: 8) {
                            TeamBadgeWindow(teamName: teamName(for: innings.teamID),
                                badgeURL: teamBadge(for: innings.teamID), size: 28, triggerSearch: false)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(teamName(for: innings.teamID))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(FottyTheme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Innings \(innings.number)")
                                    .font(.caption)
                                    .foregroundStyle(FottyTheme.textSecondary)
                            }
                        }
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 12) }
                        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                            Text("\(innings.runs)/\(innings.wickets)")
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .foregroundStyle(FottyTheme.textPrimary)
                            if let overs = innings.overs {
                                Text("\(overs) overs")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(FottyTheme.textSecondary)
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(inningsDescription(innings))
                }
                if let message = context.message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let observedAt = event.cricketFixture?.observedAt {
                    Text("ICC · Reported \(observedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(FottyTheme.textSecondary)
                }
            }
            .accessibilityIdentifier("cricket-match-context")
        }
    }

    private func heading(_ context: CricketMatchContext) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Scorecard").font(.headline)
                Spacer(minLength: 0)
                Text(phaseTitle(context)).font(.subheadline)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Scorecard").font(.headline)
                Text(phaseTitle(context)).font(.subheadline)
            }
        }
        .foregroundStyle(FottyTheme.textPrimary)
        .accessibilityAddTraits(.isHeader)
    }

    private var inningsLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }

    private func teamName(for id: String) -> String {
        id == event.cricketFixture?.homeTeamID ? event.homeName : event.awayName
    }

    private func teamBadge(for id: String) -> URL? {
        id == event.cricketFixture?.homeTeamID ? event.homeBadgeURL : event.awayBadgeURL
    }

    private func phaseTitle(_ context: CricketMatchContext) -> String {
        [event.cricketFixture?.format.rawValue,
         context.day.map { "Day \($0)" }, context.phase?.title].compactMap { $0 }.joined(separator: " · ")
    }

    private func inningsDescription(_ innings: CricketMatchContext.Innings) -> String {
        var description = "\(teamName(for: innings.teamID)), innings \(innings.number), \(innings.runs) runs, \(innings.wickets) wickets"
        if let overs = innings.overs { description += ", \(overs) overs" }
        return description
    }
}
