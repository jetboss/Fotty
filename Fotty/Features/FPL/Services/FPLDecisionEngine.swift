import Foundation

public enum FPLFreeTransferEstimator {
    public static func estimate(
        history: FPLManagerHistoryResponse?,
        targetGameweek: Int,
        startedEvent: Int? = nil,
        maximum: Int = FPLTransferRules.maximumBankedFreeTransfers
    ) -> FPLFreeTransferEstimate {
        guard targetGameweek > 1 else {
            return FPLFreeTransferEstimate(
                count: maximum,
                targetGameweek: targetGameweek,
                explanation: "Transfers are unlimited before a manager's first deadline.",
                isExact: true
            )
        }

        let firstEvent = max(1, startedEvent ?? 1)
        let completed = (history?.current ?? [])
            .filter { ($0.event ?? 0) >= firstEvent && ($0.event ?? 0) < targetGameweek }
            .sorted { ($0.event ?? 0) < ($1.event ?? 0) }
        let chipByEvent = Dictionary(
            uniqueKeysWithValues: (history?.chips ?? []).map { ($0.event, $0.name.lowercased()) }
        )

        var banked = 1
        for week in completed {
            guard let event = week.event else { continue }
            if event == firstEvent {
                banked = 1
                continue
            }

            let chip = chipByEvent[event]
            if chip == "wildcard" || chip == "freehit" {
                // Current rules preserve previously banked transfers, while the
                // transfer awarded for the chip week is consumed by activation.
                banked = min(maximum, max(1, banked))
                continue
            }

            let used = max(0, week.eventTransfers ?? 0)
            banked = min(maximum, max(1, banked - used + 1))
        }

        return FPLFreeTransferEstimate(
            count: banked,
            targetGameweek: targetGameweek,
            explanation: "Estimated from public transfer and chip history; official FPL remains the authority before confirming moves.",
            isExact: false
        )
    }
}

public enum FPLProjectionEngine {
    public static let modelVersion = "fotty-heuristic-2.0.0"

    public static func project(
        player: FPLPlayer,
        fixtures: [FPLFixture],
        startGameweek: Int,
        horizon: Int = 5
    ) -> FPLPlayerProjection {
        let boundedHorizon = min(8, max(1, horizon))
        let form = Double(player.form) ?? 0
        let pointsPerGame = Double(player.pointsPerGame) ?? 0
        let basePerFixture = max(0, pointsPerGame * 0.55 + form * 0.45)
        let availability = availabilityFactor(player)
        let expectedMinutesPerFixture = Int((baselineMinutesPerFixture(player) * availability).rounded())
        let confidence = confidence(for: player)
        var pointsByGameweek = [Int: Double]()
        var minutesByGameweek = [Int: Int]()
        var sourceByGameweek = [Int: FPLProjectionSource]()
        var assumptions = [String]()

        for gameweek in startGameweek..<(startGameweek + boundedHorizon) {
            let games = fixtures.filter { $0.event == gameweek && ($0.teamH == player.team || $0.teamA == player.team) }
            guard !games.isEmpty else {
                pointsByGameweek[gameweek] = 0
                minutesByGameweek[gameweek] = 0
                sourceByGameweek[gameweek] = .fottyEstimate
                continue
            }
            minutesByGameweek[gameweek] = expectedMinutesPerFixture * games.count

            if gameweek == startGameweek,
               let officialNext = player.officialExpectedPointsNext,
               officialNext > 0 {
                pointsByGameweek[gameweek] = officialNext * availability
                sourceByGameweek[gameweek] = .officialBlend
                assumptions.append("GW\(gameweek) starts from FPL's ep_next field.")
                continue
            }

            let minutesFactor = Double(expectedMinutesPerFixture) / 90
            let modeled = games.reduce(0.0) { total, fixture in
                let isHome = fixture.teamH == player.team
                let difficulty = isHome ? fixture.teamHDifficulty : fixture.teamADifficulty
                let fixtureFactor = max(0.60, min(1.40, 1.50 - Double(difficulty) * 0.18 + (isHome ? 0.06 : 0)))
                return total + basePerFixture * fixtureFactor * minutesFactor
            }
            pointsByGameweek[gameweek] = modeled
            sourceByGameweek[gameweek] = .fottyEstimate
        }

        if availability < 1 {
            assumptions.append("Availability scales the projection to \(Int(availability * 100))% from the current FPL flag.")
        }
        assumptions.append("Expected minutes use observed starts and minutes, then the current official availability flag.")
        assumptions.append("Future gameweeks blend official form, points per match, fixture count, FDR and expected minutes; they are Fotty estimates.")

        return FPLPlayerProjection(
            player: player,
            gameweekPoints: pointsByGameweek,
            expectedMinutes: minutesByGameweek,
            sourceByGameweek: sourceByGameweek,
            total: pointsByGameweek.values.reduce(0, +),
            confidence: confidence,
            modelVersion: modelVersion,
            assumptions: assumptions
        )
    }

