import SwiftUI

struct FootballQuotaBanner: View {
    @Environment(LiveScoreService.self) private var scoreService

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(FottyTheme.accentText)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.fottyScaled(size: 14, weight: .semibold))
                    .foregroundStyle(FottyTheme.textPrimary)
                Text(message)
                    .font(.fottyScaled(size: 12))
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(FottyTheme.surface.opacity(0.95))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(10)
    }

    private var title: String {
        if scoreService.hasQuotaError { return "Live-score allowance reserved" }
        if scoreService.isUsingDelayedScoreFallback { return "Using delayed scores" }
        return "Live scores unavailable"
    }

    private var message: String {
        if scoreService.hasQuotaError {
            return "Fotty preserved the remaining API-Football allowance. Premier League scores continue through the delayed football-data backup."
        }
        if scoreService.isUsingDelayedScoreFallback {
            return "The dedicated Premier League live feed is not configured or unavailable. Scores are coming from football-data and may be delayed."
        }
        return "Premier League scores could not be refreshed. Schedules and streams remain available."
    }
}
