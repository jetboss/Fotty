import Foundation

public struct AICoachMessage: Identifiable, Codable, Sendable {
    public let id: String
    public let sender: Sender
    public let text: String
    public let date: Date
    public let gameweek: Int?
    public let tag: String?
    public let coachCard: FPLCoachCardPayload?

    public enum Sender: String, Codable, Sendable {
        case user, coach
    }

    public init(
        id: String = UUID().uuidString,
        sender: Sender,
        text: String,
        date: Date = Date(),
        gameweek: Int? = nil,
        tag: String? = nil,
        coachCard: FPLCoachCardPayload? = nil
    ) {
        self.id = id
        self.sender = sender
        self.text = text
        self.date = date
        self.gameweek = gameweek
        self.tag = tag
        self.coachCard = coachCard
    }
}

public struct AIGameweekBriefing: Sendable {
    public let headline: String
    public let tacticalWarnings: [String]
    public let differentialGems: [String]
    public let rivalVulnerabilities: [String]
    public let topRecommendation: String
}

/// A deterministic, on-device explanation layer over Fotty's FPL models.
/// It deliberately performs no third-party AI networking and sends no manager data off device.
public enum FPLAICoachService {
    public static func deterministicResultIfApplicable(
        userQuery: String,
        managerSummary: FPLManagerSummary?,
        currentGw: FPLGameweek?,
        picks: FPLManagerPicks?,
        scores: [PlayerScore],
        freeTransfers: FPLFreeTransferEstimate?,
        live: FPLLiveSquadSummary?,
        players: [FPLPlayer],
        settings: FPLGameSettings?,
        freshness: FPLResourceMetadata?,
        publishedGameweek: Int? = nil
    ) async -> FPLSmartCoachResult? {
        let query = userQuery.lowercased()
        let judgmentMarkers = ["should i", "best", "recommend", "better", "worth", "who to buy", "who to sell"]
        guard isScoringQuery(query) || !judgmentMarkers.contains(where: query.contains) else { return nil }

        if isScoringQuery(query), live?.hasCompleteScoringData != true {
            return FPLSmartCoachResult(
                answer: unavailableScoringAnswer(live),
                confidence: "low",
                evidence: ["No complete official player-level scoring snapshot is available."],
                assumptions: ["Missing statistics are unknown, not zero points or a confirmed non-appearance."],
                actions: ["Refresh Live Points and try again when official FPL data is available."],
                model: "Fotty FPL Rules Engine",
                verifiedAt: freshness?.fetchedAt ?? Date(),
                officialDataStatus: live == nil ? "unavailable" : "incomplete",
                source: .rulesEngine,
                usage: .zero
            )
        }
        let scoringIsFresh = freshness.map { $0.age <= 300 && $0.fetchedAt.timeIntervalSinceNow <= 60 } ?? false
        if isScoringQuery(query), !scoringIsFresh {
            return FPLSmartCoachResult(
                answer: "I cannot verify a current total from an undated or stale scoring snapshot. Refresh Live Points before checking points or automatic substitutions.",
                confidence: "low",
                evidence: [freshness.map { "Scoring snapshot fetched \($0.fetchedAt.formatted(date: .abbreviated, time: .shortened))." } ?? "The scoring snapshot has no verified fetch time."],
                assumptions: ["Current scoring requires both picks and live statistics refreshed within five minutes."],
                actions: ["Refresh FPL data, then ask again."],
                model: "Fotty FPL Rules Engine",
                verifiedAt: freshness?.fetchedAt ?? Date(),
                officialDataStatus: "stale",
                source: .rulesEngine,
                usage: .zero
            )
        }

        var answer: String?
        var evidence = [String]()
        var limits = [String]()
        var actions = [String]()

        if isScoringQuery(query), let live {
            answer = await askCoach(
                userQuery: userQuery,
                managerSummary: managerSummary,
                currentGw: currentGw,
                picks: picks,
                scores: scores,
                recs: [],
                captains: [],
                rivalGap: nil,
                freeTransfers: freeTransfers,
                live: live,
                players: players
            )
            evidence = [
                "Official current points: \(live.officialCurrentPoints.map(String.init) ?? "unknown").",
                "Published lineup points: \(live.publishedLineupPoints.map(String.init) ?? "unknown").",
                "Transfer cost: \(live.transferCost)."
            ]
            if let projectedCaptainID = live.projectedCaptainElementID,
               let projectedCaptain = players.first(where: { $0.id == projectedCaptainID }) {
                evidence.append("\(projectedCaptain.webName) is provisionally promoted from vice-captain to captain.")
            }
            limits = live.pointsAreProjected
                ? ["Automatic substitutions remain provisional until official FPL publishes them or completes its data check."]
                : []
            actions = live.isFinal ? [] : ["Refresh after the remaining fixtures or official data check."]
        } else if query.contains("free transfer") || query.contains("how many transfer") {
            if let freeTransfers {
                answer = "Fotty's current public-history estimate is **\(freeTransfers.count) free transfer\(freeTransfers.count == 1 ? "" : "s")**."
                evidence = [freeTransfers.explanation]
                limits = freeTransfers.isExact ? [] : ["The public API is not the authenticated transfer screen."]
                actions = ["Confirm the exact count in official FPL before making transfers."]
            }
        } else if query.contains("deadline") {
            if let deadline = currentGw?.deadlineDate {
                answer = "The current FPL deadline in your local time is **\(deadline.formatted(date: .abbreviated, time: .shortened))**."
                evidence = ["Official gameweek deadline: \(currentGw?.deadlineTime ?? "unknown")."]
                actions = ["Refresh availability and save final changes in official FPL before that time."]
            }
        } else if query.contains("who is my captain") || query.contains("current captain") {
            let playerByID = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
            if let captain = picks?.picks.first(where: \.isCaptain).flatMap({ playerByID[$0.element] }) {
                let week = publishedGameweek.map { " for GW\($0)" } ?? ""
                answer = "Your published captain\(week) is **\(captain.webName)**."
                evidence = ["The public picks snapshot\(week) marks \(captain.webName) as captain, independently of any local draft."]
            }
        } else if query.contains("who is on my bench") || query.contains("my bench players") {
            let playerByID = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
            let bench = (picks?.picks ?? [])
                .filter { $0.position > 11 }
                .sorted { $0.position < $1.position }
                .compactMap { playerByID[$0.element]?.webName }
            if !bench.isEmpty {
                let week = publishedGameweek.map { " for GW\($0)" } ?? ""
                answer = "Your published bench order\(week) is **\(bench.joined(separator: ", "))**."
                evidence = ["Public picks\(week), positions 12–15, in order; not the local draft."]
            }
        } else if query.contains("squad size") || query.contains("players per club") || query.contains("club limit") {
            let squadSize = settings?.squadSize ?? 15
            let clubLimit = settings?.squadTeamLimit ?? 3
            answer = "The current rules allow a **\(squadSize)-player squad** and at most **\(clubLimit) players from one club**."
            evidence = ["Decoded official FPL game settings on this device."]
        } else if query.contains("selling price") || query.contains("sell-on") {
            answer = "Fotty cannot prove an exact current selling price from the public manager endpoints. Selling price depends on the authenticated purchase price and the current official price."
            evidence = ["Public picks may contain a published selling price, but pending authenticated account state is unavailable."]
            actions = ["Check the transfer screen in official FPL before judging affordability."]
        }

        guard let answer else { return nil }
        let verifiedAt = freshness?.fetchedAt ?? Date()
        let result = FPLSmartCoachResult(
            answer: answer,
            confidence: limits.isEmpty ? "high" : "medium",
            evidence: evidence,
            assumptions: limits,
            actions: actions,
            model: "Fotty FPL Rules Engine",
            verifiedAt: verifiedAt,
            officialDataStatus: freshness?.source.rawValue ?? "Device snapshot",
            source: .rulesEngine,
            usage: .zero
        )
        FottyQualityStore.shared.record(
            category: .coach,
            name: "rules_answer",
            outcome: .success,
            details: ["source": "rules_engine", "model": "fotty_rules", "token_count": "0"]
        )
        return result
    }

