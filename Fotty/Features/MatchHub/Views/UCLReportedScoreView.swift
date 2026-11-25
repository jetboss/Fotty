import SwiftUI

/// Delayed, timestamped context beside the ordinary match information. It is
/// deliberately independent of current LIVE badges, goal alerts and playback.
struct UCLReportedScoreView: View {
    let event: EventReference
    var at: Date = Date()
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let score = UCLReportedScorePolicy.score(for: event, at: at), let publishedAt = score.publisherDate {
            VStack(alignment: .leading, spacing: 12) {
                Text("Latest reported score")
                    .font(.headline)
                    .foregroundStyle(FottyTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                teamRow(home: true, goals: score.home)
                teamRow(home: false, goals: score.away)
                VStack(alignment: .leading, spacing: 4) {
                    Text("May be delayed · Football-data.org")
                    Text("Reported \(publishedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))")
                }
                .font(.caption)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("ucl-reported-score")
        }
    }

    private func teamRow(home: Bool, goals: Int) -> some View {
        let name = home ? event.homeName : event.awayName
        return scoreLayout {
            HStack(spacing: 8) {
                TeamBadgeWindow(teamName: name, badgeURL: home ? event.homeBadgeURL : event.awayBadgeURL,
                                size: 28, triggerSearch: false)
                    .accessibilityHidden(true)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 12) }
            Text("\(goals)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .fixedSize()
        }
        .foregroundStyle(FottyTheme.textPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(goals) goals, latest reported score")
    }

    private var scoreLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }
}
