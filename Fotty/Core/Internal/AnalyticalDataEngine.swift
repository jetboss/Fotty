import Foundation

// MARK: - Live Sports Stream Processor
// Resolves football matches to playable streams via embedsports.top

// Module-level typealiases so providers can reference these types without qualification
typealias EventReference = AnalyticalDataEngine.EventReference

@MainActor
struct AnalyticalDataEngine {

    private static let providers: [LiveStreamingProvider] = [
        CoreMediaProvider()
    ]

    // MARK: - NexusA Live API Models

    struct NexusALiveResponse: Codable {
        let matches: [EventReference]?

        // The API might return the array directly or wrapped
        init(from decoder: Decoder) throws {
            // Try as array first
            if let array = try? [EventReference](from: decoder) {
                self.matches = array
            } else {
                // Try as object with matches key
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.matches = try container.decodeIfPresent([EventReference].self, forKey: .matches)
            }
        }

        enum CodingKeys: String, CodingKey {
            case matches
        }
    }

    @MainActor
    struct EventReference: @preconcurrency Codable, Identifiable {
        let id: String
        let title: String?
        let category: String?
        let date: Int64?
        let poster: String?
        let popular: Bool?
        let teams: NexusATeams?
        let sources: [NexusASource]?

        enum CodingKeys: String, CodingKey {
            case id, title, category, date, poster, popular, teams, sources
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            category = try container.decodeIfPresent(String.self, forKey: .category)
            date = try container.decodeIfPresent(Int64.self, forKey: .date)
            poster = try container.decodeIfPresent(String.self, forKey: .poster)
            popular = try container.decodeIfPresent(Bool.self, forKey: .popular)
            teams = try container.decodeIfPresent(NexusATeams.self, forKey: .teams)
            sources = try container.decodeIfPresent([NexusASource].self, forKey: .sources)

            if let decodedId = try container.decodeIfPresent(String.self, forKey: .id), !decodedId.isEmpty {
                id = decodedId
            } else {
                let baseTitle = title?.replacingOccurrences(of: " ", with: "-").lowercased() ?? "event"
                id = "\(baseTitle)-\(date ?? 0)"
            }
        }

        init(
            id: String,
            title: String?,
            category: String?,
            date: Int64?,
            poster: String?,
            popular: Bool?,
            teams: NexusATeams?,
            sources: [NexusASource]?
        ) {
            self.id = id
            self.title = title
            self.category = category
            self.date = date
            self.poster = poster
            self.popular = popular
            self.teams = teams
            self.sources = sources
        }

        nonisolated var kickoffDate: Date? {
            guard let date, date > 0 else { return nil }
            if date > 10_000_000_000 {
                return Date(timeIntervalSince1970: Double(date) / 1000)
            }
            return Date(timeIntervalSince1970: Double(date))
        }

        /// Live feed: keep only fixtures in a short window around now (drops months/years-old junk). Unknown kickoff kept.
        nonisolated func passesNearTermLiveListWindow(at now: Date = .init()) -> Bool {
            if isBroadcastChannel { return true }
            guard let kickoff = kickoffDate else { return true }
            let pastGrace: TimeInterval = 36 * 3600
            let futureHorizon: TimeInterval = 48 * 3600
            return kickoff >= now.addingTimeInterval(-pastGrace) && kickoff <= now.addingTimeInterval(futureHorizon)
        }

        var normalizedCategory: String {
            AnalyticalDataEngine.normalizedCategoryKey(category)
        }

        var categoryDisplayName: String {
            AnalyticalDataEngine.categoryDisplayName(for: normalizedCategory)
        }

        var homeName: String {
            if isBroadcastChannel { return title ?? "Cricket channel" }
            if let explicit = teams?.home?.name, !explicit.isEmpty {
                return explicit
            }
            return splitTeamsFromTitle().home
        }

        var awayName: String {
            if isBroadcastChannel { return "" }
            if let explicit = teams?.away?.name, !explicit.isEmpty {
                return explicit
            }
            return splitTeamsFromTitle().away
        }

        var homeBadgeURL: URL? {
            AnalyticalDataEngine.imageURL(from: teams?.home?.badge)
        }

        var awayBadgeURL: URL? {
            AnalyticalDataEngine.imageURL(from: teams?.away?.badge)
        }

        var posterURL: URL? {
            AnalyticalDataEngine.imageURL(from: poster)
        }

        private func splitTeamsFromTitle() -> (home: String, away: String) {
            guard let title, !title.isEmpty else {
                return ("Home", "Away")
            }

            let separators = [" vs ", " v ", " @ ", " - "]
            for separator in separators {
                let parts = title.components(separatedBy: separator)
                if parts.count == 2 {
                    let home = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let away = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !home.isEmpty && !away.isEmpty {
                        return (home, away)
                    }
                }
            }

            return (title, "Away")
        }

        init(from match: FootballMatch) {
            // Schedule identities are canonical across catalog fallback,
            // Match Center, notifications, and playback. A presentation-layer
            // prefix here used to create a second identity for the same match.
            self.id = String(match.id)
            self.title = "\(match.homeTeam.displayName) vs \(match.awayTeam.displayName)"
            self.category = "football"

            // Convert ISO8601 string to timestamp
            let dateObj = match.matchDate ?? Date()
            self.date = Int64(dateObj.timeIntervalSince1970)

            self.poster = match.competition.emblem
            self.popular = match.competition.code == "PL" || match.competition.code == "CL"
            self.teams = NexusATeams(
                home: NexusATeam(name: match.homeTeam.displayName, badge: match.homeTeam.crest),
                away: NexusATeam(name: match.awayTeam.displayName, badge: match.awayTeam.crest)
            )
            self.sources = [] // No streams in review mode
        }
    }