    public static func generateBriefing(
        managerName: String?,
        currentGw: FPLGameweek?,
        picks: FPLManagerPicks?,
        scores: [PlayerScore],
        recs: [TransferRecommendation],
        captains: [CaptainRecommendation],
        rivalGap: RivalGapAnalysis?
    ) async -> AIGameweekBriefing {
        let gameweekName = currentGw?.name ?? "Upcoming gameweek"
        let isUnlimited = FPLTransferRules.hasUnlimitedPreseasonTransfers(gameweek: currentGw)
        let squadIDs = Set(picks?.picks.map(\.element) ?? [])

        let warnings = scores
            .filter { squadIDs.contains($0.player.id) }
            .filter { $0.availabilityRisk != .available || !$0.player.news.isEmpty }
            .map {
                let detail = $0.player.news.isEmpty ? $0.availabilityRisk.rawValue : $0.player.news
                return "\($0.player.webName) (\($0.team.shortName)): \(detail)"
            }

        let gems = scores
            .filter { (Double($0.player.selectedByPercent) ?? 0) < 15 }
            .sorted { $0.compositeScore > $1.compositeScore }
            .prefix(3)
            .map {
                "\($0.player.webName) (\($0.team.shortName)) — Fotty rating \(formatted($0.compositeScore))/100, \($0.player.formattedCost), \($0.player.selectedByPercent)% selected."
            }

        var rivalNotes = [String]()
        if let rivalGap {
            rivalNotes.append(rivalGap.tacticalAdvice)
            if !rivalGap.rivalThreats.isEmpty {
                let names = rivalGap.rivalThreats.prefix(2).map(\.player.webName).joined(separator: ", ")
                rivalNotes.append("Your selected rival owns \(names), while your current squad does not.")
            }
        }

        let recommendation: String
        if isUnlimited {
            recommendation = "Unlimited transfers remain available before the Gameweek 1 deadline. Save experiments as drafts in Fotty, then confirm them in official FPL."
        } else if let transfer = recs.first {
            recommendation = "Review \(transfer.playerOut.player.webName) → \(transfer.playerIn.player.webName). Fotty's model rates the replacement \(formatted(transfer.scoreUplift)) rating points higher; this is not an official points projection."
        } else if let captain = captains.first {
            recommendation = "Review \(captain.player.player.webName) for captain. The displayed points are a Fotty model estimate, not official expected points."
        } else {
            recommendation = "No high-priority modeled change is available. Recheck official availability and deadline information before confirming your team."
        }

        return AIGameweekBriefing(
            headline: "\(gameweekName) briefing\(managerName.map { " for \($0)" } ?? "")",
            tacticalWarnings: warnings.isEmpty ? ["No active availability flags were returned by the FPL data currently cached on this device."] : warnings,
            differentialGems: gems.isEmpty ? ["No low-selected candidates passed the current Fotty rating filter."] : Array(gems),
            rivalVulnerabilities: rivalNotes.isEmpty ? ["Select a rival after the gameweek deadline to compare revealed squads."] : rivalNotes,
            topRecommendation: recommendation
        )
    }

