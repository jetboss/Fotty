import Foundation

public struct FPLCoachTokenUsage: Codable, Sendable, Equatable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let cacheHitTokens: Int
    public let cacheMissTokens: Int
    public let reasoningTokens: Int

    public static let zero = FPLCoachTokenUsage(
        promptTokens: 0,
        completionTokens: 0,
        totalTokens: 0,
        cacheHitTokens: 0,
        cacheMissTokens: 0,
        reasoningTokens: 0
    )
}

public struct FPLCoachCardPayload: Codable, Sendable, Equatable {
    public let answer: String
    public let confidence: String
    public let evidence: [String]
    public let downside: [String]
    public let verifyBeforeDeadline: [String]
    public let source: String
    public let model: String?
    public let officialDataStatus: String
    public let verifiedAt: Date?
    public let usage: FPLCoachTokenUsage?

    public init(
        answer: String,
        confidence: String,
        evidence: [String],
        downside: [String],
        verifyBeforeDeadline: [String],
        source: String,
        model: String? = nil,
        officialDataStatus: String,
        verifiedAt: Date? = nil,
        usage: FPLCoachTokenUsage? = nil
    ) {
        self.answer = answer
        self.confidence = confidence
        self.evidence = evidence
        self.downside = downside
        self.verifyBeforeDeadline = verifyBeforeDeadline
        self.source = source
        self.model = model
        self.officialDataStatus = officialDataStatus
        self.verifiedAt = verifiedAt
        self.usage = usage
    }
}

public struct FPLSmartCoachResult: Sendable {
    public enum Source: String, Sendable {
        case deepSeek = "DeepSeek"
        case rulesEngine = "Fotty rules engine"
        case localFallback = "Local fallback"
    }

    public let answer: String
    public let confidence: String
    public let evidence: [String]
    public let assumptions: [String]
    public let actions: [String]
    public let model: String?
    public let verifiedAt: Date?
    public let officialDataStatus: String
    public let source: Source
    public let usage: FPLCoachTokenUsage?

    public var cardPayload: FPLCoachCardPayload {
        FPLCoachCardPayload(
            answer: answer,
            confidence: confidence,
            evidence: evidence,
            downside: assumptions,
            verifyBeforeDeadline: actions,
            source: source.rawValue,
            model: model,
            officialDataStatus: officialDataStatus,
            verifiedAt: verifiedAt,
            usage: usage
        )
    }

    public var renderedText: String {
        var sections = [answer]
        if !evidence.isEmpty {
            sections.append("### Evidence checked\n" + evidence.map { "• \($0)" }.joined(separator: "\n"))
        }
        if !assumptions.isEmpty {
            sections.append("### Assumptions and limits\n" + assumptions.map { "• \($0)" }.joined(separator: "\n"))
        }
        if !actions.isEmpty {
            sections.append("### Next checks\n" + actions.map { "• \($0)" }.joined(separator: "\n"))
        }
        var verification = "Confidence: **\(confidence.capitalized)** • \(source.rawValue) • Official-data status: \(officialDataStatus)"
        if let verifiedAt {
            verification += " • Checked \(verifiedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        if let model, !model.isEmpty {
            verification += " • \(model)"
        }
        if let usage {
            verification += " • \(usage.totalTokens) tokens"
        }
        sections.append(verification)
        return sections.joined(separator: "\n\n")
    }
}

public enum FPLSmartCoachError: LocalizedError, Sendable {
    case notConfigured
    case invalidResponse
    case service(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "The secure smart-coach proxy is not configured."
        case .invalidResponse: return "The smart coach returned an unreadable response."
        case .service(let message): return message
        }
    }
}

public enum FPLSmartCoachService {
    private struct RequestBody: Encodable {
        let query: String
        let managerId: Int
        let rivalId: Int?
        let context: Context
        let history: [ConversationItem]
    }

    private struct ConversationItem: Encodable {
        let role: String
        let content: String
    }

    private struct Context: Encodable {
        let phase: String
        let generatedAt: Date
        let freshness: [FreshnessItem]
        let profile: Profile
        let manager: Manager
        let squad: [SquadPlayer]
        let squadSource: String
        let transferOptions: [TransferOption]
        let captains: [CaptainOption]
        let freeTransfers: FreeTransfers?
        let validationIssues: [String]
        let routes: [Route]
        let live: Live?
        let rival: Rival?
        let recentReviews: [Review]
        let productBoundary: String
    }