    private struct DataFeedProfile {
        let label: String
        let baseURL: String
        let matchesAllPath: String
        let matchesLivePath: String
        let matchesUpcomingPath: String
        let streamPathPrefix: String
    }

    private struct LiveStreamVariant: Decodable {
        let streamNo: Int?
        let language: String?
        let hd: Bool?
        let embedUrl: String?
        let source: String?
        let heatTier: String?
        let viewers: Int?

        private enum CodingKeys: String, CodingKey {
            case streamNo
            case language
            case hd
            case embedUrl
            case source
            case heatTier
            case viewers
        }

        private enum AlternateCodingKeys: String, CodingKey {
            case streamNo = "stream_no"
            case embedUrl = "embed_url"
            case url
            case heatTier = "heat_tier"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let alternate = try decoder.container(keyedBy: AlternateCodingKeys.self)

            let camelStreamNo = try container.decodeIfPresent(Int.self, forKey: .streamNo)
            let snakeStreamNo = try alternate.decodeIfPresent(Int.self, forKey: .streamNo)
            let camelEmbedURL = try container.decodeIfPresent(String.self, forKey: .embedUrl)
            let snakeEmbedURL = try alternate.decodeIfPresent(String.self, forKey: .embedUrl)
            let fallbackURL = try alternate.decodeIfPresent(String.self, forKey: .url)
            let camelHeatTier = try container.decodeIfPresent(String.self, forKey: .heatTier)
            let snakeHeatTier = try alternate.decodeIfPresent(String.self, forKey: .heatTier)

            streamNo = camelStreamNo ?? snakeStreamNo
            language = try container.decodeIfPresent(String.self, forKey: .language)
            hd = try container.decodeIfPresent(Bool.self, forKey: .hd)
            embedUrl = camelEmbedURL ?? snakeEmbedURL ?? fallbackURL
            source = try container.decodeIfPresent(String.self, forKey: .source)
            heatTier = camelHeatTier ?? snakeHeatTier
            if let integerViewers = try? container.decode(Int.self, forKey: .viewers) {
                viewers = integerViewers
            } else if let stringViewers = try? container.decode(String.self, forKey: .viewers) {
                viewers = Int(stringViewers)
            } else {
                viewers = nil
            }
        }
    }

    private struct LiveStreamVariantEnvelope: Decodable {
        let data: [LiveStreamVariant]?
        let streams: [LiveStreamVariant]?
        let variants: [LiveStreamVariant]?
        let sources: [LiveStreamVariant]?

        var allVariants: [LiveStreamVariant] {
            data ?? streams ?? variants ?? sources ?? []
        }
    }

    struct StreamCandidate {
        let sourceCode: String
        let streamNo: Int
        let language: String?
        let isHD: Bool
        let heatTier: String?
        let embedURL: String
        let catalogProvider: String
        let viewers: Int?

        init(
            sourceCode: String,
            streamNo: Int,
            language: String?,
            isHD: Bool,
            heatTier: String?,
            embedURL: String,
            catalogProvider: String,
            viewers: Int? = nil
        ) {
            self.sourceCode = sourceCode
            self.streamNo = streamNo
            self.language = language
            self.isHD = isHD
            self.heatTier = heatTier
            self.embedURL = embedURL
            self.catalogProvider = catalogProvider
            self.viewers = viewers
        }
    }

    // Preferred source order — StreamEx + Score808 first (VipLeague/P2P retired from player).
    // hotel (Score808) + delta (StreamEx) — player allowlist is these two.
    private static let preferredSources = ["admin", "delta", "golf", "hotel", "echo", "india"]
    nonisolated private static let canonicalEmbedOrigin = "https://embed.st"
    private static let feedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 7
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
    private static let dataFeedProfiles: [DataFeedProfile] = [
        DataFeedProfile(
            label: "Nexus Alpha",
            baseURL: StringObfuscator.decode([0x2E, 0x1B, 0x0, 0x4, 0xA, 0x7B, 0x41, 0x4E, 0x1B, 0xE, 0x3, 0x47, 0x10, 0x7, 0x24, 0x57, 0x27, 0x2, 0x11, 0xC, 0x57, 0x2F, 0xB, 0x15]),
            matchesAllPath: "/api/live/matches/all",
            matchesLivePath: "/api/live/matches/live",
            matchesUpcomingPath: "/api/live/matches/upcoming",
            streamPathPrefix: "/api/live/stream"
        ),
        DataFeedProfile(
            label: "Nexus Alpha Mirror",
            baseURL: StringObfuscator.decode([0x2E, 0x1B, 0x0, 0x4, 0xA, 0x7B, 0x41, 0x4E, 0x1F, 0xD, 0x6, 0xC, 0x2, 0x1E, 0x33, 0x4A, 0x68, 0x1C, 0x1C]),
            matchesAllPath: "/api/live/matches/all",
            matchesLivePath: "/api/live/matches/live",
            matchesUpcomingPath: "/api/live/matches/upcoming",
            streamPathPrefix: "/api/live/stream"
        ),
        DataFeedProfile(
            label: "Nexus Beta",
            baseURL: StringObfuscator.decode([0x2E, 0x1B, 0x0, 0x4, 0xA, 0x7B, 0x41, 0x4E, 0x1F, 0xD, 0x6, 0xC, 0x2, 0x1E, 0x33, 0x56, 0x68, 0x1F, 0x1F]),
            matchesAllPath: "/api/matches/all",
            matchesLivePath: "/api/matches/live",
            matchesUpcomingPath: "/api/matches/upcoming",
            streamPathPrefix: "/api/stream"
        )
    ]
    private static let maxNativeCandidateAttempts = 6
    private static let maxFallbackEmbedCandidates = 6