    public static func askCoach(
        userQuery: String,
        history: [AICoachMessage] = [],
        managerSummary: FPLManagerSummary?,
        currentGw: FPLGameweek?,
        picks: FPLManagerPicks?,
        scores: [PlayerScore],
        recs: [TransferRecommendation],
        captains: [CaptainRecommendation],
        rivalGap: RivalGapAnalysis?,
        freeTransfers: FPLFreeTransferEstimate? = nil,
        live: FPLLiveSquadSummary? = nil,
        players: [FPLPlayer] = []
    ) async -> String {
        _ = history
        let query = userQuery.lowercased()
        let squadIDs = Set(picks?.picks.map(\.element) ?? [])
        let squad = scores.filter { squadIDs.contains($0.player.id) }
        let gameweekName = currentGw?.name ?? "the upcoming gameweek"
        let isUnlimited = FPLTransferRules.hasUnlimitedPreseasonTransfers(gameweek: currentGw)

        if isScoringQuery(query) {
            guard let live, live.hasCompleteScoringData,
                  let totalPoints = live.totalPoints,
                  let officialPoints = live.officialCurrentPoints else { return unavailableScoringAnswer(live) }
            let names = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.webName) })
            let substitutions = live.displayedAutomaticSubs.map {
                "\(names[$0.elementIn] ?? "Player \($0.elementIn)") for \(names[$0.elementOut] ?? "Player \($0.elementOut)")"
            }
            if live.pointsAreProjected {
                var pendingRules = substitutions
                if let captainID = live.projectedCaptainElementID {
                    pendingRules.append("\(names[captainID] ?? "the vice-captain") inheriting the captain multiplier")
                }
                return "### Provisional FPL total\n\nOfficial FPL currently shows **\(officialPoints) points**. Fotty's deterministic rules engine projects **\(totalPoints) points** after \(pendingRules.joined(separator: ", ")). This remains provisional until official FPL publishes the pending rules or completes its data check."
            }
            return "### Official live total\n\nOfficial FPL currently shows **\(totalPoints) points**.\(substitutions.isEmpty ? " No additional eligible automatic substitution is proven by the current snapshot." : " Automatic substitutions: \(substitutions.joined(separator: ", ")).")"
        }

        if query.contains("rival") || query.contains("mini-league") || query.contains("league") {
            return rivalAnswer(rivalGap: rivalGap)
        }

        if query.contains("captain") || query.contains("armband") || query.contains("vice") {
            return captainAnswer(captains: captains, gameweekName: gameweekName)
        }

        if query.contains("hit") || query.contains("-4") {
            if isUnlimited {
                return "### Transfer cost check\n\nThe Gameweek 1 deadline has not passed, so transfers are currently unlimited. Fotty only saves a local draft; confirm the final squad in official FPL."
            }
            let estimate = freeTransfers.map { "Fotty's public-history estimate is \($0.count) free transfer(s). " } ?? "Fotty could not estimate the current free-transfer count. "
            return "### Transfer cost check\n\n\(estimate)This remains an estimate because the public API is not the authenticated transfer screen. Do not take a hit based only on Fotty's rating difference; confirm your free transfers and the move in official FPL."
        }

        if isTransferQuery(query) {
            return transferAnswer(recs: recs, isUnlimited: isUnlimited)
        }

        if isSquadQuery(query) {
            return squadAnswer(
                squad: squad,
                managerName: managerSummary?.name,
                isUnlimited: isUnlimited
            )
        }

        if query.contains("differential") || query.contains("target") || query.contains("outside") {
            return targetAnswer(scores: scores, squadIDs: squadIDs)
        }

        return summaryAnswer(
            managerName: managerSummary?.name,
            gameweekName: gameweekName,
            recs: recs,
            captains: captains
        )
    }

    private static func squadAnswer(
        squad: [PlayerScore],
        managerName: String?,
        isUnlimited: Bool
    ) -> String {
        guard !squad.isEmpty else {
            return "### Squad review unavailable\n\nFotty does not currently have a squad to review. Reload the manager or create a local draft first."
        }

        var reply = "### Squad model review: **\(managerName ?? "Your squad")**\n\n"
        let positions = [
            (1, "Goalkeepers"),
            (2, "Defenders"),
            (3, "Midfielders"),
            (4, "Forwards")
        ]

        for (position, title) in positions {
            reply += "**\(title)**\n"
            for player in squad.filter({ $0.player.elementType == position }) {
                reply += "• **\(player.player.webName)** — Fotty rating **\(formatted(player.compositeScore))/100**, \(player.player.formattedCost)\n"
            }
            reply += "\n"
        }

        reply += "Fotty ratings rank players from the current inputs; they are not expected FPL points. "
        reply += isUnlimited
            ? "Transfers remain unlimited before the Gameweek 1 deadline."
            : "Confirm deadline, free transfers, selling prices, and final changes in official FPL."
        return reply
    }

    private static func transferAnswer(
        recs: [TransferRecommendation],
        isUnlimited: Bool
    ) -> String {
        guard !recs.isEmpty else {
            return "### Transfer shortlist\n\nNo candidate cleared Fotty's current rating threshold. That does not prove the squad is optimal; check availability, minutes risk, and upcoming fixtures."
        }

        var reply = "### Modeled transfer shortlist\n\n"
        for (index, rec) in recs.prefix(3).enumerated() {
            reply += "\(index + 1). **\(rec.playerOut.player.webName)** → **\(rec.playerIn.player.webName)**\n"
            reply += "   • Fotty rating difference: **+\(formatted(rec.scoreUplift))**\n"
            reply += "   • \(rec.reason)\n\n"
        }
        reply += "These are local draft suggestions, not applied official transfers or expected-point guarantees. "
        reply += isUnlimited
            ? "Transfers are unlimited until the Gameweek 1 deadline."
            : "Confirm your available free transfers and selling prices in official FPL."
        return reply
    }

    private static func captainAnswer(
        captains: [CaptainRecommendation],
        gameweekName: String
    ) -> String {
        guard let captain = captains.first else {
            return "### Captain review unavailable\n\nFotty does not have enough current squad data to produce a captain shortlist."
        }

        var reply = "### \(gameweekName) captain shortlist\n\n"
        reply += "1. **\(captain.player.player.webName)** — Fotty model estimate **\(formatted(captain.expectedPoints))**\n"
        if captains.count > 1 {
            let vice = captains[1]
            reply += "2. **\(vice.player.player.webName)** — Fotty model estimate **\(formatted(vice.expectedPoints))**\n"
        }
        reply += "\nThese are modeled estimates, not official expected points. Confirm availability and the deadline before locking the armband."
        return reply
    }

    private static func rivalAnswer(rivalGap: RivalGapAnalysis?) -> String {
        guard let rivalGap else {
            return "### Rival comparison unavailable\n\nSelect a mini-league rival after their squad is revealed. Fotty will compare the two published squads; it does not currently calculate true league effective ownership."
        }

        var reply = "### Rival squad comparison\n\n"
        reply += "• Published points gap: **\(rivalGap.pointDeficit)**\n"
        if !rivalGap.rivalThreats.isEmpty {
            reply += "• Rival-only players: \(rivalGap.rivalThreats.prefix(3).map(\.player.webName).joined(separator: ", "))\n"
        }
        if !rivalGap.myDifferentials.isEmpty {
            reply += "• Your unique players: \(rivalGap.myDifferentials.prefix(3).map(\.player.webName).joined(separator: ", "))\n"
        }
        reply += "\nThis is a direct squad comparison, not effective ownership or a predicted rank swing."
        return reply
    }

    private static func targetAnswer(scores: [PlayerScore], squadIDs: Set<Int>) -> String {
        let targets = scores
            .filter { !squadIDs.contains($0.player.id) && $0.player.status == "a" }
            .sorted { $0.compositeScore > $1.compositeScore }
            .prefix(4)

        guard !targets.isEmpty else {
            return "### Candidate search unavailable\n\nNo available player passed the current Fotty filter."
        }

        var reply = "### Players outside your squad\n\n"
        for (index, player) in targets.enumerated() {
            reply += "\(index + 1). **\(player.player.webName)** (\(player.team.shortName), \(player.player.formattedCost)) — Fotty rating **\(formatted(player.compositeScore))/100**, selected by **\(player.player.selectedByPercent)%**\n"
        }
        reply += "\nSelection percentage is official FPL data; the rating is Fotty's model."
        return reply
    }

    private static func summaryAnswer(
        managerName: String?,
        gameweekName: String,
        recs: [TransferRecommendation],
        captains: [CaptainRecommendation]
    ) -> String {
        var reply = "### \(gameweekName) local fallback summary\n\n"
        reply += "Fotty is reviewing **\(managerName ?? "your squad")** entirely on this device. No squad or chat data is sent to an AI provider.\n\n"
        if let transfer = recs.first {
            reply += "• Transfer to review: **\(transfer.playerOut.player.webName)** → **\(transfer.playerIn.player.webName)**\n"
        }
        if let captain = captains.first {
            reply += "• Captain to review: **\(captain.player.player.webName)**\n"
        }
        reply += "\nRecommendations are model output, not official expected points or applied FPL actions."
        return reply
    }

    private static func isTransferQuery(_ query: String) -> Bool {
        ["change", "swap", "replace", "sell", "buy", "transfer", "upgrade", "overhaul", "optimize"]
            .contains { query.contains($0) }
    }

    private static func isSquadQuery(_ query: String) -> Bool {
        ["whole team", "my team", "squad review", "rate my team", "full squad", "entire team", "lineup"]
            .contains { query.contains($0) }
    }

    static func isScoringQuery(_ query: String) -> Bool {
        // Keep this factual routing contract aligned with the Worker. Advice
        // about future transfers/captains still belongs to the reasoning model.
        let pattern = #"auto(?:matic)?[-\s]?sub|substitut|bench.*(?:point|replace|come on)|(?:point|total|score).*(?:bench|sub|replace|did not play|didn't play|no minutes)|(?:did not play|didn't play|no minutes).*(?:point|total|sub|replace)|how many (?:gameweek )?points|correct (?:gameweek )?(?:points|total)|gameweek points"#
        let currentScoreRequest = #"\b(?:what(?:['’]s| is| are)|check|verify|show)\s+(?:my|the)\s+(?:current|live)\s+(?:gameweek\s+)?(?:points|total|score)\b"#
        return query.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
            || query.range(of: currentScoreRequest, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func unavailableScoringAnswer(_ live: FPLLiveSquadSummary?) -> String {
        let published = live?.officialCurrentPoints.map { "The published official snapshot shows **\($0) points**, but player data is incomplete. " }
            ?? "I cannot verify your gameweek total because official scoring data is unavailable or incomplete. "
        return published + "Missing statistics do not mean a player failed to appear. Refresh Live Points before checking automatic substitutions or a corrected total."
    }

    private static func formatted(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
