import Foundation

enum AppRuntime {
    /// Physical-device playback checks need production refresh/resolution while
    /// still suppressing provider audio during the automated run.
    static var isPhysicalLiveTesting: Bool {
        ProcessInfo.processInfo.environment["FOTTY_PHYSICAL_LIVE_TEST"] == "1"
    }

    /// Keeps hosted unit/UI tests deterministic and prevents them from exercising
    /// production feeds merely because XCTest launches the application target.
    static var isAutomatedTesting: Bool {
        if isPhysicalLiveTesting { return false }
        let environment = ProcessInfo.processInfo.environment
        return environment["FOTTY_AUTOMATED_TESTING"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
            || NSClassFromString("XCTest.XCTestCase") != nil
    }

    static var shouldMutePlaybackForTesting: Bool {
        isAutomatedTesting || isPhysicalLiveTesting
    }
}

// MARK: - API Configuration

enum Config {
    static let pocketBaseBaseURLString = "https://fotty-api.pixel-invoice.com"
    /// Fotty Web (PWA + account APIs such as delete-account).
    static let webAppURLString = "https://fotty.pixel-invoice.com"
    /// Public edge boundary; provider credentials remain Worker secrets.
    private static let defaultEdgeAPIBaseURLString = "https://fotty-playback-v3.adaptive-rhubarb.workers.dev"

    private static func configuredValue(_ key: String) -> String {
        let environmentValue = ProcessInfo.processInfo.environment[key]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentValue, !environmentValue.isEmpty {
            return environmentValue
        }

        let bundleValue = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bundleValue,
              !bundleValue.isEmpty,
              !bundleValue.hasPrefix("$(") else {
            return ""
        }
        return bundleValue
    }

    static var footballAPIKey: String {
        configuredValue("FOOTBALL_DATA_API_KEY")
    }
    
    // Football Pro (RapidAPI - Sportmonks v3)
    static var rapidAPIKey: String {
        configuredValue("RAPID_API_KEY")
    }
    static let footballProHost = "football-pro.p.rapidapi.com"
    
    // API-Football — Free tier: 100 req/day, all leagues
    static var apiFootballKey: String {
        configuredValue("API_FOOTBALL_KEY")
    }
    static let apiFootballHost = "v3.football.api-sports.io"