    // MARK: - Find streams for a football match

    /// Search all providers for a matching event and return stream sources
    static func findStreams(
        for event: EventReference
    ) async throws -> [StreamSource] {
        // ULTIMATE PRIORITY: Use the Hybrid System
        return try await HybridStreamProvider.shared.resolvePrioritizedSources(for: event)
    }

    /// LEGACY: Search all providers for a matching event
    static func findStreams(
        homeTeam: String,
        awayTeam: String
    ) async throws -> [StreamSource] {
        var allSources: [StreamSource] = []
        for provider in providers {
            if let sources = try? await provider.findStreams(homeTeam: homeTeam, awayTeam: awayTeam) {
                allSources.append(contentsOf: sources)
            }
        }

        guard !allSources.isEmpty else {
            throw ProcessorError.noSourcesFound
        }

        return allSources
    }

    /// Internal implementation for NexusA stream finding
    static func findStreams_NexusAImplementation(
        homeTeam: String,
        awayTeam: String
    ) async throws -> [StreamSource] {
        // 1. Fetch all live events from NexusA
        let events = try await fetchLiveEvents_NexusAImplementation()

        // 2. Find matching event by team names
        guard let match = findMatch(events: events, homeTeam: homeTeam, awayTeam: awayTeam) else {
            throw ProcessorError.noSourcesFound
        }

        return try await findStreamsDirect(for: match)
    }

    static func findStreamsDirect(for match: EventReference) async throws -> [StreamSource] {
        guard let sources = match.sources, !sources.isEmpty else {
            throw ProcessorError.noSourcesFound
        }

        // 3. Sort sources by preference and build embed URLs
        let sortedSources = sources.sorted { a, b in
            let aIdx = preferredSources.firstIndex(of: a.source) ?? preferredSources.count
            let bIdx = preferredSources.firstIndex(of: b.source) ?? preferredSources.count
            return aIdx < bIdx
        }

        var candidates: [StreamCandidate] = []
        for source in sortedSources {
            let resolved = await streamCandidates(for: source)
            candidates.append(contentsOf: resolved)
        }

        candidates = deduplicateCandidates(candidates)
        guard !candidates.isEmpty else {
            throw ProcessorError.noSourcesFound
        }

        // The supported player graph is web-only. Retired P2P/Ace-shaped
        // candidates are rejected before any renderer or playback session sees them.
        let webCandidates = Array(candidates.filter { !isP2PCandidate($0) }.prefix(maxNativeCandidateAttempts))

        var streamSources: [StreamSource] = []

        for candidate in webCandidates {
            do {
                let processor = WebViewRenderer()
                let extracted = try await processor.extractSources(
                    from: candidate.embedURL,
                    referer: candidate.embedURL,
                    providerName: "\(streamProviderDisplayName(for: candidate.sourceCode)) #\(candidate.streamNo)",
                    timeout: 8
                )
                let catalogHeaders: [String: String] = [
                    "X-Fotty-Nexus-Source": candidate.sourceCode,
                    "X-Fotty-Nexus-Stream": "\(candidate.streamNo)",
                    "X-Fotty-Nexus-Catalog": candidate.catalogProvider
                ]
                streamSources.append(contentsOf: extracted.map { $0.mergingHeaders(catalogHeaders) })

                if !extracted.isEmpty {
                    print("[LiveSports] Native source succeeded: \(candidate.sourceCode)#\(candidate.streamNo) via \(candidate.catalogProvider)")
                }
            } catch {
                print("[LiveSports] Candidate failed \(candidate.sourceCode)#\(candidate.streamNo): \(error.localizedDescription)")
                continue
            }
        }

        // If native extraction fails, expose a curated list of web fallbacks.
        if streamSources.isEmpty {
            for candidate in candidates.prefix(maxFallbackEmbedCandidates) {
                guard let url = URL(string: candidate.embedURL) else { continue }
                let origin = originString(for: url) ?? "https://embedsports.top"
                streamSources.append(
                    StreamSource(
                        url: url,
                        quality: "live",
                        provider: "\(streamProviderDisplayName(for: candidate.sourceCode)) #\(candidate.streamNo)",
                        subtitles: [],
                        headers: [
                            "Referer": candidate.embedURL,
                            "Origin": origin,
                            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
                            "X-Fotty-Nexus-Source": candidate.sourceCode,
                            "X-Fotty-Nexus-Stream": "\(candidate.streamNo)",
                            "X-Fotty-Nexus-Catalog": candidate.catalogProvider
                        ]
                    )
                )
            }
        }

        return streamSources
    }