    private struct FreshnessItem: Encodable {
        let resource: String
        let source: String
        let fetchedAt: Date
    }

    private struct Profile: Encodable {
        let riskStyle: String
        let planningHorizon: Int
        let avoidHits: Bool
    }

    private struct Manager: Encodable {
        let id: Int
        let teamName: String
        let overallPoints: Int?
        let overallRank: Int?
        let bank: Int?
        let teamValue: Int?
    }

    private struct SquadPlayer: Encodable {
        let id: Int
        let name: String
        let team: String
        let position: String
        let cost: Int
        let sellingPrice: Int?
        let starting: Bool
        let squadPosition: Int
        let outfieldBenchOrder: Int?
        let publishedMultiplier: Int?
        let effectiveMultiplier: Int?
        let captain: Bool
        let viceCaptain: Bool
        let status: String
        let news: String
        let form: Double
        let pointsPerGame: Double
        let epNext: Double?
        let horizonProjection: Double
        let projectionModel: String
        let projectionConfidence: String
        let projectionWeeks: [ProjectionWeek]
        let selectedPercent: Double
        let fixtures: [String]
        let gameweekMinutes: Int?
        let gameweekPoints: Int?
        let fixtureRemaining: Bool?
    }

    private struct ProjectionWeek: Encodable {
        let gameweek: Int
        let points: Double
        let expectedMinutes: Int
        let source: String
    }

    private struct TransferPlayer: Encodable {
        let id: Int
        let name: String
        let cost: Int
        let horizonProjection: Double
    }

    private struct TransferOption: Encodable {
        let out: TransferPlayer
        let `in`: TransferPlayer
        let projectedGain: Double
        let ratingDifference: Double
        let reason: String
    }

    private struct CaptainOption: Encodable {
        let id: Int
        let name: String
        let epNextOrFottyEstimate: Double
        let selectedPercent: Double
        let reason: String
    }

    private struct FreeTransfers: Encodable {
        let count: Int
        let exact: Bool
        let explanation: String
    }

    private struct Route: Encodable {
        let name: String
        let transferCount: Int
        let hitCost: Int
        let projectedGainAfterHit: Double
        let weeklyProjectedGain: [ProjectionDelta]
        let breakEvenGameweek: Int?
        let modelVersion: String
        let explanation: String
    }

    private struct ProjectionDelta: Encodable {
        let gameweek: Int
        let points: Double
    }

    private struct Live: Encodable {
        let points: Int?
        let officialCurrentPoints: Int?
        let publishedLineupPoints: Int?
        let hasCompleteScoringData: Bool
        let transferCost: Int
        let pointsStatus: String
        let played: Int?
        let remaining: Int?
        let bonus: Int?
        let final: Bool
        let substitutions: [LiveSubstitution]
        let projectedCaptain: String?
    }

    private struct LiveSubstitution: Encodable {
        let playerIn: String
        let playerOut: String
        let official: Bool
    }

    private struct Rival: Encodable {
        let name: String
        let pointsGap: Int
        let myCaptain: String?
        let rivalCaptain: String?
        let myUniquePlayers: [String]
        let rivalUniquePlayers: [String]
    }

    private struct Review: Encodable {
        let gameweek: Int
        let points: Int
        let transferCost: Int
        let benchPoints: Int
        let captain: String?
        let captainPoints: Int?
    }

    private struct ResponseBody: Decodable {
        let answer: String
        let confidence: String
        let evidence: [String]
        let assumptions: [String]
        let actions: [String]
        let model: String?
        let verifiedAt: String?
        let officialDataStatus: String
        let source: String?
        let usage: FPLCoachTokenUsage?
    }

    private struct ErrorBody: Decodable {
        let error: String
    }