    /// TheSportsDB — v1 uses key in URL path; v2 premium uses `X-API-KEY` header. Override with `FOTTY_THESPORTSDB_API_KEY`.
    static var theSportsDBAPIKey: String {
        let raw = ProcessInfo.processInfo.environment["FOTTY_THESPORTSDB_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty { return raw }
        return "3"
    }

    static var theSportsDBPrefersV2: Bool {
        theSportsDBAPIKey != "3" && theSportsDBAPIKey != "123"
    }

    // Submission metadata
    static let legalBaseURLString = "https://getfotty.com"
    static let privacyPolicyPath = "/privacy"
    static let termsOfUsePath = "/terms"
    
    static var privacyPolicyURL: URL? {
        buildLegalURL(path: privacyPolicyPath)
    }
    
    static var termsOfUseURL: URL? {
        buildLegalURL(path: termsOfUsePath)
    }

    /// Reviewed schedule data from the existing edge boundary. This can update
    /// independently from iOS; the app validates it completely before caching.
    static var cplScheduleManifestURL: URL? {
        footballProxyBaseURL?.appendingPathComponent("api/cricket/cpl-fixtures")
    }
    
    private static func buildLegalURL(path: String) -> URL? {
        guard let base = URL(string: legalBaseURLString) else { return nil }
        return base.appendingPathComponent(path)
    }
    
    static var pocketBaseBaseURL: URL? {
        normalizedHTTPURL(from: pocketBaseBaseURLString)
    }

    /// Edge base used for server-side football-data.org proxying.
    /// Override with `FOTTY_FOOTBALL_PROXY_BASE` for a self-hosted deployment.
    static var footballProxyBaseURLString: String {
        let raw = ProcessInfo.processInfo.environment["FOTTY_FOOTBALL_PROXY_BASE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty { return raw }
        return defaultEdgeAPIBaseURLString
    }

    static var footballProxyBaseURL: URL? {
        normalizedHTTPURL(from: footballProxyBaseURLString)
    }

    /// Secure Cloudflare Worker boundary for FPL reasoning. The DeepSeek key is
    /// stored as a Worker secret and is never bundled with the iOS application.
    static var fplCoachProxyBaseURLString: String {
        let raw = configuredValue("FOTTY_FPL_COACH_PROXY_BASE")
        return raw.isEmpty
            ? defaultEdgeAPIBaseURLString
            : raw
    }

    static var fplCoachProxyBaseURL: URL? {
        normalizedHTTPSURL(from: fplCoachProxyBaseURLString)
    }

    /// When true (default), football-data.org schedule/WC calls prefer `/api/football/matches` on the web host.
    static var prefersFootballDataProxy: Bool {
        let raw = ProcessInfo.processInfo.environment["FOTTY_FOOTBALL_PROXY_ENABLED"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let raw, !raw.isEmpty {
            return !(raw == "0" || raw == "false" || raw == "no" || raw == "off")
        }
        return true
    }

    enum P2P {
        private static func environmentValue(_ key: String) -> String? {
            let raw = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty == false) ? raw : nil
        }

        static var serverBaseURLString: String {
            environmentValue("FOTTY_P2P_SERVER_URL") ?? "https://p2p.pixel-invoice.com"
        }

        static var scraperBaseURLString: String {
            environmentValue("FOTTY_P2P_SCRAPER_URL") ?? "https://scraper.pixel-invoice.com"
        }

        static var serverBaseURL: URL? {
            normalizedHTTPURL(from: serverBaseURLString)
        }

        static var scraperBaseURL: URL? {
            normalizedHTTPURL(from: scraperBaseURLString)
        }

        /// Optional LAN/homelab mirror for `/matches` when upstream CDN is empty. Uses scraper host + `/matches`.
        static var homelabMatchesMirrorURL: URL? {
            guard let base = scraperBaseURL else { return nil }
            return base.appendingPathComponent("matches")
        }

        static var accessClientID: String? {
            environmentValue("FOTTY_P2P_CF_ACCESS_CLIENT_ID")
        }

        static var accessClientSecret: String? {
            environmentValue("FOTTY_P2P_CF_ACCESS_CLIENT_SECRET")
        }

        static var edgeHeaders: [String: String] {
            guard let clientID = accessClientID,
                  let clientSecret = accessClientSecret else {
                return [:]
            }
            return [
                "CF-Access-Client-Id": clientID,
                "CF-Access-Client-Secret": clientSecret
            ]
        }
    }

    /// Extra API-Football league fixtures merged into `FootballRepository.getPremiumFixtures` (e.g. a major tournament).
    /// **Nothing is hardcoded** — enable per scheme, CI, or device run with environment variables only; remove the vars later to drop the feed.
    ///
    /// - `FOTTY_FOOTBALL_SPOTLIGHT_LEAGUES` — comma-separated `leagueId` or `leagueId:season` (API-Football query params).
    /// - `FOTTY_FOOTBALL_SPOTLIGHT_SECTION_TITLE` — optional display string if you add UI; unused by default.
    enum FootballSpotlight {
        static let leaguesEnvironmentKey = "FOTTY_FOOTBALL_SPOTLIGHT_LEAGUES"
        static let sectionTitleEnvironmentKey = "FOTTY_FOOTBALL_SPOTLIGHT_SECTION_TITLE"

        struct LeagueQuery: Sendable, Hashable {
            let leagueId: String
            /// When `nil`, the repository uses the same rolling season string as PL/UCL for that refresh.
            let season: String?
        }

        /// Parsed spotlight leagues; empty when unset — **default app behavior is unchanged.**
        static var leagueQueries: [LeagueQuery] {
            guard let raw = ProcessInfo.processInfo.environment[leaguesEnvironmentKey] else { return [] }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return [] }

            var queries: [LeagueQuery] = []
            for part in trimmed.split(separator: ",") {
                let token = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if token.isEmpty { continue }
                let components = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
                if components.count == 2 {
                    let lid = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let season = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !lid.isEmpty, !season.isEmpty {
                        queries.append(LeagueQuery(leagueId: lid, season: season))
                    }
                } else if components.count == 1 {
                    let lid = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !lid.isEmpty {
                        queries.append(LeagueQuery(leagueId: lid, season: nil))
                    }
                }
            }
            return queries
        }

        static var hasConfiguredLeagues: Bool { !leagueQueries.isEmpty }

        /// Ops-defined label for optional UI; not a data source.
        static var sectionTitle: String? {
            guard let raw = ProcessInfo.processInfo.environment[sectionTitleEnvironmentKey] else { return nil }
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
    }

    /// **Match Arena** discovery is intentionally narrow: elite club football + major international tournaments.
    /// API-Football `league` ids: `39` Premier League, `2` UEFA Champions League, `140` La Liga,
    /// `4` UEFA European Championship, `9` Copa América (men’s).
    enum Arena {
        /// API-Football `league.id` values used in Match Hub / premium fixture pulls.
        static let discoveryLeagueIds: Set<String> = ["39", "2", "140", "4", "9"]

        /// football-data.org v4 competition ids (live fallback uses these, not API-Football ids).
        private static let footballDataDiscoveryIds: Set<Int> = [
            2021, // Premier League
            2001, // UEFA Champions League
            2014, // La Liga
            2018, // UEFA European Championship
            2152, // Copa América (men’s; fd catalog)
        ]

        private static let discoveryNameTokens: [String] = [
            "premier league",
            "champions league",
            "la liga",
            "laliga",
            "primera division",
            "european championship",
            "euro 20",
            "copa america",
            "copa américa",
        ]

        static func discoveryIncludes(competition: FottyCompetition) -> Bool {
            discoveryIncludes(
                competitionId: Int(competition.id),
                competitionName: competition.name,
                competitionCode: nil
            )
        }

        static func discoveryIncludes(
            competitionId: Int?,
            competitionName: String? = nil,
            competitionCode: String? = nil
        ) -> Bool {
            if let competitionId {
                if discoveryLeagueIds.contains(String(competitionId)) { return true }
                if footballDataDiscoveryIds.contains(competitionId) { return true }
            }
            let label = [competitionName, competitionCode]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .lowercased()
            guard !label.isEmpty else { return false }
            return discoveryNameTokens.contains(where: { label.contains($0) })
        }
    }
    
    // Image sizes
    enum ImageSize {
        static let thumbnailSmall = "/w342"
        static let thumbnailMedium = "/w500"
        static let thumbnailLarge = "/w780"
        static let hero = "/w1280"
        static let heroOriginal = "/original"
        static let profile = "/w185"
    }
    
    private static func normalizedHTTPSURL(from rawString: String) -> URL? {
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else { return nil }
        return url
    }
    
    private static func normalizedHTTPURL(from rawString: String) -> URL? {
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withoutTrailingSlash = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard let url = URL(string: withoutTrailingSlash) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }
}

enum AppCapabilities {
    static let externalAIInsightsEnvironmentKey = "FOTTY_INSIGHTS_EXTERNAL_AI_ENABLED"
    
    static var externalAIInsightsEnabled: Bool {
        if let envValue = ProcessInfo.processInfo.environment[externalAIInsightsEnvironmentKey],
           let parsed = parseBooleanString(envValue) {
            return parsed
        }
        return false
    }
    
    static var aiInsightsConsentRequired: Bool {
        externalAIInsightsEnabled
    }
    
    private static func parseBooleanString(_ rawValue: String) -> Bool? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        case "0", "false", "no", "n", "off":
            return false
        default:
            return nil
        }
    }
}