    static func fallbackEmbedSources(for match: EventReference) -> [StreamSource] {
        guard let sources = match.sources, !sources.isEmpty else {
            return []
        }

        let sortedSources = sources.sorted { a, b in
            let aIdx = preferredSources.firstIndex(of: a.source) ?? preferredSources.count
            let bIdx = preferredSources.firstIndex(of: b.source) ?? preferredSources.count
            return aIdx < bIdx
        }

        var streamSources: [StreamSource] = []
        for source in sortedSources {
            guard supportsCanonicalEmbedFallback(sourceCode: source.source) else {
                continue
            }
            // This path is reached only when the catalog supplied no usable
            // variants. Keep one truthful fallback per family rather than
            // inventing multiple broadcast choices.
            for streamNo in [1] {
                guard let embedURL = canonicalEmbedURL(for: source, streamNo: streamNo),
                      let url = URL(string: embedURL),
                      !isDiscoveryOnlyEmbedURL(url) else {
                    continue
                }

                let referer = embedReferer(forSourceCode: source.source) ?? embedURL
                let origin = URL(string: referer).flatMap { originString(for: $0) } ?? "https://embed.st"
                streamSources.append(
                    StreamSource(
                        url: url,
                        quality: "live",
                        provider: "\(streamProviderDisplayName(for: source.source)) #\(streamNo)",
                        subtitles: [],
                        headers: [
                            "Referer": referer,
                            "Origin": origin,
                            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                            "X-Fotty-Nexus-Source": source.source,
                            "X-Fotty-Web-Embed": "true"
                        ]
                    )
                )
            }
        }

        return streamSources
    }

    nonisolated static func canonicalEmbedURL(for source: NexusASource, streamNo: Int) -> String? {
        let safeStreamNo = max(streamNo, 1)
        let sourcePart = encodedPathComponent(source.source)
        let idPart = encodedPathComponent(source.id)
        guard !sourcePart.isEmpty, !idPart.isEmpty else { return nil }
        return "\(canonicalEmbedOrigin)/embed/\(sourcePart)/\(idPart)/\(safeStreamNo)"
    }

    /// Only families with a maintained canonical embed contract may be used
    /// when every catalog mirror returned zero concrete variants. Echo/Admin
    /// require a provider-supplied URL; inventing one produces stale 404 rows.
    nonisolated static func supportsCanonicalEmbedFallback(sourceCode: String) -> Bool {
        ["hotel", "delta", "golf", "india"].contains(
            sourceCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }

    nonisolated static func embedReferer(forSourceCode sourceCode: String) -> String? {
        switch sourceCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "hotel":
            return "https://www.score808live.tv/"
        case "echo":
            return "https://www.vipleague.im/"
        case "delta", "golf", "india":
            return "https://www.streamex.net/"
        default:
            return "https://www.streamex.net/"
        }
    }

    /// Return all available sport events (live + upcoming) for browsing.
    static func allLiveEvents() async throws -> [EventReference] {
        return try await fetchLiveEvents()
    }

    @MainActor
    static func categoryDisplayName(for rawCategory: String) -> String {
        switch rawCategory {
        case "football", "soccer":
            return "Football"
        case "american-football", "nfl":
            return "American football"
        case "motor-sports", "motorsports":
            return "Motorsport"
        case "afl":
            return "AFL"
        case "basketball":
            return "Basketball"
        case "baseball":
            return "Baseball"
        case "hockey":
            return "Hockey"
        case "fight", "mma", "boxing":
            return "Fight"
        default:
            if rawCategory.isEmpty || rawCategory == "other" {
                return "Other"
            }
            return rawCategory.capitalized
        }
    }

    enum FootballLeagueTab: String, CaseIterable, Identifiable {
        case all
        case premierLeague
        case championsLeague
        case laLiga
        case serieA
        case bundesliga
        case ligue1
        case other

        var id: String { rawValue }

        @MainActor
        var displayName: String {
            switch self {
            case .all:
                return "All Football"
            case .premierLeague:
                return "Premier League"
            case .championsLeague:
                return "Champions League"
            case .laLiga:
                return "La Liga"
            case .serieA:
                return "Serie A"
            case .bundesliga:
                return "Bundesliga"
            case .ligue1:
                return "Ligue 1"
            case .other:
                return "Other Leagues"
            }
        }

        var badgeURL: URL? {
            switch self {
            case .premierLeague: return URL(string: "https://media.api-sports.io/football/leagues/39.png")
            case .championsLeague: return URL(string: "https://media.api-sports.io/football/leagues/2.png")
            case .laLiga: return URL(string: "https://media.api-sports.io/football/leagues/140.png")
            case .serieA: return URL(string: "https://media.api-sports.io/football/leagues/135.png")
            case .bundesliga: return URL(string: "https://media.api-sports.io/football/leagues/78.png")
            case .ligue1: return URL(string: "https://media.api-sports.io/football/leagues/61.png")
            default: return nil
            }
        }
    }

    enum FootballLeagueEvidence: String, Equatable {
        case officialFixture
        case providerMarker
        case rosterInference
        case nonDomesticMarker
        case unresolvedProviderMarker
        case none
    }

    struct FootballLeagueClassification: Equatable {
        let tab: FootballLeagueTab
        let evidence: FootballLeagueEvidence
        let reasonCode: String?

        var isIdentityConflict: Bool { evidence == .unresolvedProviderMarker }
    }

    static func sportIconName(for rawCategory: String) -> String {
        SportIdentity.symbol(for: rawCategory)
    }

    static func footballLeagueTabs(for matches: [EventReference]) -> [FootballLeagueTab] {
        [
            .all,
            .premierLeague,
            .championsLeague,
            .laLiga,
            .serieA,
            .bundesliga,
            .ligue1,
            .other
        ]
    }

    static func footballLeagueTab(
        for match: EventReference,
        officialMatch: FootballMatch? = nil
    ) -> FootballLeagueTab {
        footballLeagueClassification(for: match, officialMatch: officialMatch).tab
    }

