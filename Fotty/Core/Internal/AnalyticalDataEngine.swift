import Foundation
import OSLog

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
                self.matches = try container.decode([EventReference].self, forKey: .matches)
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
        /// Fotty-owned ingestion metadata. Persist the quarantine in local
        /// caches, but never allow it to advertise or resolve a delivery route.
        let hasCatalogIdentityConflict: Bool
        /// Optional schedule/status receipt; old provider and saved JSON remains
        /// decodable. It never supplies a stream URL or channel programme.
        let cricketFixture: CricketFixtureMetadata?
        let sportsFixture: SportsFixtureMetadata?
        /// Exact competition evidence from an official schedule or fixture feed.
        let competitionID: String?

        enum CodingKeys: String, CodingKey {
            case id, title, category, date, poster, popular, teams, sources
            case hasCatalogIdentityConflict = "_fottyIdentityConflict"
            case cricketFixture = "_fottyCricketFixture"
            case sportsFixture = "_fottySportsFixture"
            case competitionID = "_fottyCompetitionID"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            category = try container.decodeIfPresent(String.self, forKey: .category)
            date = try container.decodeIfPresent(Int64.self, forKey: .date)
            poster = try container.decodeIfPresent(String.self, forKey: .poster)
            popular = try container.decodeIfPresent(Bool.self, forKey: .popular)
            teams = try container.decodeIfPresent(NexusATeams.self, forKey: .teams)
            hasCatalogIdentityConflict = try container.decodeIfPresent(Bool.self, forKey: .hasCatalogIdentityConflict) ?? false
            cricketFixture = try container.decodeIfPresent(CricketFixtureMetadata.self, forKey: .cricketFixture)
            sportsFixture = try container.decodeIfPresent(SportsFixtureMetadata.self, forKey: .sportsFixture)
            competitionID = try container.decodeIfPresent(String.self, forKey: .competitionID) ?? sportsFixture?.competitionID
            let decodedSources = try container.decodeIfPresent([NexusASource].self, forKey: .sources)
            sources = hasCatalogIdentityConflict ? [] : decodedSources

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
            sources: [NexusASource]?,
            hasCatalogIdentityConflict: Bool = false,
            cricketFixture: CricketFixtureMetadata? = nil,
            sportsFixture: SportsFixtureMetadata? = nil,
            competitionID: String? = nil
        ) {
            self.id = id
            self.title = title
            self.category = category
            self.date = date
            self.poster = poster
            self.popular = popular
            self.teams = teams
            self.hasCatalogIdentityConflict = hasCatalogIdentityConflict
            self.cricketFixture = cricketFixture
            self.sportsFixture = sportsFixture
            self.competitionID = competitionID ?? sportsFixture?.competitionID
            self.sources = hasCatalogIdentityConflict ? [] : sources
        }

        nonisolated var kickoffDate: Date? {
            guard let date, date > 0 else { return nil }
            if date > 10_000_000_000 {
                return Date(timeIntervalSince1970: Double(date) / 1000)
            }
            return Date(timeIntervalSince1970: Double(date))
        }

        /// Live feed: retain enough trusted future catalog for the personalized
        /// three-day Home window while still dropping months/years-old junk.
        /// Broadcast channels and unknown kickoffs remain available.
        nonisolated func passesNearTermLiveListWindow(at now: Date = .init()) -> Bool {
            guard !hasCatalogIdentityConflict else { return false }
            if isBroadcastChannel { return true }
            guard let kickoff = kickoffDate else { return true }
            if cricketFixture != nil || sportsFixture != nil {
                return kickoff >= now.addingTimeInterval(-14 * 86400)
                    && kickoff <= now.addingTimeInterval(CatalogTimingPolicy.retentionFutureHorizon)
            }
            return kickoff >= now.addingTimeInterval(-CatalogTimingPolicy.retentionPastGrace)
                && kickoff <= now.addingTimeInterval(CatalogTimingPolicy.retentionFutureHorizon)
        }

        var normalizedCategory: String {
            AnalyticalDataEngine.normalizedCategoryKey(category)
        }

        var categoryDisplayName: String {
            AnalyticalDataEngine.categoryDisplayName(for: normalizedCategory)
        }

        var homeName: String {
            if isBroadcastChannel { return title ?? "Cricket channel" }
            if let sportsFixture, sportsFixture.eventKind != .match { return sportsFixture.title }
            if let explicit = teams?.home?.name, !explicit.isEmpty {
                return explicit
            }
            return splitTeamsFromTitle().home
        }

        var awayName: String {
            if isBroadcastChannel { return "" }
            if let sportsFixture, sportsFixture.eventKind != .match { return "" }
            if let explicit = teams?.away?.name, !explicit.isEmpty {
                return explicit
            }
            return splitTeamsFromTitle().away
        }

        var homeBadgeURL: URL? {
            guard !hasCatalogIdentityConflict else { return nil }
            return AnalyticalDataEngine.imageURL(from: teams?.home?.badge)
                ?? TeamBrandService.sportSpecificBadgeURL(for: homeName, category: normalizedCategory)
        }

        var awayBadgeURL: URL? {
            guard !hasCatalogIdentityConflict else { return nil }
            return AnalyticalDataEngine.imageURL(from: teams?.away?.badge)
                ?? TeamBrandService.sportSpecificBadgeURL(for: awayName, category: normalizedCategory)
        }

        var posterURL: URL? {
            hasCatalogIdentityConflict ? nil : AnalyticalDataEngine.imageURL(from: poster)
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
            // An official fixture is schedule truth, not evidence that a
            // provider has published a playable route.
            self.sources = []
            self.hasCatalogIdentityConflict = false
            self.cricketFixture = nil
            self.sportsFixture = nil
            switch AnalyticalDataEngine.officialCompetitionTab(match.competition) {
            case .premierLeague: self.competitionID = "premier-league"
            case .championsLeague: self.competitionID = "champions-league"
            case .laLiga: self.competitionID = "la-liga"
            case .serieA: self.competitionID = "serie-a"
            case .bundesliga: self.competitionID = "bundesliga"
            case .ligue1: self.competitionID = "ligue-1"
            default: self.competitionID = nil
            }
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

    struct LiveStreamVariant: Decodable {
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

        private enum CodingKeys: String, CodingKey { case data, streams, variants, sources }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            data = try values.decodeIfPresent([LiveStreamVariant].self, forKey: .data)
            streams = try values.decodeIfPresent([LiveStreamVariant].self, forKey: .streams)
            variants = try values.decodeIfPresent([LiveStreamVariant].self, forKey: .variants)
            sources = try values.decodeIfPresent([LiveStreamVariant].self, forKey: .sources)
            guard data != nil || streams != nil || variants != nil || sources != nil else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                    debugDescription: "Stream catalog has no recognized variant array"))
            }
        }

        var allVariants: [LiveStreamVariant] {
            data ?? streams ?? variants ?? sources ?? []
        }
    }

    struct StreamCandidate: Sendable {
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

    private struct StreamCandidateLookup: Sendable {
        var candidates: [StreamCandidate] = []
        var confirmedEmpty = false
    }

    // Preferred source order — StreamEx + Score808 first (VipLeague/P2P retired from player).
    // hotel (Score808) + delta (StreamEx) — player allowlist is these two.
    private static let preferredSources = ["admin", "delta", "golf", "hotel", "echo", "india"]
    nonisolated private static let canonicalEmbedOrigin = "https://embed.st"
    private static let feedBodyClient: FottyBoundedHTTPClient = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 7
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return FottyBoundedHTTPClient(configuration: configuration)
    }()
    nonisolated static let maximumStreamVariantBytes = 512 * 1024
    nonisolated static let maximumStreamVariants = 128
    nonisolated static let maximumMatchCatalogBytes = 4 * 1024 * 1024
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
        awayTeam: String,
        kickoffDate: Date? = nil,
        matchID: String = "",
        category: String = "football"
    ) async throws -> [StreamSource] {
        // 1. Fetch all live events from NexusA
        let events = try await fetchLiveEvents_NexusAImplementation()

        // Name-only legacy callers cannot prove which day's fixture they mean.
        // Active fallback callers supply the same dated identity as Watch.
        let request = StreamPlaybackRequest(matchID: matchID,
            displayTitle: "\(homeTeam) vs \(awayTeam)", homeTeam: homeTeam, awayTeam: awayTeam,
            category: category, kickoffDate: kickoffDate)
        guard let match = CatalogPlaybackIdentity.matchingEvent(for: request, in: events) else {
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
        return try await browsableCatalogEvents(from: fetchLiveEvents())
    }

    static func liveCatalogSnapshot() async throws -> LiveCatalogSnapshot {
        var snapshots: [LiveCatalogSnapshot] = []
        var failedProviders = 0
        for provider in providers {
            try Task.checkCancellation()
            do { snapshots.append(try await provider.fetchCatalogSnapshot()) }
            catch {
                try Task.checkCancellation()
                failedProviders += 1
            }
        }
        try Task.checkCancellation()
        guard !snapshots.isEmpty else { throw URLError(.cannotLoadFromNetwork) }
        return LiveCatalogSnapshot(
            events: deduplicateMatches(snapshots.flatMap(\.events)),
            checkedAt: snapshots.map(\.checkedAt).min() ?? Date(),
            source: snapshots.map(\.source).joined(separator: ", "),
            respondingFeeds: snapshots.reduce(0) { $0 + $1.respondingFeeds },
            attemptedFeeds: snapshots.reduce(failedProviders) { $0 + $1.attemptedFeeds },
            isPartial: failedProviders > 0 || snapshots.contains(where: \.isPartial)
        )
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

    /// Converts the independently verified schedule into source-free catalog
    /// rows. Home/Matchday can therefore show a Champions League fixture even
    /// before a stream provider publishes it, without inventing Watch access.
    static func officialScheduleEvents(
        from matches: [FootballMatch],
        competition: FootballLeagueTab
    ) -> [EventReference] {
        matches.compactMap { match in
            guard officialCompetitionTab(match.competition) == competition,
                  match.matchDate != nil else { return nil }
            return EventReference(from: match)
        }
    }

    /// Official fixture identity wins only after `LiveScoreService` has matched
    /// both teams and a bounded kickoff. Provider metadata and seasonal rosters
    /// remain deterministic fallbacks when that reconciliation is unavailable.
    static func footballLeagueClassification(
        for match: EventReference,
        officialMatch: FootballMatch? = nil
    ) -> FootballLeagueClassification {
        guard !match.hasCatalogIdentityConflict else {
            return FootballLeagueClassification(tab: .other, evidence: .unresolvedProviderMarker,
                reasonCode: "conflicting_catalog_identity")
        }
        if let officialMatch {
            return FootballLeagueClassification(
                tab: officialCompetitionTab(officialMatch.competition),
                evidence: .officialFixture,
                reasonCode: nil
            )
        }

        if let fixture = match.sportsFixture, fixture.sport == "football" {
            let tabs: [String: FootballLeagueTab] = ["premier-league": .premierLeague,
                "champions-league": .championsLeague, "la-liga": .laLiga, "serie-a": .serieA,
                "bundesliga": .bundesliga, "ligue-1": .ligue1]
            if let tab = tabs[fixture.competitionID] {
                return FootballLeagueClassification(tab: tab,
                    evidence: fixture.verified ? .officialFixture : .providerMarker, reasonCode: nil)
            }
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
        try await liveCatalogSnapshot().events
    }

    static func browsableCatalogEvents(from events: [EventReference]) -> [EventReference] {
        events.filter { !$0.hasCatalogIdentityConflict }
    }

    static func fetchLiveEvents_NexusAImplementation(budget: Duration = .seconds(7)) async throws -> [EventReference] {
        try await fetchCatalogSnapshot_NexusAImplementation(budget: budget).events
    }

    static func fetchCatalogSnapshot_NexusAImplementation(budget: Duration = .seconds(7)) async throws -> LiveCatalogSnapshot {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: budget)
        var normalized: [LiveCatalogSnapshot.Observation]?
        if let url = Config.footballProxyBaseURL?.appendingPathComponent("api/live/catalog") {
            do {
                let components = budget.components
                let seconds = min(6, max(0.1, Double(components.seconds) + Double(components.attoseconds) / 1e18))
                var request = URLRequest(url: url)
                request.timeoutInterval = seconds
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let body = try await feedBodyClient.fetch(request, maximumBytes: maximumMatchCatalogBytes,
                    deadline: seconds, redirectPolicy: { original, target in
                        original.scheme == target.scheme && original.host == target.host && original.port == target.port
                    }).data
                normalized = try decodeBroadcastCatalog(from: body)
            } catch {
                try Task.checkCancellation()
                // During rollout/edge failure, use the already reviewed direct
                // adapter inside the SAME total clock. A valid unavailable
                // envelope below does not duplicate all provider requests.
            }
        }
        try Task.checkCancellation()
        if let normalized { return try LiveCatalogSnapshot.combine(normalized) }
        let remaining = clock.now.duration(to: deadline)
        guard remaining > .zero else { throw URLError(.timedOut) }
        return try await fetchDirectCatalogSnapshot(budget: remaining)
    }

    private struct BroadcastCatalogEnvelope: Decodable {
        struct Provider: Decodable {
            let id: String
            let family: String
            let outcome: String
            let matches: [EventReference]
        }
        let schemaVersion: Int
        let observedAt: Date
        let independentFamilies: Int
        let providers: [Provider]
    }

    static func decodeBroadcastCatalog(from data: Data, at now: Date = Date()) throws -> [LiveCatalogSnapshot.Observation] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else { throw ProcessorError.invalidData }
            return date
        }
        let envelope = try decoder.decode(BroadcastCatalogEnvelope.self, from: data)
        let ids = Set(["nexus-primary", "nexus-mirror", "nexus-backup"])
        guard envelope.schemaVersion == 1, envelope.independentFamilies == 1,
              envelope.providers.count == ids.count,
              Set(envelope.providers.map(\.id)) == ids,
              now.timeIntervalSince(envelope.observedAt) >= -30,
              now.timeIntervalSince(envelope.observedAt) <= 120 else { throw ProcessorError.invalidData }
        return try envelope.providers.map { provider in
            guard provider.family == "nexus", provider.matches.count <= 4_000,
                  ["available", "empty", "partial", "unavailable"].contains(provider.outcome),
                  provider.outcome != "available" || !provider.matches.isEmpty,
                  !["empty", "unavailable"].contains(provider.outcome) || provider.matches.isEmpty,
                  provider.matches.allSatisfy({ row in
                      !row.hasCatalogIdentityConflict && row.sportsFixture == nil && row.cricketFixture == nil
                          && row.competitionID == nil && !row.id.isEmpty && row.id.utf8.count <= 256
                          && (row.title?.isEmpty == false) && (row.title?.utf8.count ?? 0) <= 512
                          && (row.sources?.count ?? 0) <= 64
                  }) else { throw ProcessorError.invalidData }
            return .init(source: provider.id, events: provider.outcome == "unavailable" ? nil : provider.matches,
                         isPartial: provider.outcome == "partial")
        }
    }

    private static func fetchDirectCatalogSnapshot(budget: Duration) async throws -> LiveCatalogSnapshot {
        // Check the bounded mirror set, not whichever returns first. An empty
        // valid feed is a result; an error-shaped JSON object is not one.
        let accumulator = LiveCatalogAccumulator(sources: dataFeedProfiles.map(\.label))
        await withTaskGroup(of: Bool.self) { group in
            // One catalog clock, including fallback endpoints. Retain completed
            // mirrors on expiry and label the missing coverage explicitly.
            group.addTask {
                try? await Task.sleep(for: budget)
                return true
            }
            for provider in dataFeedProfiles {
                group.addTask {
                    do {
                        let matches = try await fetchMatches(path: provider.matchesAllPath, baseURL: provider.baseURL)
                        await accumulator.record(matches, source: provider.label)
                        return false
                    } catch {
                        guard !Task.isCancelled else { return false }
                    }
                    // The two complementary fallback feeds share the second
                    // five-second stage. Preserve one if the other is down.
                    await withTaskGroup(of: Void.self) { fallbacks in
                        for path in [provider.matchesLivePath, provider.matchesUpcomingPath] {
                            fallbacks.addTask {
                                if let rows = try? await fetchMatches(path: path, baseURL: provider.baseURL) {
                                    await accumulator.record(rows, source: provider.label, fallbackPart: path)
                                }
                            }
                        }
                    }
                    return false
                }
            }
            var completed = 0
            for await expired in group {
                if expired { break }
                completed += 1
                if completed == dataFeedProfiles.count { break }
            }
            group.cancelAll()
        }
        try Task.checkCancellation()
        return try LiveCatalogSnapshot.combine(accumulator.observations)
    }

    static func streamCandidates(
        for source: NexusASource,
        synthesizeWhenEmpty: Bool = true,
        onCandidates: (@Sendable ([StreamCandidate]) -> Void)? = nil,
        onEmptyCatalog: (@Sendable () -> Void)? = nil,
        onFailure: (@Sendable (String, Error) -> Void)? = nil
    ) async -> [StreamCandidate] {
        guard !Task.isCancelled else { return [] }
        let sourcePart = encodedPathComponent(source.source)
        let idPart = encodedPathComponent(source.id)

        let lookup = await withTaskGroup(of: StreamCandidateLookup.self) { group in
            for provider in dataFeedProfiles {
                let path = "\(provider.streamPathPrefix)/\(sourcePart)/\(idPart)"
                group.addTask {
                    do {
                        let variants = try await fetchStreamVariants(path: path, baseURL: provider.baseURL)
                        if variants.isEmpty {
                            guard !Task.isCancelled else { return StreamCandidateLookup() }
                            onEmptyCatalog?()
                            return StreamCandidateLookup(confirmedEmpty: true)
                        }
                        print("[LiveSports] \(source.source) catalog from \(provider.label): \(variants.count) variants")

                        var candidates: [StreamCandidate] = []
                        for variant in variants {
                            guard let embedURL = variant.embedUrl else {
                                continue
                            }

                            let streamNo = max(variant.streamNo ?? 1, 1)
                            let sourceCode = (variant.source?.isEmpty == false) ? (variant.source ?? source.source) : source.source
                            guard let url = URL(string: embedURL),
                                  StreamPluginProviderMatching.allowsSharedPlaybackURL(
                                    url,
                                    sourceCode: sourceCode
                                  ) else { continue }
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
                        // A nonempty catalog whose routes were missing or not
                        // admitted is not evidence for canonical fallback.
                        guard !candidates.isEmpty else { throw ProcessorError.invalidData }
                        guard !Task.isCancelled else { return StreamCandidateLookup() }
                        onCandidates?(curatedPlaybackCandidates(from: [candidates], limit: 32))
                        return StreamCandidateLookup(candidates: candidates)
                    } catch {
                        guard !Task.isCancelled else { return StreamCandidateLookup() }
                        onFailure?(provider.label, error)
                        print("[LiveSports] Stream catalog failed \(provider.label) for \(source.source): \(error.localizedDescription)")
                        return StreamCandidateLookup()
                    }
                }
            }

            var collected = StreamCandidateLookup()
            for await providerLookup in group {
                collected.candidates.append(contentsOf: providerLookup.candidates)
                collected.confirmedEmpty = collected.confirmedEmpty || providerLookup.confirmedEmpty
            }
            return collected
        }
        var resolved = lookup.candidates

        // Catalog often returns [] for hotel/delta even when embed.st/{source}/{id} carries the full player.
        if !Task.isCancelled, synthesizeWhenEmpty,
           lookup.confirmedEmpty,
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

    /// Preserve concrete delivery alternatives, including same-label HD/SD
    /// routes. Round-robin families so one large catalog cannot fill the entire
    /// validation budget before another family's first or second choice.
    nonisolated static func curatedPlaybackCandidates(
        from candidateGroups: [[StreamCandidate]],
        limit: Int
    ) -> [StreamCandidate] {
        guard limit > 0 else { return [] }

        var familyOrder: [String] = []
        var byFamily: [String: [StreamCandidate]] = [:]
        for candidate in candidateGroups.flatMap({ $0 }) {
            let family = candidate.sourceCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if byFamily[family] == nil { familyOrder.append(family) }
            byFamily[family, default: []].append(candidate)
        }
        let groups = familyOrder.map { family in
            deduplicateCandidates((byFamily[family] ?? []).sorted(by: isBetterBroadcastCandidate))
        }
        var selected: [StreamCandidate] = []
        var index = 0
        while selected.count < limit {
            var added = false
            for group in groups where index < group.count {
                selected.append(group[index])
                added = true
                if selected.count == limit { break }
            }
            guard added else { break }
            index += 1
        }
        return selected
    }

    nonisolated private static func isBetterBroadcastCandidate(
        _ lhs: StreamCandidate,
        than rhs: StreamCandidate
    ) -> Bool {
        if lhs.isHD != rhs.isHD { return lhs.isHD && !rhs.isHD }
        let lhsViewers = lhs.viewers ?? -1
        let rhsViewers = rhs.viewers ?? -1
        if lhsViewers != rhsViewers { return lhsViewers > rhsViewers }
        if lhs.streamNo != rhs.streamNo { return lhs.streamNo < rhs.streamNo }
        if lhs.embedURL != rhs.embedURL { return lhs.embedURL < rhs.embedURL }
        return lhs.catalogProvider < rhs.catalogProvider
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
            // Provider mirrors returning the same URL/family are duplicates;
            // path case, query parameters and distinct family headers are not.
            let family = candidate.sourceCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let key = "\(family)|\(candidate.embedURL)"
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

        let response = try await feedBodyClient.fetch(request,
            maximumBytes: maximumStreamVariantBytes, deadline: 7)
        try Task.checkCancellation()
        return try decodeStreamVariants(from: response.data)
    }

    /// An error-shaped HTTP200 response is not a valid empty catalog and must
    /// reach the resolver's failure path rather than trigger empty fallback.
    static func decodeStreamVariants(from data: Data) throws -> [LiveStreamVariant] {
        guard data.count <= maximumStreamVariantBytes else { throw ProcessorError.invalidData }
        let decoder = JSONDecoder()
        let variants: [LiveStreamVariant]
        if let array = try? decoder.decode([LiveStreamVariant].self, from: data) { variants = array }
        else { variants = try decoder.decode(LiveStreamVariantEnvelope.self, from: data).allVariants }
        guard variants.count <= maximumStreamVariants,
              variants.allSatisfy({ ($0.embedUrl?.utf8.count ?? 0) <= 16_384
                  && ($0.source?.utf8.count ?? 0) <= 100
                  && ($0.language?.utf8.count ?? 0) <= 100
                  && ($0.heatTier?.utf8.count ?? 0) <= 100 }) else { throw ProcessorError.invalidData }
        return variants
    }

    static func fetchMatches(path: String, baseURL: String,
                             transport: FottyBoundedHTTPClient? = nil) async throws -> [EventReference] {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw ProcessorError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue(baseURL, forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        do {
            let bodyInterval = FottyPerformanceTrace.catalog.beginInterval("CatalogBodyRead")
            defer { FottyPerformanceTrace.catalog.endInterval("CatalogBodyRead", bodyInterval) }
            // URLSession delegate chunks are accumulated off MainActor. The
            // complete-body mode retains the same 4 MiB ingestion limit while
            // avoiding one actor-isolated append for every individual byte.
            data = try await (transport ?? feedBodyClient).fetch(request,
                maximumBytes: maximumMatchCatalogBytes, deadline: 5).data
        } catch let failure as FottyBoundedHTTPClient.Failure {
            switch failure {
            case .responseTooLarge: throw ProcessorError.invalidData
            case .httpStatus(_), .invalidResponse: throw ProcessorError.httpError
            case .unsafeRedirect: throw failure
            }
        }
        try Task.checkCancellation()
        let decodeInterval = FottyPerformanceTrace.catalog.beginInterval("CatalogDecode")
        defer { FottyPerformanceTrace.catalog.endInterval("CatalogDecode", decodeInterval) }
        let matches = try decodeMatches(from: data)
        guard matches.count <= 10_000 else { throw ProcessorError.invalidData }
        return matches
    }

    static func decodeMatches(from data: Data) throws -> [EventReference] {
        let decoder = JSONDecoder()

        if let matches = try? decoder.decode([EventReference].self, from: data) {
            return matches
        }

        if let response = try? decoder.decode(NexusALiveResponse.self, from: data) {
            return response.matches ?? []
        }

        throw ProcessorError.invalidData
    }

    static func deduplicateMatches(_ matches: [EventReference]) -> [EventReference] {
        var accumulator = MatchDeduplicationAccumulator(capacity: matches.count)
        for match in matches { accumulator.acceptID(match) }
        for match in accumulator.matchesByID { accumulator.acceptFixture(match) }
        return accumulator.merged
    }

    /// Home yields between bounded batches while retaining exactly the same
    /// two-pass identity/merge rules as synchronous callers. Intermediate rows
    /// stay local; cancellation or a newer request discards the whole result.
    /// The work count covers both passes and permits deterministic batch tests
    /// without publishing fixture identities or partially prepared snapshots.
    static func deduplicateMatchesCooperatively(
        _ matches: [EventReference],
        isCurrent: () -> Bool,
        checkpoint: (_ processedRows: Int) async -> Bool
    ) async -> [EventReference]? {
        func acceptsRequest() -> Bool { !Task.isCancelled && isCurrent() }
        guard acceptsRequest() else { return nil }
        var accumulator = MatchDeduplicationAccumulator(capacity: matches.count)
        var processedRows = 0
        func suspend() async -> Bool {
            guard acceptsRequest() else { return false }
            guard await checkpoint(processedRows) else { return false }
            return acceptsRequest()
        }
        for (index, match) in matches.enumerated() {
            guard acceptsRequest() else { return nil }
            accumulator.acceptID(match)
            processedRows += 1
            if (index + 1).isMultiple(of: 32), !(await suspend()) { return nil }
        }
        if !matches.count.isMultiple(of: 32), !(await suspend()) { return nil }
        for (index, match) in accumulator.matchesByID.enumerated() {
            guard acceptsRequest() else { return nil }
            accumulator.acceptFixture(match)
            processedRows += 1
            if (index + 1).isMultiple(of: 32), !(await suspend()) { return nil }
        }
        if !accumulator.matchesByID.count.isMultiple(of: 32), !(await suspend()) { return nil }
        guard acceptsRequest() else { return nil }
        return accumulator.merged
    }

    @MainActor
    private struct MatchDeduplicationAccumulator {
        private(set) var matchesByID: [EventReference] = []
        private var indicesByID: [String: Int] = [:]
        private var fixtureIndices: [String: Int] = [:]
        private(set) var merged: [EventReference] = []

        init(capacity: Int) {
            matchesByID.reserveCapacity(capacity)
            indicesByID.reserveCapacity(capacity)
        }

        mutating func acceptID(_ match: EventReference) {
            guard let index = indicesByID[match.id] else {
                indicesByID[match.id] = matchesByID.count
                matchesByID.append(match)
                return
            }
            let existing = matchesByID[index]
            guard !existing.hasCatalogIdentityConflict else { return }
            guard !match.hasCatalogIdentityConflict, existing.kickoffDate == match.kickoffDate,
                  CatalogPlaybackIdentity.matchingEvent(for: StreamPlaybackRequest(event: existing), in: [match]) != nil else {
                // One quarantined ID remains in the resolver snapshot, not two
                // Identifiable rows in UI and not a fabricated empty success.
                matchesByID[index] = EventReference(id: existing.id, title: existing.title,
                    category: existing.category, date: existing.date, poster: existing.poster,
                    popular: existing.popular, teams: existing.teams, sources: [],
                    hasCatalogIdentityConflict: true, cricketFixture: existing.cricketFixture,
                    sportsFixture: existing.sportsFixture, competitionID: existing.competitionID)
                return
            }
            var seenSources = Set<String>()
            let sources = ((existing.sources ?? []) + (match.sources ?? [])).filter {
                seenSources.insert("\($0.source)|\($0.id)").inserted
            }
            matchesByID[index] = EventReference(id: existing.id, title: existing.title,
                category: existing.category, date: existing.date, poster: existing.poster,
                popular: existing.popular, teams: existing.teams,
                sources: sources.isEmpty && existing.sources == nil && match.sources == nil ? nil : sources,
                cricketFixture: existing.cricketFixture ?? match.cricketFixture,
                sportsFixture: existing.sportsFixture ?? match.sportsFixture,
                competitionID: existing.competitionID ?? match.competitionID)
        }

        // Different provider families sometimes assign different event IDs to
        // the same fixture. Collapse them only when sport, exact kickoff and
        // both reviewed whole-team identities agree. This preserves genuine
        // doubleheaders and keeps youth/reserve fixtures distinct.
        mutating func acceptFixture(_ event: EventReference) {
            guard !event.hasCatalogIdentityConflict,
                  let fixtureKey = AnalyticalDataEngine.duplicateFixtureKey(for: event) else {
                merged.append(event)
                return
            }
            guard let index = fixtureIndices[fixtureKey] else {
                fixtureIndices[fixtureKey] = merged.count
                merged.append(event)
                return
            }

            let existing = merged[index]
            if let previous = existing.sportsFixture, let current = event.sportsFixture,
               previous.fixtureID != current.fixtureID {
                // Two official IDs at the same instant are an ambiguity, not
                // permission to combine doubleheaders or overwrite a receipt.
                merged.append(event)
                return
            }
            let preferred: EventReference
            let secondary: EventReference
            if (existing.sources?.isEmpty ?? true), !(event.sources?.isEmpty ?? true) {
                preferred = event
                secondary = existing
            } else {
                preferred = existing
                secondary = event
            }
            var seenSources = Set<String>()
            let sources = ((preferred.sources ?? []) + (secondary.sources ?? [])).filter {
                seenSources.insert("\($0.source)|\($0.id)").inserted
            }
            merged[index] = EventReference(
                id: preferred.id,
                title: preferred.title ?? secondary.title,
                category: preferred.category ?? secondary.category,
                date: preferred.date ?? secondary.date,
                poster: preferred.poster ?? secondary.poster,
                popular: preferred.popular ?? secondary.popular,
                teams: preferred.teams ?? secondary.teams,
                sources: sources,
                cricketFixture: preferred.cricketFixture ?? secondary.cricketFixture,
                sportsFixture: preferred.sportsFixture ?? secondary.sportsFixture,
                competitionID: preferred.competitionID ?? secondary.competitionID
            )
        }
    }

    private static func duplicateFixtureKey(for event: EventReference) -> String? {
        guard !event.isBroadcastChannel,
              let kickoff = event.kickoffDate,
              event.homeName != "Home", event.awayName != "Away",
              !event.homeName.isEmpty, !event.awayName.isEmpty else { return nil }
        let category = event.normalizedCategory
        func teamKey(_ name: String) -> String {
            if category == "football", let club = FootballCompetitionCatalog.canonicalClubID(for: name) {
                return "football:\(club)"
            }
            if let known = SportsTeamIdentity.known(name: name, category: category) {
                return "known:\(known.id)"
            }
            return "raw:\(SportsTeamIdentity.normalized(name))"
        }
        let competition = event.competitionID ?? ""
        let squad = category == "football" ? CatalogPlaybackIdentity.footballSquadIdentity(for: event).sorted().joined(separator: ",") : ""
        return "\(category)|\(competition)|\(Int64(kickoff.timeIntervalSince1970))|\(teamKey(event.homeName))|\(teamKey(event.awayName))|\(squad)"
    }

    static func normalizedCategoryKey(_ rawCategory: String?) -> String {
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
        case "nfl", "american football":
            return "american-football"
        case "atp", "wta":
            return "tennis"
        case "motor-sports", "motorsports", "f1", "formula 1":
            return "motorsport"
        case "pga":
            return "golf"
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

    static func imageURL(from raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }

        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }

        if raw.hasPrefix("/api/") {
            let s = StringObfuscator.decode([0x2E, 0x1B, 0x0, 0x4, 0xA, 0x7B, 0x41, 0x4E, 0x1F, 0x1A, 0x6, 0x8, 0x13, 0x16, 0x24, 0x1C, 0x36, 0x6, 0xC, 0x11, 0x15, 0x6C, 0x7, 0xF, 0x1A, 0x16, 0x1D, 0xA, 0x6, 0x5D, 0x35, 0x5D, 0x2B]) // "https://streamed.pk"
            let sx = StringObfuscator.decode([0x2E, 0x1B, 0x0, 0x4, 0xA, 0x7B, 0x41, 0x4E, 0x1B, 0xE, 0x3, 0x47, 0x10, 0x7, 0x24, 0x57, 0x27, 0x2, 0x11, 0xC, 0x57, 0x2F, 0xB, 0x15]) // "https://www.nx.net"
            return URL(string: s + raw) ?? URL(string: sx + raw)
        }

        // Most badge values are opaque provider tokens. They are not paths and
        // must be sent through the provider's badge-image endpoint.
        let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? raw
        let badgeBase = StringObfuscator.decode([0x2E, 0x1B, 0x0, 0x4, 0xA, 0x7B, 0x41, 0x4E, 0x1F, 0xD, 0x6, 0xC, 0x2, 0x1E, 0x33, 0x56, 0x68, 0x1F, 0x1F, 0x5B, 0x18, 0x31, 0x7, 0x4E, 0x5, 0x14, 0x15, 0xE, 0x6, 0x0, 0x79, 0x50, 0x27, 0xB, 0x13, 0x11, 0x56])
        return URL(string: badgeBase + "\(encoded).webp")
    }

    private static func isP2PCandidate(_ candidate: StreamCandidate) -> Bool {
        let url = candidate.embedURL.lowercased()
        return url.contains("acestream://") || url.contains("/proxy/acestream/")
    }

}