    public static func ask(
        query: String,
        managerID: Int,
        manager: FPLManagerSummary,
        phase: FPLGameweekPhase,
        profile: FPLCoachProfile,
        picks: FPLManagerPicks?,
        squadSource: String = "Published squad",
        isLocalDraft: Bool = false,
        scores: [PlayerScore],
        fixtures: [FPLFixture],
        planningStartGameweek: Int,
        transferRecommendations: [TransferRecommendation],
        captainRecommendations: [CaptainRecommendation],
        freeTransfers: FPLFreeTransferEstimate?,
        validation: FPLSquadValidationReport?,
        routes: [FPLDraftRoute],
        live: FPLLiveSquadSummary?,
        rivalID: Int?,
        rival: RivalGapAnalysis?,
        reviews: [FPLGameweekReview],
        freshness: [String: FPLResourceMetadata],
        history: [AICoachMessage]
    ) async throws -> FPLSmartCoachResult {
        guard let baseURL = Config.fplCoachProxyBaseURL else {
            throw FPLSmartCoachError.notConfigured
        }
        let context = makeContext(
            managerID: managerID,
            manager: manager,
            phase: phase,
            profile: profile,
            picks: picks,
            squadSource: squadSource,
            isLocalDraft: isLocalDraft,
            scores: scores,
            fixtures: fixtures,
            planningStartGameweek: planningStartGameweek,
            transferRecommendations: transferRecommendations,
            captainRecommendations: captainRecommendations,
            freeTransfers: freeTransfers,
            validation: validation,
            routes: routes,
            live: live,
            rival: rival,
            reviews: reviews,
            freshness: freshness
        )
        let body = RequestBody(
            query: String(query.prefix(1_200)),
            managerId: managerID,
            rivalId: rivalID,
            context: context,
            history: history.suffix(6).map {
                ConversationItem(role: $0.sender == .user ? "user" : "assistant", content: String($0.text.prefix(1_200)))
            }
        )

        var request = URLRequest(url: baseURL.appendingPathComponent("api/fpl/coach"))
        request.httpMethod = "POST"
        request.timeoutInterval = 55
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(installationID(), forHTTPHeaderField: "X-Fotty-Install-ID")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FPLSmartCoachError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data).error)
                ?? "The smart coach is temporarily unavailable."
            throw FPLSmartCoachError.service(message)
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        let verifiedAt = decoded.verifiedAt.flatMap { value in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        }
        guard let normalizedSource = responseSource(decoded.source) else {
            throw FPLSmartCoachError.invalidResponse
        }
        let answer = decoded.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let confidence = decoded.confidence.lowercased()
        guard !answer.isEmpty,
              answer.count <= 8_000,
              ["low", "medium", "high"].contains(confidence),
              !decoded.evidence.isEmpty,
              !decoded.officialDataStatus.isEmpty,
              let verifiedAt,
              Date().timeIntervalSince(verifiedAt) <= 30 * 60,
              verifiedAt.timeIntervalSinceNow <= 5 * 60,
              normalizedSource != .deepSeek || !(decoded.model ?? "").isEmpty,
              !FPLAICoachService.isScoringQuery(query) || normalizedSource == .rulesEngine,
              normalizedSource != .rulesEngine || (decoded.usage?.totalTokens ?? 0) == 0 else {
            throw FPLSmartCoachError.invalidResponse
        }

        let result = FPLSmartCoachResult(
            answer: answer,
            confidence: confidence,
            evidence: Array(decoded.evidence.prefix(8)),
            assumptions: Array(decoded.assumptions.prefix(8)),
            actions: Array(decoded.actions.prefix(8)),
            model: decoded.model,
            verifiedAt: verifiedAt,
            officialDataStatus: decoded.officialDataStatus,
            source: normalizedSource,
            usage: decoded.usage
        )
        FottyQualityStore.shared.record(
            category: .coach,
            name: normalizedSource == .deepSeek ? "model_request" : "rules_answer",
            outcome: .success,
            details: [
                "source": normalizedSource == .deepSeek ? "deepseek" : "rules_engine",
                "model": decoded.model ?? "none",
                "token_count": "\(decoded.usage?.totalTokens ?? 0)"
            ]
        )
        return result
    }

    private static func makeContext(
        managerID: Int,
        manager: FPLManagerSummary,
        phase: FPLGameweekPhase,
        profile: FPLCoachProfile,
        picks: FPLManagerPicks?,
        squadSource: String,
        isLocalDraft: Bool,
        scores: [PlayerScore],
        fixtures: [FPLFixture],
        planningStartGameweek: Int,
        transferRecommendations: [TransferRecommendation],
        captainRecommendations: [CaptainRecommendation],
        freeTransfers: FPLFreeTransferEstimate?,
        validation: FPLSquadValidationReport?,
        routes: [FPLDraftRoute],
        live: FPLLiveSquadSummary?,
        rival: RivalGapAnalysis?,
        reviews: [FPLGameweekReview],
        freshness: [String: FPLResourceMetadata]
    ) -> Context {
        let scoreByID = Dictionary(uniqueKeysWithValues: scores.map { ($0.player.id, $0) })
        let liveRowByID = Dictionary(uniqueKeysWithValues: (live?.rows ?? []).map { ($0.player.id, $0) })
        let squad = (picks?.picks ?? []).compactMap { pick -> SquadPlayer? in
            guard let score = scoreByID[pick.element] else { return nil }
            let liveRow = isLocalDraft ? nil : liveRowByID[pick.element]
            let projection = FPLProjectionEngine.project(
                player: score.player,
                fixtures: fixtures,
                startGameweek: planningStartGameweek,
                horizon: profile.planningHorizon
            )
            return SquadPlayer(
                id: score.player.id,
                name: score.player.webName,
                team: score.team.shortName,
                position: score.player.positionName,
                cost: score.player.nowCost,
                sellingPrice: pick.sellingPrice,
                starting: pick.position <= 11,
                squadPosition: pick.position,
                outfieldBenchOrder: pick.position > 12 ? pick.position - 12 : nil,
                publishedMultiplier: isLocalDraft ? nil : pick.multiplier,
                effectiveMultiplier: liveRow?.effectiveMultiplier,
                captain: pick.isCaptain,
                viceCaptain: pick.isViceCaptain,
                status: score.player.status,
                news: score.player.news,
                form: Double(score.player.form) ?? 0,
                pointsPerGame: Double(score.player.pointsPerGame) ?? 0,
                epNext: score.player.officialExpectedPointsNext,
                horizonProjection: projection.total,
                projectionModel: projection.modelVersion,
                projectionConfidence: projection.confidence.rawValue,
                projectionWeeks: projection.gameweekPoints.keys.sorted().map { gameweek in
                    ProjectionWeek(
                        gameweek: gameweek,
                        points: projection.gameweekPoints[gameweek] ?? 0,
                        expectedMinutes: projection.expectedMinutes[gameweek] ?? 0,
                        source: projection.sourceByGameweek[gameweek]?.rawValue ?? FPLProjectionSource.fottyEstimate.rawValue
                    )
                },
                selectedPercent: Double(score.player.selectedByPercent) ?? 0,
                fixtures: score.upcomingFixtures.prefix(profile.planningHorizon).map {
                    "GW\($0.gameweek) \($0.isHome ? "vs" : "at") \($0.opponent.shortName) FDR \($0.difficulty)"
                },
                gameweekMinutes: liveRow?.stats.minutes,
                gameweekPoints: liveRow?.stats.totalPoints,
                fixtureRemaining: liveRow?.hasFixtureRemaining
            )
        }
        let transfers = transferRecommendations.prefix(6).map { recommendation in
            let outProjection = FPLProjectionEngine.project(
                player: recommendation.playerOut.player,
                fixtures: fixtures,
                startGameweek: planningStartGameweek,
                horizon: profile.planningHorizon
            ).total
            let inProjection = FPLProjectionEngine.project(
                player: recommendation.playerIn.player,
                fixtures: fixtures,
                startGameweek: planningStartGameweek,
                horizon: profile.planningHorizon
            ).total
            return TransferOption(
                out: TransferPlayer(
                    id: recommendation.playerOut.id,
                    name: recommendation.playerOut.player.webName,
                    cost: recommendation.playerOut.player.nowCost,
                    horizonProjection: outProjection
                ),
                in: TransferPlayer(
                    id: recommendation.playerIn.id,
                    name: recommendation.playerIn.player.webName,
                    cost: recommendation.playerIn.player.nowCost,
                    horizonProjection: inProjection
                ),
                projectedGain: inProjection - outProjection,
                ratingDifference: recommendation.scoreUplift,
                reason: recommendation.reason
            )
        }
        return Context(
            phase: phase.rawValue,
            generatedAt: Date(),
            freshness: freshness.sorted(by: { $0.key < $1.key }).map {
                FreshnessItem(resource: $0.key, source: $0.value.source.rawValue, fetchedAt: $0.value.fetchedAt)
            },
            profile: Profile(
                riskStyle: profile.riskStyle.rawValue,
                planningHorizon: profile.planningHorizon,
                avoidHits: profile.avoidHits
            ),
            manager: Manager(
                id: managerID,
                teamName: manager.name,
                overallPoints: manager.summaryOverallPoints,
                overallRank: manager.summaryOverallRank,
                bank: manager.lastDeadlineBank,
                teamValue: manager.lastDeadlineValue
            ),
            squad: squad,
            squadSource: squadSource,
            transferOptions: transfers,
            captains: captainRecommendations.prefix(5).map {
                CaptainOption(
                    id: $0.player.id,
                    name: $0.player.player.webName,
                    epNextOrFottyEstimate: $0.expectedPoints,
                    selectedPercent: $0.selectionPercent,
                    reason: $0.reason
                )
            },
            freeTransfers: freeTransfers.map {
                FreeTransfers(count: $0.count, exact: $0.isExact, explanation: $0.explanation)
            },
            validationIssues: validation?.issues.map(\.message) ?? [],
            routes: routes.map { route in
                Route(
                    name: route.name,
                    transferCount: route.transfers.count,
                    hitCost: route.hitCost,
                    projectedGainAfterHit: route.projectedGain,
                    weeklyProjectedGain: route.weeklyProjectedGain.keys.sorted().map { gameweek in
                        ProjectionDelta(gameweek: gameweek, points: route.weeklyProjectedGain[gameweek] ?? 0)
                    },
                    breakEvenGameweek: route.breakEvenGameweek,
                    modelVersion: route.modelVersion,
                    explanation: route.explanation
                )
            },
            live: live.map { summary in
                let playerNames = Dictionary(uniqueKeysWithValues: squad.map { ($0.id, $0.name) })
                let substitutions = summary.displayedAutomaticSubs.map { substitution in
                    LiveSubstitution(
                        playerIn: playerNames[substitution.elementIn] ?? "Player \(substitution.elementIn)",
                        playerOut: playerNames[substitution.elementOut] ?? "Player \(substitution.elementOut)",
                        official: !summary.automaticSubs.isEmpty
                    )
                }
                return Live(
                    points: summary.totalPoints,
                    officialCurrentPoints: summary.officialCurrentPoints,
                    publishedLineupPoints: summary.publishedLineupPoints,
                    hasCompleteScoringData: summary.hasCompleteScoringData,
                    transferCost: summary.transferCost,
                    pointsStatus: !summary.hasCompleteScoringData ? "incomplete" : (summary.pointsAreProjected ? summary.projectionLabel : (summary.isFinal ? "official final" : "official current")),
                    played: summary.hasCompleteScoringData ? summary.playersPlayed : nil,
                    remaining: summary.hasCompleteScoringData ? summary.playersRemaining : nil,
                    bonus: summary.hasCompleteScoringData ? summary.officialBonus : nil,
                    final: summary.isFinal,
                    substitutions: substitutions,
                    projectedCaptain: summary.projectedCaptainElementID.flatMap { playerID in
                        scores.first(where: { $0.player.id == playerID })?.player.webName
                    }
                )
            },
            rival: rival.map {
                Rival(
                    name: $0.rivalName,
                    pointsGap: $0.pointDeficit,
                    myCaptain: $0.myCaptainName,
                    rivalCaptain: $0.rivalCaptainName,
                    myUniquePlayers: $0.myDifferentials.map { $0.player.webName },
                    rivalUniquePlayers: $0.rivalThreats.map { $0.player.webName }
                )
            },
            recentReviews: reviews.prefix(5).map {
                Review(
                    gameweek: $0.gameweek,
                    points: $0.points,
                    transferCost: $0.transferCost,
                    benchPoints: $0.pointsOnBench,
                    captain: $0.captainName,
                    captainPoints: $0.captainPoints
                )
            },
            productBoundary: "Fotty saves local drafts only and never submits changes to the official FPL account. Squad source: \(squadSource). The live summary is exclusively the published official lineup, not this local plan."
        )
    }

    private static func responseSource(_ raw: String?) -> FPLSmartCoachResult.Source? {
        let normalized = raw?.lowercased() ?? ""
        if normalized.contains("rules engine") || normalized.contains("official fpl") {
            return .rulesEngine
        }
        if normalized.contains("deepseek") { return .deepSeek }
        return nil
    }

    private static func installationID() -> String {
        let key = "fotty.installation.id"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }
}