    /// Official fixture identity wins only after `LiveScoreService` has matched
    /// both teams and a bounded kickoff. Provider metadata and seasonal rosters
    /// remain deterministic fallbacks when that reconciliation is unavailable.
    static func footballLeagueClassification(
        for match: EventReference,
        officialMatch: FootballMatch? = nil
    ) -> FootballLeagueClassification {
        if let officialMatch {
            return FootballLeagueClassification(
                tab: officialCompetitionTab(officialMatch.competition),
                evidence: .officialFixture,
                reasonCode: nil
            )
        }

        let sourceIdentity = match.sources?
            .map { "\($0.source) \($0.id)" }
            .joined(separator: " ") ?? ""
        let haystack = "\(match.id) \(match.title ?? "") \(sourceIdentity)".lowercased()
        let isCurrentPair: (FootballCompetitionID) -> Bool = { competition in
            FootballCompetitionCatalog.containsBoth(
                home: match.homeName,
                away: match.awayName,
                in: competition
            )
        }

        if containsAny(in: haystack, terms: ["champions league", "uefa champions", "champions-league", "ucl"]) {
            return FootballLeagueClassification(tab: .championsLeague, evidence: .providerMarker, reasonCode: nil)
        }
        let domesticMarkers: [(FootballLeagueTab, FootballCompetitionID, [String])] = [
            (.premierLeague, .premierLeague, ["premier league", "english premier", "premier-league", "epl"]),
            (.laLiga, .laLiga, ["la liga", "laliga", "la-liga"]),
            (.serieA, .serieA, ["serie a", "serie-a"]),
            (.bundesliga, .bundesliga, ["bundesliga"]),
            (.ligue1, .ligue1, ["ligue 1", "ligue-1", "ligue1"]),
        ]
        for (tab, competition, markers) in domesticMarkers where containsAny(in: haystack, terms: markers) {
            if hasNonDomesticCompetitionMarker(haystack) {
                return FootballLeagueClassification(tab: .other, evidence: .nonDomesticMarker, reasonCode: "non_domestic_marker")
            }
            guard isCurrentPair(competition) else {
                return FootballLeagueClassification(
                    tab: .other,
                    evidence: .unresolvedProviderMarker,
                    reasonCode: "provider_marker_membership_conflict"
                )
            }
            return FootballLeagueClassification(tab: tab, evidence: .providerMarker, reasonCode: nil)
        }
        if hasNonDomesticCompetitionMarker(haystack) {
            return FootballLeagueClassification(tab: .other, evidence: .nonDomesticMarker, reasonCode: "non_domestic_marker")
        }

        if isCurrentPair(.premierLeague) {
            return FootballLeagueClassification(tab: .premierLeague, evidence: .rosterInference, reasonCode: nil)
        }
        if isCurrentPair(.laLiga) {
            return FootballLeagueClassification(tab: .laLiga, evidence: .rosterInference, reasonCode: nil)
        }
        if isCurrentPair(.serieA) {
            return FootballLeagueClassification(tab: .serieA, evidence: .rosterInference, reasonCode: nil)
        }
        if isCurrentPair(.bundesliga) {
            return FootballLeagueClassification(tab: .bundesliga, evidence: .rosterInference, reasonCode: nil)
        }
        if isCurrentPair(.ligue1) {
            return FootballLeagueClassification(tab: .ligue1, evidence: .rosterInference, reasonCode: nil)
        }

        return FootballLeagueClassification(tab: .other, evidence: .none, reasonCode: nil)
    }

    private static func officialCompetitionTab(_ competition: MatchCompetition) -> FootballLeagueTab {
        switch competition.id {
        case 39, 2021: return .premierLeague
        case 2, 2001: return .championsLeague
        case 140, 2014: return .laLiga
        case 135, 2019: return .serieA
        case 78, 2002: return .bundesliga
        case 61, 2015: return .ligue1
        default: break
        }

        switch competition.code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "PL": return .premierLeague
        case "CL": return .championsLeague
        case "PD": return .laLiga
        case "SA": return .serieA
        case "BL1": return .bundesliga
        case "FL1": return .ligue1
        default: break
        }