    public static func compareSwap(
        playerOut: FPLPlayer,
        playerIn: FPLPlayer,
        fixtures: [FPLFixture],
        startGameweek: Int,
        horizon: Int
    ) -> Double {
        project(player: playerIn, fixtures: fixtures, startGameweek: startGameweek, horizon: horizon).total
            - project(player: playerOut, fixtures: fixtures, startGameweek: startGameweek, horizon: horizon).total
    }

    private static func availabilityFactor(_ player: FPLPlayer) -> Double {
        if player.status == "u" || player.status == "s" || player.status == "i" { return 0 }
        if let chance = player.chanceOfPlayingNextRound {
            return Double(max(0, min(100, chance))) / 100
        }
        return player.status == "d" ? 0.75 : 1
    }

    private static func baselineMinutesPerFixture(_ player: FPLPlayer) -> Double {
        if player.status == "u" || player.status == "s" || player.status == "i" { return 0 }
        if player.starts > 0 {
            return max(1, min(90, Double(player.minutes) / Double(player.starts)))
        }
        if player.minutes > 0 {
            return max(1, min(90, Double(player.minutes)))
        }
        // With no current-season sample, use a conservative placeholder and
        // expose low confidence instead of presenting a false 90-minute claim.
        return 60
    }

    private static func confidence(for player: FPLPlayer) -> FPLProjectionConfidence {
        if availabilityFactor(player) == 0 || player.starts == 0 { return .low }
        if player.starts >= 4,
           player.status == "a",
           (player.chanceOfPlayingNextRound ?? 100) == 100 {
            return .high
        }
        return .medium
    }
}

public enum FPLDecisionEngine {
    private struct AutosubCandidate {
        let pick: FPLPick
        let player: FPLPlayer
        let stats: FPLLivePlayerStats
        let confirmedNoAppearance: Bool
    }

    private struct AutosubResolution {
        let multipliers: [Int: Int]
        let projectedSubs: [FPLAutomaticSub]
        let projectedCaptainElementID: Int?
    }

