import SwiftUI

/// Read the current accepted row each time. The retained player/sheet identity
/// is not a cached scorecard and cannot resurrect a missing/quarantined fixture.
@MainActor
enum CurrentSportsMatchContextPolicy {
    static func event(for identity: EventReference, in catalog: [EventReference], at now: Date) -> EventReference? {
        guard !identity.hasCatalogIdentityConflict, !identity.isBroadcastChannel,
              let current = CatalogPlaybackIdentity.matchingEvent(for: StreamPlaybackRequest(event: identity), in: catalog),
              !current.hasCatalogIdentityConflict,
              SportsHandoffIdentity.qualifiers(for: identity) == SportsHandoffIdentity.qualifiers(for: current),
              CricketMatchContextPolicy.context(for: current, at: now) != nil
                || UCLReportedScorePolicy.score(for: current, at: now) != nil else { return nil }
        if current.normalizedCategory == "cricket" {
            // A named-pair fallback cannot establish cricket format, ordinal
            // or squad. Only an accepted fixture identity can carry a scorecard.
            guard let previous = identity.cricketFixture, let latest = current.cricketFixture,
                  previous.fixtureID == latest.fixtureID, previous.competitionID == latest.competitionID,
                  previous.format == latest.format,
                  previous.homeTeamID == latest.homeTeamID, previous.awayTeamID == latest.awayTeamID else { return nil }
        }
        return current
    }
}

struct CurrentSportsMatchContextView: View {
    let event: EventReference

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            if let current = CurrentSportsMatchContextPolicy.event(for: event,
                in: MatchListViewModel.shared.matchContextCatalog, at: tick.date) {
                VStack(alignment: .leading, spacing: 12) {
                    CricketMatchContextView(event: current, at: tick.date)
                    UCLReportedScoreView(event: current, at: tick.date)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(FottyTheme.spacingMD)
                .bentoSurface(cornerRadius: FottyTheme.radiusMD)
            }
        }
    }
}