        let name = competition.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let country = competition.country?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if ["champions league", "uefa champions league"].contains(name) { return .championsLeague }
        if ["premier league", "english premier league", "england premier league"].contains(name),
           country.isEmpty || country == "england" { return .premierLeague }
        if ["la liga", "primera division", "primera división"].contains(name), country.isEmpty || country == "spain" { return .laLiga }
        if name == "serie a", country.isEmpty || country == "italy" { return .serieA }
        if name == "bundesliga", country.isEmpty || country == "germany" { return .bundesliga }
        if ["ligue 1", "ligue1"].contains(name), country.isEmpty || country == "france" { return .ligue1 }
        return .other
    }

    // MARK: - Private

    static func fetchLiveEvents() async throws -> [EventReference] {
        var allMatches: [EventReference] = []

        for provider in providers {
            do {
                let matches = try await provider.fetchLiveEvents()
                allMatches.append(contentsOf: matches)
            } catch {
                print("[LiveSports] Provider \(provider.name) failed to fetch events: \(error.localizedDescription)")
            }
        }

        return deduplicateMatches(allMatches)
    }

    static func fetchLiveEvents_NexusAImplementation() async throws -> [EventReference] {
        return try await withThrowingTaskGroup(of: [EventReference].self) { group in
            for provider in dataFeedProfiles {
                group.addTask {
                    // Try primary feed first
                    if let matches = try? await fetchMatches(path: provider.matchesAllPath, baseURL: provider.baseURL), !matches.isEmpty {
                        print("[LiveSports] Loaded \(matches.count) matches via \(provider.label)")
                        return matches
                    }

                    // Fallback for older deployments or temporary API regressions.
                    var mergedMatches: [EventReference] = []
                    for path in [provider.matchesLivePath, provider.matchesUpcomingPath] {
                        if let matches = try? await fetchMatches(path: path, baseURL: provider.baseURL) {
                            mergedMatches.append(contentsOf: matches)
                        }
                    }
                    if !mergedMatches.isEmpty {
                        print("[LiveSports] Loaded \(mergedMatches.count) matches via \(provider.label) fallback feeds")
                        return mergedMatches
                    }
                    throw ProcessorError.noSourcesFound
                }
            }

            var firstValidMatches: [EventReference]?
            while let result = await group.nextResult() {
                if case .success(let matches) = result, !matches.isEmpty {
                    firstValidMatches = matches
                    group.cancelAll()
                    break
                }
            }

            if let matches = firstValidMatches {
                return deduplicateMatches(matches)
            }
            throw ProcessorError.noSourcesFound
        }
    }

    static func streamCandidates(
        for source: NexusASource,
        synthesizeWhenEmpty: Bool = true
    ) async -> [StreamCandidate] {
        let sourcePart = encodedPathComponent(source.source)
        let idPart = encodedPathComponent(source.id)

        var resolved = await withTaskGroup(of: [StreamCandidate].self) { group in
            for provider in dataFeedProfiles {
                let path = "\(provider.streamPathPrefix)/\(sourcePart)/\(idPart)"
                group.addTask {
                    do {
                        let variants = try await fetchStreamVariants(path: path, baseURL: provider.baseURL)
                        if !variants.isEmpty {
                            print("[LiveSports] \(source.source) catalog from \(provider.label): \(variants.count) variants")
                        }

                        var candidates: [StreamCandidate] = []
                        for variant in variants {
                            guard let embedURL = variant.embedUrl,
                                  URL(string: embedURL) != nil else {
                                continue
                            }

                            let streamNo = max(variant.streamNo ?? 1, 1)
                            let sourceCode = (variant.source?.isEmpty == false) ? (variant.source ?? source.source) : source.source
                            candidates.append(
                                StreamCandidate(
                                    sourceCode: sourceCode,
                                    streamNo: streamNo,
                                    language: variant.language,
                                    isHD: variant.hd ?? false,
                                    heatTier: variant.heatTier,
                                    embedURL: embedURL,
                                    catalogProvider: provider.label,
                                    viewers: variant.viewers
                                )
                            )
                        }
                        return candidates
                    } catch {
                        print("[LiveSports] Stream catalog failed \(provider.label) for \(source.source): \(error.localizedDescription)")
                        return []
                    }
                }
            }

            var collected: [StreamCandidate] = []
            for await providerCandidates in group {
                collected.append(contentsOf: providerCandidates)
            }
            return collected
        }

        // Catalog often returns [] for hotel/delta even when embed.st/{source}/{id} carries the full player.
        if synthesizeWhenEmpty,
           resolved.isEmpty,
           supportsCanonicalEmbedFallback(sourceCode: source.source),
           let embedURL = canonicalEmbedURL(for: source, streamNo: 1) {
            print("[LiveSports] Synthesizing embed.st URL for \(source.source)")
            resolved = [
                StreamCandidate(
                    sourceCode: source.source,
                    streamNo: 1,
                    language: nil,
                    isHD: true,
                    heatTier: "synthesized",
                    embedURL: embedURL,
                    catalogProvider: "embed.st"
                )
            ]
            if let second = canonicalEmbedURL(for: source, streamNo: 2) {
                resolved.append(
                    StreamCandidate(
                        sourceCode: source.source,
                        streamNo: 2,
                        language: nil,
                        isHD: true,
                        heatTier: "synthesized",
                        embedURL: second,
                        catalogProvider: "embed.st"
                    )
                )
            }
        }

        resolved.sort(by: compareCandidates)
        return deduplicateCandidates(resolved)
    }

    /// Turns raw provider variants into useful broadcast choices. HD/SD pairs
    /// for the same channel become one row, each source family gets a first
    /// chance, and the remaining slots favor the most-used alternatives.
    nonisolated static func curatedPlaybackCandidates(
        from candidateGroups: [[StreamCandidate]],
        limit: Int
    ) -> [StreamCandidate] {
        guard limit > 0 else { return [] }

        let groups = candidateGroups.compactMap { rawGroup -> [StreamCandidate]? in
            var bestByBroadcast: [String: StreamCandidate] = [:]
            for candidate in deduplicateCandidates(rawGroup) {
                let label = candidate.language?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let key = (label?.isEmpty == false)
                    ? label!
                    : "\(candidate.sourceCode.lowercased())#\(candidate.streamNo)"
                if let existing = bestByBroadcast[key] {
                    if isBetterBroadcastCandidate(candidate, than: existing) {
                        bestByBroadcast[key] = candidate
                    }
                } else {
                    bestByBroadcast[key] = candidate
                }
            }
            let group = bestByBroadcast.values.sorted(by: isBetterBroadcastCandidate)
            return group.isEmpty ? nil : group
        }

        var selected = groups.compactMap(\.first)
        let remaining = groups
            .flatMap { $0.dropFirst() }
            .sorted(by: isBetterBroadcastCandidate)
        selected.append(contentsOf: remaining)
        return Array(deduplicateCandidates(selected).prefix(limit))
    }

    nonisolated private static func isBetterBroadcastCandidate(
        _ lhs: StreamCandidate,
        than rhs: StreamCandidate
    ) -> Bool {
        if lhs.isHD != rhs.isHD { return lhs.isHD && !rhs.isHD }
        let lhsViewers = lhs.viewers ?? -1
        let rhsViewers = rhs.viewers ?? -1
        if lhsViewers != rhsViewers { return lhsViewers > rhsViewers }
        return lhs.streamNo < rhs.streamNo
    }

    private static func compareCandidates(_ lhs: StreamCandidate, _ rhs: StreamCandidate) -> Bool {
        let lhsSourceRank = preferredSources.firstIndex(of: lhs.sourceCode) ?? preferredSources.count
        let rhsSourceRank = preferredSources.firstIndex(of: rhs.sourceCode) ?? preferredSources.count
        if lhsSourceRank != rhsSourceRank {
            return lhsSourceRank < rhsSourceRank
        }

        let lhsHeatRank = heatTierRank(lhs.heatTier)
        let rhsHeatRank = heatTierRank(rhs.heatTier)
        if lhsHeatRank != rhsHeatRank {
            return lhsHeatRank < rhsHeatRank
        }

        if lhs.isHD != rhs.isHD {
            return lhs.isHD && !rhs.isHD
        }

        if lhs.streamNo != rhs.streamNo {
            return lhs.streamNo < rhs.streamNo
        }

        return lhs.embedURL < rhs.embedURL
    }

    private static func heatTierRank(_ heatTier: String?) -> Int {
        switch heatTier?.lowercased() {
        case "veryhigh":
            return 0
        case "high":
            return 1
        case "medium":
            return 2
        case "low":
            return 3
        case "none":
            return 4
        default:
            return 5
        }
    }

    private static func streamProviderDisplayName(for sourceCode: String) -> String {
        switch sourceCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "admin": return "StreamEx PPV"
        case "delta": return "StreamEx"
        case "echo": return "VipLeague"
        case "golf": return "MethStreams"
        case "hotel": return "Score808"
        case "india": return "StrikeOut"
        default:
            guard !sourceCode.isEmpty else { return "Web Source" }
            return sourceCode.uppercased()
        }
    }

    nonisolated private static func deduplicateCandidates(_ candidates: [StreamCandidate]) -> [StreamCandidate] {
        var seenURLs = Set<String>()
        var result: [StreamCandidate] = []

        for candidate in candidates {
            let key = candidate.embedURL.lowercased()
            if seenURLs.insert(key).inserted {
                result.append(candidate)
            }
        }

        return result
    }

    private static func isDiscoveryOnlyEmbedURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "scraper.pixel-invoice.com"
    }

    nonisolated private static func encodedPathComponent(_ value: String) -> String {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func fetchStreamVariants(path: String, baseURL: String) async throws -> [LiveStreamVariant] {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw ProcessorError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue(baseURL, forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await feedSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ProcessorError.httpError
        }

        let decoder = JSONDecoder()
        if let variants = try? decoder.decode([LiveStreamVariant].self, from: data) {
            return variants
        }
        if let envelope = try? decoder.decode(LiveStreamVariantEnvelope.self, from: data) {
            return envelope.allVariants
        }
        return []
    }

    private static func fetchMatches(path: String, baseURL: String) async throws -> [EventReference] {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw ProcessorError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue(baseURL, forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await feedSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ProcessorError.httpError
        }

        return try decodeMatches(from: data)
    }

    private static func decodeMatches(from data: Data) throws -> [EventReference] {
        let decoder = JSONDecoder()

        if let matches = try? decoder.decode([EventReference].self, from: data) {
            return matches
        }

        if let response = try? decoder.decode(NexusALiveResponse.self, from: data) {
            return response.matches ?? []
        }

        throw ProcessorError.invalidData
    }

    private static func deduplicateMatches(_ matches: [EventReference]) -> [EventReference] {
        var seenIds = Set<String>()
        var result: [EventReference] = []

        for match in matches {
            if seenIds.insert(match.id).inserted {
                result.append(match)
            }
        }

        return result
    }

    private static func normalizedCategoryKey(_ rawCategory: String?) -> String {
        let raw = rawCategory?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !raw.isEmpty else { return "other" }

        switch raw {
        case "soccer":
            return "football"
        case "mma", "boxing", "ufc", "pfl", "bellator", "one":
            return "fight"
        case "nba", "wnba", "ncaab", "ncaa", "fiba", "euroleague", "acb", "bbl":
            return "basketball"
        case "mlb", "npb", "kbo":
            return "baseball"
        case "nhl", "khl", "ahl":
            return "hockey"
        default:
            return raw
        }
    }

    private static func containsAny(in text: String, terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }

    private static func hasNonDomesticCompetitionMarker(_ text: String) -> Bool {
        containsAny(in: text, terms: [
            "premier league 2", "premier-league-2", "premier league cup", "premier-league-cup",
            "fa cup", "fa-cup", "efl cup", "efl-cup", "league cup", "carabao",
            "community shield", "championship", "league one", "league-one", "league two",
            "league-two", "bundesliga 2", "2. bundesliga", "copa del rey", "coppa italia", "dfb pokal", "coupe de france",
            "europa league", "conference league", "friendly", " u18", " u19", " u21", " u23",
            "women", "ladies", "youth", "academy", "reserves",
        ])
    }

    private static func originString(for url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private static func imageURL(from raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }

        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }

        if raw.hasPrefix("/api/") {
            let s = StringObfuscator.decode([0x2E, 0x1B, 0x0, 0x4, 0xA, 0x7B, 0x41, 0x4E, 0x1F, 0x1A, 0x6, 0x8, 0x13, 0x16, 0x24, 0x1C, 0x36, 0x6, 0xC, 0x11, 0x15, 0x6C, 0x7, 0xF, 0x1A, 0x16, 0x1D, 0xA, 0x6, 0x5D, 0x35, 0x5D, 0x2B]) // "https://streamed.pk"
            let sx = StringObfuscator.decode([0x2E, 0x1B, 0x0, 0x4, 0xA, 0x7B, 0x41, 0x4E, 0x1B, 0xE, 0x3, 0x47, 0x10, 0x7, 0x24, 0x57, 0x27, 0x2, 0x11, 0xC, 0x57, 0x2F, 0xB, 0x15]) // "https://www.nx.net"
            return URL(string: s + raw) ?? URL(string: sx + raw)
        }

        // Most badge values are proxy tokens. (obfuscated)
        let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? raw
        let badgeBase = StringObfuscator.decode([0x2E, 0x1B, 0x0, 0x4, 0xA, 0x7B, 0x41, 0x4E, 0x1F, 0xD, 0x6, 0xC, 0x2, 0x1E, 0x33, 0x56, 0x68, 0x1F, 0x1F, 0x4, 0x11, 0x1C, 0x4B, 0x1D, 0xA, 0x7, 0x7, 0x5, 0x17, 0x4A, 0x6, 0x0, 0x0, 0x1, 0x1, 0x4F])
        let proxyBase = StringObfuscator.decode([0x2E, 0x1B, 0x0, 0x4, 0xA, 0x7B, 0x41, 0x4E, 0x1B, 0xE, 0x3, 0x47, 0x10, 0x7, 0x24, 0x57, 0x27, 0x2, 0x11, 0xC, 0x57, 0x2F, 0xB, 0x15, 0x4, 0x11, 0x1C, 0x4B, 0x1D, 0xA, 0x7, 0x7, 0x5, 0x17, 0x4A, 0x1, 0xA, 0x6, 0x1E, 0x1B, 0x41])
        return URL(string: badgeBase + "\(encoded).webp") ?? URL(string: proxyBase + "\(encoded)")
    }

    /// Fuzzy match a football-data.org match to a NexusA live event
    private static func findMatch(
        events: [EventReference],
        homeTeam: String,
        awayTeam: String
    ) -> EventReference? {

        let canonicalHome = FootballCompetitionCatalog.canonicalClubID(for: homeTeam)
        let canonicalAway = FootballCompetitionCatalog.canonicalClubID(for: awayTeam)
        if let canonicalHome, let canonicalAway,
           let exactIdentityMatch = events.first(where: { event in
               guard event.normalizedCategory == "football" else { return false }
               return FootballCompetitionCatalog.canonicalClubID(for: event.homeName) == canonicalHome
                   && FootballCompetitionCatalog.canonicalClubID(for: event.awayName) == canonicalAway
           }) {
            return exactIdentityMatch
        }

        // Unknown clubs retain the bounded legacy word matcher as a fallback;
        // recognized clubs never depend on title substrings or abbreviations.
        let homeWords = normalizeTeam(homeTeam)
        let awayWords = normalizeTeam(awayTeam)

        // Score each event by how many team name words match
        var bestMatch: (event: EventReference, score: Int)?

        for event in events {
            guard let title = event.title?.lowercased() else { continue }

            // Must be football category
            if let category = event.category?.lowercased(),
               category != "football" && category != "soccer" { continue }

            var score = 0

            for word in homeWords {
                if title.contains(word) { score += 1 }
            }
            for word in awayWords {
                if title.contains(word) { score += 1 }
            }

            // Need at least 2 matching words (one from each team minimum)
            if score >= 2 {
                if score > (bestMatch?.score ?? -1) {
                    bestMatch = (event, score)
                }
            }
        }

        return bestMatch?.event
    }

    /// Normalize a team name into searchable words
    private static func normalizeTeam(_ name: String) -> [String] {
        let cleaned = name.lowercased()
            .replacingOccurrences(of: " fc", with: "")
            .replacingOccurrences(of: " cf", with: "")
            .replacingOccurrences(of: " afc", with: "")
            // NOTE: Do NOT replace "united" → "utd". The NexusA catalog uses full team names
            // (e.g. "Manchester United vs …"), so the replacement kills the title match.

        // Use > 1 (length >= 2) so 3-char tokens like "PSG", "BVB", "Man" are kept.
        let words = cleaned.components(separatedBy: .whitespaces)
            .filter { $0.count > 1 }

        // Also add common abbreviation mappings
        var result = words

        let abbreviations: [String: [String]] = [
            "manchester": ["man"],
            "liverpool": ["liverpool"],
            "arsenal": ["arsenal"],
            "chelsea": ["chelsea"],
            "tottenham": ["tottenham", "spurs"],
            "newcastle": ["newcastle"],
            "city": ["city"],
            "palace": ["crystal", "palace"],
            "wolves": ["wolverhampton", "wolves"],
            "nottingham": ["nottingham", "forest"],
            "brighton": ["brighton"],
            "bournemouth": ["bournemouth"],
            "brentford": ["brentford"],
            "fulham": ["fulham"],
            "everton": ["everton"],
            "burnley": ["burnley"],
            "villa": ["aston", "villa"],
            "paris": ["psg", "paris"],
            "bayern": ["bayern", "munich"],
            "barcelona": ["barcelona", "barca"],
            "madrid": ["real", "madrid"],
            "juventus": ["juventus", "juve"],
            "inter": ["inter", "milan"],
            "dortmund": ["dortmund", "bvb"],
        ]

        for word in words {
            if let extras = abbreviations[word] {
                result.append(contentsOf: extras)
            }
        }

        return Array(Set(result))
    }

    private static func isP2PCandidate(_ candidate: StreamCandidate) -> Bool {
        let url = candidate.embedURL.lowercased()
        return url.contains("acestream://") || url.contains("/proxy/acestream/")
    }

}
