import Foundation

struct FPLDiskSnapshotEnvelope: Codable, Sendable {
    static let currentVersion = 3

    let version: Int
    let endpoint: String
    let savedAt: Date
    let season: String
    let catalogFingerprint: String?
    let payload: Data
}

enum FPLDiskSnapshotPolicy {
    static func maximumAge(for endpoint: String) -> TimeInterval {
        if endpoint.contains("/live/") { return 5 * 60 }
        if endpoint == "fixtures/" { return 6 * 60 * 60 }
        if endpoint == "bootstrap-static/" { return 24 * 60 * 60 }
        if endpoint.contains("element-summary/") { return 72 * 60 * 60 }
        if endpoint.contains("/picks/") || endpoint.contains("leagues-classic/") ||
            endpoint.contains("/history/") || endpoint.hasPrefix("entry/") {
            return 24 * 60 * 60
        }
        return 24 * 60 * 60
    }

    static func isUsable(
        _ envelope: FPLDiskSnapshotEnvelope,
        endpoint: String,
        expectedSeason: String,
        expectedCatalogFingerprint: String?,
        now: Date = Date()
    ) -> Bool {
        guard envelope.version == FPLDiskSnapshotEnvelope.currentVersion,
              envelope.endpoint == endpoint,
              envelope.season == expectedSeason else { return false }
        let age = now.timeIntervalSince(envelope.savedAt)
        guard age >= 0, age <= maximumAge(for: endpoint) else { return false }
        if let expectedCatalogFingerprint {
            guard envelope.catalogFingerprint == expectedCatalogFingerprint else { return false }
        }
        return true
    }
}