    public static func liveSquadSummary(
        gameweek: FPLGameweek,
        picks: FPLManagerPicks,
        live: FPLEventLiveResponse,
        players: [FPLPlayer],
        teams: [FPLTeam],
        fixtures: [FPLFixture]
    ) -> FPLLiveSquadSummary {
        let liveByID = uniqueScoringRows(live.elements, id: \.id).mapValues(\.stats)
        let playerByID = uniqueScoringRows(players, id: \.id)
        let teamByID = uniqueScoringRows(teams, id: \.id)
        let matchesGameweek = picks.entryHistory?.event == nil || picks.entryHistory?.event == gameweek.id
        let hasCompleteScoringData = matchesGameweek && picks.picks.count == 15
            && Set(picks.picks.map(\.element)).count == 15
            && Set(picks.picks.map(\.position)) == Set(1...15)
            && picks.picks.allSatisfy { pick in
                guard let player = playerByID[pick.element],
                      teamByID[player.team] != nil,
                      let stats = liveByID[pick.element] else { return false }
                return stats.minutes >= 0 && (1...4).contains(player.elementType)
                    && (0...3).contains(pick.multiplier)
            }
        let resolution = resolveAutosubs(
            gameweek: gameweek,
            picks: picks,
            liveByID: liveByID,
            playerByID: playerByID,
            fixtures: fixtures,
            hasCompleteScoringData: hasCompleteScoringData
        )
        let transferCost = max(0, picks.entryHistory?.eventTransfersCost ?? 0)
        let publishedLineupPoints: Int? = hasCompleteScoringData ? picks.picks.reduce(-transferCost) { total, pick in
            total + (liveByID[pick.element]?.totalPoints ?? 0) * max(0, pick.multiplier)
        } : nil
        let projectedPoints: Int? = hasCompleteScoringData ? picks.picks.reduce(-transferCost) { total, pick in
            total + (liveByID[pick.element]?.totalPoints ?? 0) * max(0, resolution.multipliers[pick.element] ?? pick.multiplier)
        } : nil
        let officialCurrentPoints = matchesGameweek ? (picks.entryHistory?.points ?? publishedLineupPoints) : nil
        let usesProjection = picks.automaticSubs.isEmpty
            && (!resolution.projectedSubs.isEmpty || resolution.projectedCaptainElementID != nil)
            && !(gameweek.finished && gameweek.dataChecked == true)
        let displayedPoints = usesProjection ? projectedPoints : officialCurrentPoints
        let activePicks = uniqueScoringRows(picks.picks, id: \.element).values.filter {
            matchesGameweek && max(0, resolution.multipliers[$0.element] ?? $0.multiplier) > 0
        }

        let rows = activePicks.compactMap { pick -> FPLLiveSquadPlayer? in
            guard let player = playerByID[pick.element],
                  let team = teamByID[player.team],
                  let stats = liveByID[pick.element], stats.minutes >= 0 else { return nil }
            let remaining = fixtures.contains { fixture in
                fixture.event == gameweek.id
                    && !fixture.finished
                    && fixture.finishedProvisional != true
                    && (fixture.teamH == player.team || fixture.teamA == player.team)
            }
            return FPLLiveSquadPlayer(
                pick: pick,
                player: player,
                team: team,
                stats: stats,
                effectiveMultiplier: max(0, resolution.multipliers[pick.element] ?? pick.multiplier),
                multipliedPoints: stats.totalPoints * max(0, resolution.multipliers[pick.element] ?? pick.multiplier),
                hasFixtureRemaining: remaining
            )
        }

        return FPLLiveSquadSummary(
            gameweek: gameweek.id,
            totalPoints: displayedPoints,
            officialCurrentPoints: officialCurrentPoints,
            publishedLineupPoints: publishedLineupPoints,
            hasCompleteScoringData: hasCompleteScoringData,
            transferCost: transferCost,
            playersPlayed: rows.filter { $0.stats.played == true || $0.stats.minutes > 0 }.count,
            playersRemaining: rows.filter(\.hasFixtureRemaining).count,
            officialBonus: rows.reduce(0) { $0 + $1.stats.bonus * $1.effectiveMultiplier },
            automaticSubs: picks.automaticSubs,
            projectedAutomaticSubs: resolution.projectedSubs,
            projectedCaptainElementID: resolution.projectedCaptainElementID,
            rows: rows.sorted { $0.pick.position < $1.pick.position },
            isFinal: gameweek.finished && gameweek.dataChecked == true
        )
    }

    private static func uniqueScoringRows<Row>(_ rows: [Row], id: KeyPath<Row, Int>) -> [Int: Row] {
        Dictionary(grouping: rows, by: { $0[keyPath: id] })
            .compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    private static func resolveAutosubs(
        gameweek: FPLGameweek,
        picks: FPLManagerPicks,
        liveByID: [Int: FPLLivePlayerStats],
        playerByID: [Int: FPLPlayer],
        fixtures: [FPLFixture],
        hasCompleteScoringData: Bool
    ) -> AutosubResolution {
        let published = Dictionary(picks.picks.map { ($0.element, max(0, $0.multiplier)) }, uniquingKeysWith: { first, _ in first })
        guard hasCompleteScoringData, picks.automaticSubs.isEmpty,
              !(gameweek.finished && gameweek.dataChecked == true) else {
            return AutosubResolution(
                multipliers: published,
                projectedSubs: [],
                projectedCaptainElementID: nil
            )
        }

        func appeared(_ stats: FPLLivePlayerStats) -> Bool {
            stats.played == true || stats.minutes > 0
        }

        func teamFixturesComplete(_ teamID: Int) -> Bool {
            let rows = fixtures.filter {
                $0.event == gameweek.id && ($0.teamH == teamID || $0.teamA == teamID)
            }
            return !rows.isEmpty && rows.allSatisfy { $0.finished || $0.finishedProvisional == true }
        }

        let candidates = picks.picks.compactMap { pick -> AutosubCandidate? in
            guard let player = playerByID[pick.element], let stats = liveByID[pick.element] else { return nil }
            return AutosubCandidate(
                pick: pick,
                player: player,
                stats: stats,
                confirmedNoAppearance: !appeared(stats) && teamFixturesComplete(player.team)
            )
        }
        var pairs = [(incoming: AutosubCandidate, outgoing: AutosubCandidate)]()

        // Bench Boost keeps all published multipliers. Ordinary gameweeks can
        // replace confirmed non-appearances in legal bench order.
        if picks.activeChip?.lowercased() != "bboost" {
            if let startingGoalkeeper = candidates.first(where: { $0.pick.position <= 11 && $0.player.elementType == 1 }),
               startingGoalkeeper.confirmedNoAppearance,
               let benchGoalkeeper = candidates.first(where: {
                   $0.pick.position > 11 && $0.player.elementType == 1 && appeared($0.stats)
               }) {
                pairs.append((benchGoalkeeper, startingGoalkeeper))
            }

            let missingOutfield = candidates.filter {
                $0.pick.position <= 11 && $0.player.elementType != 1 && $0.confirmedNoAppearance
            }
            let activeOutfield = candidates.filter {
                $0.pick.position <= 11 && $0.player.elementType != 1 && !$0.confirmedNoAppearance
            }
            let eligibleBench = candidates
                .filter { $0.pick.position > 11 && $0.player.elementType != 1 && appeared($0.stats) }
                .sorted { $0.pick.position < $1.pick.position }
            let selectedBench = preferredOutfieldSubs(
                active: activeOutfield,
                eligibleBench: eligibleBench,
                vacancies: missingOutfield.count
            )
            var unmatchedOutgoing = missingOutfield.sorted { $0.pick.position < $1.pick.position }
            for incoming in selectedBench {
                let samePosition = unmatchedOutgoing.firstIndex { $0.player.elementType == incoming.player.elementType }
                let index = samePosition ?? unmatchedOutgoing.startIndex
                guard unmatchedOutgoing.indices.contains(index) else { break }
                pairs.append((incoming, unmatchedOutgoing.remove(at: index)))
            }
        }

        var effective = published
        if picks.activeChip?.lowercased() != "bboost" {
            for candidate in candidates where candidate.pick.position <= 11 && candidate.confirmedNoAppearance {
                effective[candidate.pick.element] = 0
            }
        }
        for pair in pairs {
            effective[pair.outgoing.pick.element] = 0
            effective[pair.incoming.pick.element] = 1
        }
        var projectedCaptainElementID: Int?
        if let captain = candidates.first(where: { $0.pick.isCaptain }) {
            let captainMultiplier = max(2, captain.pick.multiplier)
            if effective[captain.pick.element, default: 0] > 0 && !captain.confirmedNoAppearance {
                effective[captain.pick.element] = captainMultiplier
            } else if let vice = candidates.first(where: { $0.pick.isViceCaptain }),
                      appeared(vice.stats),
                      effective[vice.pick.element, default: 0] > 0 {
                effective[captain.pick.element] = 0
                effective[vice.pick.element] = captainMultiplier
                projectedCaptainElementID = vice.pick.element
            }
        }

        return AutosubResolution(
            multipliers: effective,
            projectedSubs: pairs.map {
                FPLAutomaticSub(
                    entry: nil,
                    elementIn: $0.incoming.pick.element,
                    elementOut: $0.outgoing.pick.element,
                    event: gameweek.id
                )
            },
            projectedCaptainElementID: projectedCaptainElementID
        )
    }

    private static func preferredOutfieldSubs(
        active: [AutosubCandidate],
        eligibleBench: [AutosubCandidate],
        vacancies: Int
    ) -> [AutosubCandidate] {
        let maximum = min(vacancies, eligibleBench.count)
        for count in stride(from: maximum, through: 0, by: -1) {
            for selection in combinations(of: eligibleBench, choosing: count) {
                if isLegalOutfieldFormation(active + selection) { return selection }
            }
        }
        return []
    }

    private static func combinations<T>(of values: [T], choosing count: Int) -> [[T]] {
        guard count > 0 else { return [[]] }
        guard count <= values.count else { return [] }
        if count == values.count { return [values] }
        var result = [[T]]()
        func visit(_ start: Int, _ current: [T]) {
            if current.count == count {
                result.append(current)
                return
            }
            guard start < values.count else { return }
            let upperBound = values.count - (count - current.count)
            guard start <= upperBound else { return }
            for index in start...upperBound {
                visit(index + 1, current + [values[index]])
            }
        }
        visit(0, [])
        return result
    }

    private static func isLegalOutfieldFormation(_ players: [AutosubCandidate]) -> Bool {
        let defenders = players.filter { $0.player.elementType == 2 }.count
        let midfielders = players.filter { $0.player.elementType == 3 }.count
        let forwards = players.filter { $0.player.elementType == 4 }.count
        return players.count <= 10
            && (3...5).contains(defenders)
            && (2...5).contains(midfielders)
            && (1...3).contains(forwards)
    }

    public static func commandCenter(
        phase: FPLGameweekPhase,
        gameweek: FPLGameweek?,
        picks: FPLManagerPicks?,
        scores: [PlayerScore],
        validation: FPLSquadValidationReport?,
        freeTransfers: FPLFreeTransferEstimate?,
        live: FPLLiveSquadSummary?,
        history: FPLManagerHistoryResponse?,
        now: Date = Date()
    ) -> FPLCommandCenterState {
        let squadIDs = Set(picks?.picks.map(\.element) ?? [])
        let playerByID = Dictionary(uniqueKeysWithValues: scores.map { ($0.player.id, $0.player) })
        let captainPick = picks?.picks.first(where: \.isCaptain)
        let captainName = captainPick.flatMap { playerByID[$0.element]?.webName }
        let flagged = scores.filter {
            squadIDs.contains($0.player.id) && ($0.player.status != "a" || !$0.player.news.isEmpty)
        }
        var actions = [FPLCommandCenterAction]()
        var metrics = [FPLCommandCenterMetric]()
        var warnings = flagged.prefix(4).map { "\($0.player.webName): \($0.player.news.isEmpty ? $0.availabilityRisk.rawValue : $0.player.news)" }
        if let validation, !validation.isValid {
            warnings.append(contentsOf: validation.issues.filter { $0.severity == .error }.prefix(3).map(\.message))
        }

        switch phase {
        case .planning:
            if let deadline = gameweek?.deadlineDate {
                metrics.append(metric("DEADLINE", deadlineCountdown(deadline, now: now), "Local time"))
            }
            metrics.append(metric("CAPTAIN", captainName ?? "Not set", captainPick == nil ? "Decision needed" : "Current squad"))
            if let freeTransfers {
                metrics.append(metric("EST. FT", "\(freeTransfers.count)", freeTransfers.isExact ? "Confirmed" : "Verify in FPL"))
            }
            if !flagged.isEmpty {
                actions.append(action("Resolve squad flags", "\(flagged.count) selected player(s) need an availability decision.", "cross.case.fill", 100, .transfers))
            }
            actions.append(action("Review captain", "Compare the leading captain options before the deadline.", "crown.fill", 90, .captain))
            if let freeTransfers {
                actions.append(action("Build transfer route", "Plan with about \(freeTransfers.count) free transfer\(freeTransfers.count == 1 ? "" : "s"); verify the count in official FPL.", "arrow.triangle.2.circlepath", 80, .transfers))
            }
            actions.append(action("Ask the smart coach", "Challenge the plan across fixtures, risk, chips and rivals.", "sparkles", 70, .coach))
        case .locked:
            metrics.append(metric("STARTING", "\(picks?.picks.filter { $0.position <= 11 }.count ?? 0)", "Lineup locked"))
            metrics.append(metric("CAPTAIN", captainName ?? "—", "Official squad"))
            metrics.append(metric("STATUS", "Locked", "Awaiting kickoff"))
            actions.append(action("Check the locked squad", "The deadline has passed; review the published lineup and captain.", "lock.fill", 100, .squad))
            actions.append(action("Prepare live tracking", "Official event-live data will populate as matches begin.", "bolt.fill", 80, .live))
        case .live:
            if let live {
                metrics.append(metric("LIVE POINTS", live.totalPoints.map(String.init) ?? "—", !live.hasCompleteScoringData ? "Incomplete player data" : (live.pointsAreProjected ? live.projectionLabel.capitalized : (live.isFinal ? "Final" : "Official feed"))))
                metrics.append(metric("REMAINING", live.hasCompleteScoringData ? "\(live.playersRemaining)" : "—", "Player fixtures"))
                let effectiveCaptainID = live.projectedCaptainElementID ?? captainPick?.element
                let effectiveCaptain = live.rows.first(where: { $0.player.id == effectiveCaptainID })
                metrics.append(metric(
                    "CAPTAIN",
                    effectiveCaptain.map { "\($0.multipliedPoints) pts" } ?? "—",
                    effectiveCaptain?.player.webName ?? captainName
                ))
                let detail = live.hasCompleteScoringData
                    ? "\(live.totalPoints.map(String.init) ?? "—") points, \(live.playersRemaining) active player fixture(s) remaining.\(live.pointsAreProjected ? " Pending rule changes are labeled provisional." : "")"
                    : "Player data is incomplete. Refresh before checking autosubs or a corrected total."
                actions.append(action("Follow live points", detail, "bolt.fill", 100, .live))
            } else {
                metrics.append(metric("LIVE POINTS", "—", "Waiting for official data"))
                metrics.append(metric("CAPTAIN", captainName ?? "—", "Official squad"))
            }
            actions.append(action("Check rival swings", "Compare published squads, captains and remaining players.", "swords", 90, .leagues))
        case .review:
            let latest = history?.current.last(where: { $0.event == gameweek?.id })
            metrics.append(metric("POINTS", "\(latest?.points ?? 0)", "Confirmed"))
            metrics.append(metric("BENCH", "\(latest?.pointsOnBench ?? 0)", "Points left"))
            metrics.append(metric("RANK", latest?.overallRank.map { "#\($0)" } ?? "—", "Overall"))
            actions.append(action("Review the gameweek", "\(latest?.points ?? 0) points, \(latest?.pointsOnBench ?? 0) left on the bench and \(latest?.eventTransfersCost ?? 0) transfer points spent.", "checkmark.seal.fill", 100, .live))
            actions.append(action("Plan the next horizon", "Turn the lessons into a five-gameweek route.", "calendar.badge.clock", 80, .planner))
        case .unavailable:
            actions.append(action("Refresh official data", "Fotty cannot determine the current gameweek phase.", "arrow.clockwise", 100, .squad))
        }

        let title = gameweek.map { "\($0.name) Command Center" } ?? "FPL Command Center"
        let subtitle: String
        switch phase {
        case .planning: subtitle = "Prioritize the decisions that must be settled before the deadline."
        case .locked: subtitle = "Your official team is locked; Fotty is switching from planning to monitoring."
        case .live: subtitle = "Official event-live points drive this matchday view."
        case .review: subtitle = "Use the confirmed outcome to improve the next decision, not to chase the last score."
        case .unavailable: subtitle = "Refresh the official FPL snapshot to resume planning."
        }
        return FPLCommandCenterState(
            phase: phase,
            title: title,
            subtitle: subtitle,
            metrics: metrics,
            actions: actions.sorted { $0.priority > $1.priority },
            warnings: warnings
        )
    }

    public static func review(
        gameweek: Int,
        picks: FPLManagerPicks,
        live: FPLLiveSquadSummary?,
        history: FPLManagerHistoryResponse?,
        players: [FPLPlayer]
    ) -> FPLGameweekReview? {
        guard let event = history?.current.first(where: { $0.event == gameweek }) else { return nil }
        let playerByID = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
        let captainPick = picks.picks.first(where: \.isCaptain)
        let captainRow = live?.rows.first(where: { $0.pick.element == captainPick?.element })
        let topRow = live?.rows.max(by: { $0.stats.totalPoints < $1.stats.totalPoints })
        return FPLGameweekReview(
            gameweek: gameweek,
            points: event.points ?? 0,
            overallRank: event.overallRank,
            transferCost: event.eventTransfersCost ?? 0,
            pointsOnBench: event.pointsOnBench ?? 0,
            captainName: captainPick.flatMap { playerByID[$0.element]?.webName },
            captainPoints: captainRow?.multipliedPoints,
            topScorerName: topRow?.player.webName,
            topScorerPoints: topRow?.stats.totalPoints,
            recordedAt: Date()
        )
    }

    private static func action(
        _ title: String,
        _ detail: String,
        _ symbol: String,
        _ priority: Int,
        _ destination: FPLCommandCenterAction.Destination
    ) -> FPLCommandCenterAction {
        FPLCommandCenterAction(title: title, detail: detail, symbol: symbol, priority: priority, destination: destination)
    }

    private static func metric(_ label: String, _ value: String, _ detail: String? = nil) -> FPLCommandCenterMetric {
        FPLCommandCenterMetric(label: label, value: value, detail: detail)
    }

    private static func deadlineCountdown(_ deadline: Date, now: Date) -> String {
        let interval = max(0, deadline.timeIntervalSince(now))
        let totalMinutes = Int(interval / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

@MainActor
public enum FPLReviewStore {
    public static func load(managerID: Int, season: String = FPLSeasonIdentifier.currentLabel()) -> [FPLGameweekReview] {
        guard let data = UserDefaults.standard.data(forKey: key(managerID: managerID, season: season)),
              let reviews = try? JSONDecoder().decode([FPLGameweekReview].self, from: data) else {
            return []
        }
        return reviews.sorted { $0.gameweek > $1.gameweek }
    }

    public static func upsert(
        _ review: FPLGameweekReview,
        managerID: Int,
        season: String = FPLSeasonIdentifier.currentLabel()
    ) -> [FPLGameweekReview] {
        var reviews = load(managerID: managerID, season: season)
        reviews.removeAll { $0.gameweek == review.gameweek }
        reviews.append(review)
        reviews.sort { $0.gameweek > $1.gameweek }
        if let data = try? JSONEncoder().encode(reviews) {
            UserDefaults.standard.set(data, forKey: key(managerID: managerID, season: season))
        }
        return reviews
    }

    private static func key(managerID: Int, season: String) -> String {
        "fotty.fpl.\(season).manager.\(managerID).reviews"
    }
}