public actor FPLService {
    public static let shared = FPLService()

    private let baseURL = "https://fantasy.premierleague.com/api"
    private let session: URLSession
    private var cache: [String: (data: Data, timestamp: Date, season: String)] = [:]
    private let fileManager = FileManager.default
    private var activeSeasonLabel = FPLSeasonIdentifier.currentLabel()
    private var activeCatalogFingerprint: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadRevalidatingCacheData
        self.session = URLSession(configuration: config)
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? FileManager.default.removeItem(
                at: caches.appendingPathComponent("fpl_snapshots_v2", isDirectory: true)
            )
        }
    }

    private var snapshotDirectoryURL: URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("fpl_snapshots_v3", isDirectory: true)
    }

    private func snapshotURL(for key: String) -> URL? {
        guard let directory = snapshotDirectoryURL else { return nil }
        let safeName = key.map { character -> Character in
            character.isLetter || character.isNumber ? character : "_"
        }
        return directory.appendingPathComponent(String(safeName) + ".json")
    }

    private func bootstrapFingerprint(_ bootstrap: FPLBootstrapResponse) -> String {
        bootstrap.teams.sorted { $0.id < $1.id }
            .map { "\($0.id):\($0.name):\($0.shortName)" }
            .joined(separator: "|")
    }

    private func updateSeasonContext<T>(from value: T) {
        guard let bootstrap = value as? FPLBootstrapResponse else { return }
        let season = FPLSeasonIdentifier.label(from: bootstrap.events)
        let fingerprint = bootstrapFingerprint(bootstrap)
        if activeSeasonLabel != season || activeCatalogFingerprint != fingerprint {
            cache.removeAll()
        }
        activeSeasonLabel = season
        activeCatalogFingerprint = fingerprint
    }

    private func validateSeason<T>(of value: T, expectedSeason: String) throws {
        guard let bootstrap = value as? FPLBootstrapResponse else { return }
        guard FPLSeasonIdentifier.label(from: bootstrap.events) == expectedSeason else {
            throw URLError(.cannotParseResponse)
        }
    }

    private func saveDiskSnapshot(key: String, endpoint: String, data: Data, savedAt: Date) {
        guard let directory = snapshotDirectoryURL,
              let fileURL = snapshotURL(for: key) else { return }
        let envelope = FPLDiskSnapshotEnvelope(
            version: FPLDiskSnapshotEnvelope.currentVersion,
            endpoint: endpoint,
            savedAt: savedAt,
            season: activeSeasonLabel,
            catalogFingerprint: activeCatalogFingerprint,
            payload: data
        )
        guard let encoded = try? JSONEncoder().encode(envelope) else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? encoded.write(to: fileURL, options: .atomic)
        pruneDiskSnapshots(in: directory, now: savedAt)
    }

    private func pruneDiskSnapshots(in directory: URL, now: Date) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let ranked = files.compactMap { url -> (URL, Date)? in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return (url, values?.contentModificationDate ?? .distantPast)
        }.sorted { $0.1 > $1.1 }
        for (index, item) in ranked.enumerated()
        where index >= 96 || now.timeIntervalSince(item.1) > 90 * 24 * 60 * 60 {
            try? fileManager.removeItem(at: item.0)
        }
    }

    private func loadDiskSnapshot<T: Decodable & Sendable>(
        key: String,
        endpoint: String,
        now: Date = Date()
    ) -> FPLResource<T>? {
        guard let fileURL = snapshotURL(for: key),
              let data = try? Data(contentsOf: fileURL),
              let envelope = try? JSONDecoder().decode(FPLDiskSnapshotEnvelope.self, from: data),
              FPLDiskSnapshotPolicy.isUsable(
                envelope,
                endpoint: endpoint,
                expectedSeason: activeSeasonLabel,
                expectedCatalogFingerprint: activeCatalogFingerprint,
                now: now
              ),
              let value = try? JSONDecoder().decode(T.self, from: envelope.payload) else {
            return nil
        }
        if let bootstrap = value as? FPLBootstrapResponse,
           FPLSeasonIdentifier.label(from: bootstrap.events) != envelope.season {
            return nil
        }
        updateSeasonContext(from: value)
        return FPLResource(
            value: value,
            metadata: FPLResourceMetadata(
                source: .diskSnapshot,
                fetchedAt: envelope.savedAt,
                endpoint: endpoint
            )
        )
    }

    private func fetchResource<T: Decodable & Sendable>(_ path: String) async throws -> FPLResource<T> {
        let now = Date()
        let calendarSeason = FPLSeasonIdentifier.currentLabel(at: now)
        if activeSeasonLabel != calendarSeason {
            activeSeasonLabel = calendarSeason
            activeCatalogFingerprint = nil
            cache.removeAll()
        }

        if let entry = cache[path], entry.season == activeSeasonLabel,
           now.timeIntervalSince(entry.timestamp) < cacheTTL(for: path) {
            let value = try JSONDecoder().decode(T.self, from: entry.data)
            try validateSeason(of: value, expectedSeason: calendarSeason)
            updateSeasonContext(from: value)
            return FPLResource(
                value: value,
                metadata: FPLResourceMetadata(source: .memoryCache, fetchedAt: entry.timestamp, endpoint: path)
            )
        }

        guard let url = URL(string: "\(baseURL)/\(path)") else {
            if let snapshot: FPLResource<T> = loadDiskSnapshot(key: path, endpoint: path, now: now) {
                return snapshot
            }
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                if let snapshot: FPLResource<T> = loadDiskSnapshot(key: path, endpoint: path, now: now) {
                    return snapshot
                }
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode(T.self, from: data)
            try validateSeason(of: decoded, expectedSeason: calendarSeason)
            updateSeasonContext(from: decoded)
            let fetchedAt = Date()
            cache[path] = (data, fetchedAt, activeSeasonLabel)
            saveDiskSnapshot(key: path, endpoint: path, data: data, savedAt: fetchedAt)
            return FPLResource(
                value: decoded,
                metadata: FPLResourceMetadata(source: .network, fetchedAt: fetchedAt, endpoint: path)
            )
        } catch {
            if let snapshot: FPLResource<T> = loadDiskSnapshot(key: path, endpoint: path, now: now) {
                return snapshot
            }
            throw error
        }
    }

    private func cacheTTL(for path: String) -> TimeInterval {
        if path.contains("/live/") { return 30 }
        if path == "fixtures/" { return 45 }
        if path.contains("/picks/") || path.contains("leagues-classic/") { return 60 }
        return 300
    }

    public func clearCache() { cache.removeAll() }

    public func fetchBootstrapResource() async throws -> FPLResource<FPLBootstrapResponse> { try await fetchResource("bootstrap-static/") }
    public func fetchFixturesResource() async throws -> FPLResource<[FPLFixture]> { try await fetchResource("fixtures/") }
    public func fetchManagerSummaryResource(id: Int) async throws -> FPLResource<FPLManagerSummary> { try await fetchResource("entry/\(id)/") }
    public func fetchPicksResource(managerId: Int, gameweek: Int) async throws -> FPLResource<FPLManagerPicks> { try await fetchResource("entry/\(managerId)/event/\(gameweek)/picks/") }
    public func fetchManagerHistoryResource(id: Int) async throws -> FPLResource<FPLManagerHistoryResponse> { try await fetchResource("entry/\(id)/history/") }
    public func fetchEventLiveResource(gameweek: Int) async throws -> FPLResource<FPLEventLiveResponse> { try await fetchResource("event/\(gameweek)/live/") }
    public func fetchElementSummaryResource(playerId: Int) async throws -> FPLResource<FPLElementSummaryResponse> { try await fetchResource("element-summary/\(playerId)/") }
    public func fetchLeagueStandingsResource(leagueId: Int, page: Int = 1) async throws -> FPLResource<FPLLeagueStandingsResponse> {
        try await fetchResource("leagues-classic/\(leagueId)/standings/?page_standings=\(max(1, page))")
    }

    public func fetchBootstrap() async throws -> FPLBootstrapResponse { try await fetchBootstrapResource().value }
    public func fetchFixtures() async throws -> [FPLFixture] { try await fetchFixturesResource().value }
    public func fetchManagerSummary(id: Int) async throws -> FPLManagerSummary { try await fetchManagerSummaryResource(id: id).value }
    public func fetchPicks(managerId: Int, gameweek: Int) async throws -> FPLManagerPicks { try await fetchPicksResource(managerId: managerId, gameweek: gameweek).value }
    public func fetchManagerHistory(id: Int) async throws -> FPLManagerHistoryResponse { try await fetchManagerHistoryResource(id: id).value }
    public func fetchEventLive(gameweek: Int) async throws -> FPLEventLiveResponse { try await fetchEventLiveResource(gameweek: gameweek).value }
    public func fetchElementSummary(playerId: Int) async throws -> FPLElementSummaryResponse { try await fetchElementSummaryResource(playerId: playerId).value }
    public func fetchLeagueStandings(leagueId: Int, page: Int = 1) async throws -> FPLLeagueStandingsResponse { try await fetchLeagueStandingsResource(leagueId: leagueId, page: page).value }
}
