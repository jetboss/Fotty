import Foundation

/// The fixture receipt contains schedule/status facts only. Stream descriptors
/// come exclusively from a current, independently matched provider catalog.
enum CricketFixtureCatalog {
    static let maximumPayloadBytes = 512 * 1024
    static let maximumFixtures = 500
    static let statusFreshness: TimeInterval = 30 * 60
    static let fixtureIDPrefix = "cricket-fixture:"

    enum SourceStatus: String, Codable, Sendable {
        case verified, partial, unavailable
        case lastKnownGood = "last-known-good"
        var verifiesCurrentRows: Bool { self == .verified || self == .partial }
    }

    enum Format: String, Codable, Sendable { case t20 = "T20", t10 = "T10", odi = "ODI", test = "Test", unknown }
    enum Status: String, Codable, Sendable {
        case scheduled, live, finished, postponed, cancelled, unknown
        var stopsPlayback: Bool { self == .finished || self == .cancelled || self == .postponed }
    }

    struct Team: Codable, Equatable, Sendable { let id: String; let name: String }
    struct Source: Codable, Equatable, Sendable {
        enum Verification: String, Codable, Sendable { case verified, held }
        let name: String
        let url: String
        let observedAt: String
        /// An additive, row-scoped admission receipt. Missing means the legacy
        /// cohort contract; it must never imply that unavailable rows are fresh.
        let verification: Verification?

        init(name: String, url: String, observedAt: String, verification: Verification? = nil) {
            self.name = name; self.url = url; self.observedAt = observedAt; self.verification = verification
        }

        private enum CodingKeys: String, CodingKey { case name, url, observedAt, verification }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = try values.decode(String.self, forKey: .name)
            url = try values.decode(String.self, forKey: .url)
            observedAt = try values.decode(String.self, forKey: .observedAt)
            // Only absence is the legacy contract. An explicit null/unknown
            // marker must not silently fall back to cohort verification.
            verification = values.contains(.verification) ? try values.decode(Verification.self, forKey: .verification) : nil
        }
    }
    struct Fixture: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let start: String
        let format: Format
        let status: Status
        let competitionId: String
        let competitionName: String
        let home: Team
        let away: Team
        let source: Source
        let context: CricketMatchContext?
        let matchOrdinal: Int?
        var kickoff: Date? { CricketFixtureCatalog.date(start) }

        init(id: String, start: String, format: Format, status: Status, competitionId: String,
             competitionName: String, home: Team, away: Team, source: Source, context: CricketMatchContext? = nil, matchOrdinal: Int? = nil) {
            self.id = id; self.start = start; self.format = format; self.status = status
            self.competitionId = competitionId; self.competitionName = competitionName
            self.home = home; self.away = away; self.source = source
            self.context = context?.validated(format: format, homeTeamID: home.id, awayTeamID: away.id)
            self.matchOrdinal = matchOrdinal.flatMap { [Format.odi, .t20].contains(format) && (1...99).contains($0) ? $0 : nil }
        }

        private enum CodingKeys: String, CodingKey {
            case id, start, format, status, competitionId, competitionName, home, away, source, context, matchOrdinal
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            start = try values.decode(String.self, forKey: .start)
            format = try values.decode(Format.self, forKey: .format)
            status = try values.decode(Status.self, forKey: .status)
            competitionId = try values.decode(String.self, forKey: .competitionId)
            competitionName = try values.decode(String.self, forKey: .competitionName)
            home = try values.decode(Team.self, forKey: .home)
            away = try values.decode(Team.self, forKey: .away)
            source = try values.decode(Source.self, forKey: .source)
            // Malformed optional score context cannot erase an accepted fixture
            // or promote a retained schedule/status receipt to a newer one.
            let candidate = try? values.decode(CricketMatchContext.self, forKey: .context)
            context = candidate?.validated(format: format, homeTeamID: home.id, awayTeamID: away.id)
            let acceptsOrdinal = format == .odi || format == .t20
            matchOrdinal = (try? values.decode(Int.self, forKey: .matchOrdinal)).flatMap { acceptsOrdinal && (1...99).contains($0) ? $0 : nil }
        }
    }
    struct Coverage: Codable, Equatable, Sendable {
        enum Status: String, Codable, Sendable { case covered, offseason, unavailable }
        let competitionId: String
        let competitionName: String
        let status: Status
        let checkedAt: String
        let fixtureCount: Int
        let expectedFixtureCount: Int?
        let nextStart: String?
    }
    struct Snapshot: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let complete: Bool
        let checkedAt: String
        let revision: String
        let sourceStatus: SourceStatus
        let fixtures: [Fixture]
        let coverage: [Coverage]
        var receiptDate: Date? { CricketFixtureCatalog.date(checkedAt) }
    }
    enum ValidationError: Error { case header, receipt, fixture, coverage, size }

    static func date(_ value: String) -> Date? {
        // The offset is mandatory: a device's local zone never supplies UTC.
        guard value.range(of: #"(?:Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else { return nil }
        return CatalogISO8601DateParser.date(value)
    }

    static func validatedSnapshot(from data: Data, now: Date = .init(), reconciledCache: Bool = false) throws -> Snapshot {
        guard data.count <= maximumPayloadBytes else { throw ValidationError.size }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        guard snapshot.schemaVersion == 1, snapshot.complete,
              validText(snapshot.revision, maximum: 160), snapshot.fixtures.count <= maximumFixtures,
              !snapshot.coverage.isEmpty, snapshot.coverage.count <= 64 else { throw ValidationError.header }
        guard let receipt = snapshot.receiptDate,
              receipt <= now.addingTimeInterval(300), receipt >= now.addingTimeInterval(-30 * 86400) else {
            throw ValidationError.receipt
        }
        var competitions = Set<String>()
        for item in snapshot.coverage {
            guard validText(item.competitionId, maximum: 100), validText(item.competitionName, maximum: 200),
                  competitions.insert(item.competitionId).inserted, (0...maximumFixtures).contains(item.fixtureCount),
                  let observed = date(item.checkedAt), observed <= receipt.addingTimeInterval(300),
                  (item.status == .unavailable || observed >= now.addingTimeInterval(-30 * 86400)),
                  item.expectedFixtureCount.map({ (0...maximumFixtures).contains($0) }) ?? true,
                  item.nextStart.map({ date($0) != nil }) ?? true else { throw ValidationError.coverage }
        }
        var ids = Set<String>()
        var identities = Set<String>()
        for fixture in snapshot.fixtures {
            guard validText(fixture.id, maximum: 120), ids.insert(fixture.id).inserted,
                  validText(fixture.competitionName, maximum: 200), competitions.contains(fixture.competitionId),
                  validText(fixture.home.id, maximum: 100), validText(fixture.away.id, maximum: 100),
                  fixture.home.id != fixture.away.id,
                  validTeamName(fixture.home.name), validTeamName(fixture.away.name),
                  teamKey(fixture.home.name) != teamKey(fixture.away.name),
                  let start = fixture.kickoff,
                  start >= now.addingTimeInterval(-(fixture.competitionId == "cpl" ? 366 : 30) * 86400),
                  start <= now.addingTimeInterval(90 * 86400), validText(fixture.source.name, maximum: 100),
                  let url = URL(string: fixture.source.url), url.scheme == "https", url.host != nil,
                  url.user == nil, url.password == nil,
                  let observed = date(fixture.source.observedAt), observed <= receipt.addingTimeInterval(300),
                  observed >= now.addingTimeInterval(-(fixture.competitionId == "cpl" ? 366 : 30) * 86400),
                  identities.insert("\(fixture.competitionId)|\(start.timeIntervalSince1970)|\(fixture.home.id)|\(fixture.away.id)").inserted
            else { throw ValidationError.fixture }
            if fixture.source.verification != nil {
                guard ["west-indies", "icc"].contains(fixture.competitionId),
                      fixture.source.verification != .held
                        || snapshot.coverage.first(where: { $0.competitionId == fixture.competitionId })?.status == .unavailable
                else { throw ValidationError.fixture }
            }
        }
        // A complete successful competition cannot silently lose one row in
        // transport. Retained rows in a locally reconciled cache are exempt only
        // for explicitly unavailable competitions.
        for item in snapshot.coverage {
            if reconciledCache && item.status == .unavailable { continue }
            let count = snapshot.fixtures.filter { $0.competitionId == item.competitionId }.count
            guard count == item.fixtureCount,
                  item.status != .offseason || count == 0,
                  item.expectedFixtureCount.map({ item.status != .covered || $0 == count }) ?? true else {
                throw ValidationError.coverage
            }
        }
        return snapshot
    }

    /// A partially successful response only replaces competitions that were
    /// checked completely; unavailable competitions keep their original receipt.
    static func accepting(_ candidate: Snapshot, over cached: Snapshot?) -> Snapshot {
        guard let cached else { return candidate }
        guard candidate.sourceStatus != .unavailable,
              candidate.sourceStatus != .lastKnownGood,
              (candidate.receiptDate ?? .distantPast) >= (cached.receiptDate ?? .distantPast) else { return cached }
        for coverage in candidate.coverage where coverage.status != .unavailable {
            // Empty/pending-only cohorts have no row to enforce monotonicity.
            // An unrelated fresh cohort must not bless an older replacement.
            let cachedReceipt = cached.coverage.first { $0.competitionId == coverage.competitionId }
                .flatMap { date($0.checkedAt) } ?? .distantPast
            let newestRow = cached.fixtures.filter { $0.competitionId == coverage.competitionId }
                .compactMap { date($0.source.observedAt) }.max() ?? .distantPast
            guard (date(coverage.checkedAt) ?? .distantPast) >= max(cachedReceipt, newestRow) else { return cached }
        }
        let oldByID = Dictionary(uniqueKeysWithValues: cached.fixtures.map { ($0.id, $0) })
        for fixture in candidate.fixtures {
            guard let old = oldByID[fixture.id] else { continue }
            // Stable fixture identity cannot be reused for a different squad.
            // Terminal facts also cannot silently regress into a live match.
            if old.competitionId != fixture.competitionId || old.home.id != fixture.home.id || old.away.id != fixture.away.id
                || ([Status.finished, .cancelled].contains(old.status) && [Status.scheduled, .live].contains(fixture.status))
                || (date(fixture.source.observedAt) ?? .distantPast) < (date(old.source.observedAt) ?? .distantPast) {
                return cached
            }
        }
        let checked = Set(candidate.coverage.filter { $0.status != .unavailable }.map(\.competitionId))
        let unavailable = cached.fixtures.filter { !checked.contains($0.competitionId) }
        let ids = Set(candidate.fixtures.map(\.id))
        let fixtures = candidate.fixtures + unavailable.filter { !ids.contains($0.id) }.map { fixture in
            guard fixture.source.verification != nil else { return fixture }
            // Cache-only rows were not admitted by this response. Preserve
            // their facts/receipt, but never retain an explicit verified flag.
            return Fixture(id: fixture.id, start: fixture.start, format: fixture.format, status: fixture.status,
                competitionId: fixture.competitionId, competitionName: fixture.competitionName,
                home: fixture.home, away: fixture.away,
                source: Source(name: fixture.source.name, url: fixture.source.url,
                               observedAt: fixture.source.observedAt, verification: .held), context: fixture.context, matchOrdinal: fixture.matchOrdinal)
        }
        var coverage = candidate.coverage.map { item in
            guard item.status == .unavailable,
                  let prior = cached.coverage.first(where: { $0.competitionId == item.competitionId }),
                  (date(prior.checkedAt) ?? .distantPast) > (date(item.checkedAt) ?? .distantPast) else { return item }
            // Retain the last admitted watermark even when the newest envelope
            // reports an older unavailable receipt and the cache has no rows.
            return Coverage(competitionId: item.competitionId, competitionName: item.competitionName,
                status: .unavailable, checkedAt: prior.checkedAt, fixtureCount: item.fixtureCount,
                expectedFixtureCount: item.expectedFixtureCount, nextStart: item.nextStart)
        }
        let coverageIDs = Set(coverage.map(\.competitionId))
        coverage += cached.coverage.filter { !coverageIDs.contains($0.competitionId) }.map {
            Coverage(competitionId: $0.competitionId, competitionName: $0.competitionName, status: .unavailable,
                     checkedAt: $0.checkedAt, fixtureCount: 0, expectedFixtureCount: nil, nextStart: $0.nextStart)
        }
        return Snapshot(schemaVersion: 1, complete: true, checkedAt: candidate.checkedAt, revision: candidate.revision,
                        sourceStatus: candidate.sourceStatus, fixtures: fixtures, coverage: coverage)
    }

    static func pollingInterval(snapshot: Snapshot?, now: Date) -> TimeInterval {
        guard let snapshot else { return 5 * 60 }
        if !snapshot.sourceStatus.verifiesCurrentRows || snapshot.coverage.contains(where: { $0.status == .unavailable }) {
            return 5 * 60
        }
        for fixture in snapshot.fixtures where !fixture.status.stopsPlayback {
            guard let start = fixture.kickoff else { continue }
            let sinceStart = now.timeIntervalSince(start)
            // These are polling windows, never inferred live/final statuses.
            let window: TimeInterval
            switch fixture.format { case .t20: window = 8 * 3600; case .t10: window = 4 * 3600; case .odi: window = 12 * 3600
            case .test: window = 6 * 86400; case .unknown: window = 24 * 3600 }
            if fixture.status == .live || (-1800...window).contains(sinceStart) { return 5 * 60 }
            if sinceStart >= -24 * 3600, sinceStart < 0 { return 15 * 60 }
        }
        return 4 * 3600
    }

    static func teamKey(_ name: String) -> String {
        let normalized = name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                               locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "&", with: " and ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        let key = normalized.replacingOccurrences(of: #"\b(?:under|u)\s*(\d{1,2})\b"#, with: "u$1", options: .regularExpression)
            .replacingOccurrences(of: #"\b(?:womens|ladies)\b"#, with: "women", options: .regularExpression)
        if key.hasSuffix(" women") { return teamKey(String(key.dropLast(6))) + " women" }
        if let qualifier = key.range(of: #" u\d{1,2}$"#, options: .regularExpression) {
            return teamKey(String(key[..<qualifier.lowerBound])) + String(key[qualifier])
        }
        // Exact international aliases only. Women's/youth qualifiers remain
        // intact, and a partial word can never map a team.
        switch key {
        case "ind": return "india"
        case "wi", "windies": return "west indies"
        case "nz", "nzl": return "new zealand"
        case "sl", "sri": return "sri lanka"
        case "sa", "rsa": return "south africa"
        case "aus": return "australia"
        case "eng": return "england"
        case "pak": return "pakistan"
        case "ban", "bang": return "bangladesh"
        case "afg": return "afghanistan"
        default: return key
        }
    }

    private static func validText(_ text: String, maximum: Int) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= maximum
            && !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
    private static func validTeamName(_ text: String) -> Bool {
        validText(text, maximum: 100) && !["home", "away", "tbd", "tbc", "unknown", "teams to be confirmed"].contains(teamKey(text))
    }

    @MainActor
    static func upcomingSearchEvents(from snapshot: Snapshot?, at now: Date) -> [EventReference] {
        guard let snapshot, snapshot.sourceStatus.verifiesCurrentRows,
              SportsSearchSchedule.isFresh(snapshot.receiptDate, at: now) else { return [] }
        let latest = now.addingTimeInterval(SportsSearchSchedule.futureHorizon)
        return snapshot.fixtures.compactMap { fixture in
            // CPL retains its separately reviewed season receipt.
            guard fixture.competitionId.lowercased() != "cpl",
                  !fixture.competitionId.lowercased().hasPrefix("cpl-"),
                  fixture.status == .scheduled, let kickoff = fixture.kickoff,
                  kickoff > now, kickoff <= latest,
                  let coverage = snapshot.coverage.first(where: { $0.competitionId == fixture.competitionId }),
                  coverage.status == .covered,
                  SportsSearchSchedule.isFresh(date(coverage.checkedAt), at: now) else { return nil }
            let metadata = fixtureMetadata(for: fixture, in: snapshot)
            guard metadata.verified, SportsSearchSchedule.isFresh(metadata.observedAt, at: now) else { return nil }
            return projectedEvent(for: fixture, metadata: metadata, kickoff: kickoff)
        }
    }

    @MainActor
    static func terminalEvents(from snapshot: Snapshot?) -> [EventReference] {
        guard let snapshot, snapshot.sourceStatus.verifiesCurrentRows else { return [] }
        return snapshot.fixtures.compactMap { fixture in
            // CPL keeps its independent schedule/status authority.
            guard fixture.competitionId.lowercased() != "cpl", !fixture.competitionId.lowercased().hasPrefix("cpl-"),
                  fixture.status == .finished || fixture.status == .cancelled, let start = fixture.kickoff else { return nil }
            let metadata = fixtureMetadata(for: fixture, in: snapshot)
            guard metadata.verified else { return nil }
            return projectedEvent(for: fixture, metadata: metadata, kickoff: start)
        }
    }

    @MainActor
    /// Home rows plus the schedule's current fixtures. Earlier projections of
    /// this schedule are replaced; CPL keeps its own schedule and other rows
    /// pass through.
    static func merging(into catalog: [EventReference], snapshot: Snapshot?, at now: Date = .init()) -> [EventReference] {
        let remaining = catalog.filter { !$0.id.hasPrefix(fixtureIDPrefix) }
        guard let snapshot else { return remaining }
        let projected = snapshot.fixtures.compactMap { fixture -> EventReference? in
            guard fixture.competitionId.lowercased() != "cpl", !fixture.competitionId.lowercased().hasPrefix("cpl-"),
                  let start = fixture.kickoff, fixture.status != .finished, fixture.status != .cancelled,
                  start <= now.addingTimeInterval(CatalogTimingPolicy.retentionFutureHorizon),
                  start >= now.addingTimeInterval(-14 * 86400) else { return nil }
            return projectedEvent(for: fixture, metadata: fixtureMetadata(for: fixture, in: snapshot), kickoff: start)
        }
        return remaining + projected
    }

    private static func fixtureMetadata(for fixture: Fixture, in snapshot: Snapshot) -> CricketFixtureMetadata {
        let covered = snapshot.coverage.first { $0.competitionId == fixture.competitionId }?.status == .covered
        let admitted: Bool
        switch fixture.source.verification {
        case .verified: admitted = true
        case .held: admitted = false
        case nil: admitted = covered
        }
        return CricketFixtureMetadata(fixtureID: fixture.id, competitionID: fixture.competitionId,
            competitionName: fixture.competitionName, format: fixture.format, status: fixture.status,
            observedAt: date(fixture.source.observedAt) ?? .distantPast,
            verified: admitted && snapshot.sourceStatus.verifiesCurrentRows,
            context: fixture.context,
            homeTeamID: fixture.home.id, awayTeamID: fixture.away.id, matchOrdinal: fixture.matchOrdinal)
    }

    @MainActor
    private static func projectedEvent(for fixture: Fixture, metadata: CricketFixtureMetadata, kickoff: Date) -> EventReference {
        .init(id: fixtureIDPrefix + fixture.id,
            title: "\(fixture.competitionName) · \(fixture.home.name) vs \(fixture.away.name)", category: "cricket",
            date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: fixture.home.name, badge: nil), away: .init(name: fixture.away.name, badge: nil)),
            sources: [], cricketFixture: metadata)
    }

}

struct CricketFixtureMetadata: Codable, Equatable, Sendable {
    let fixtureID: String
    let competitionID: String
    let competitionName: String
    let format: CricketFixtureCatalog.Format
    let status: CricketFixtureCatalog.Status
    let observedAt: Date
    let verified: Bool
    /// Optional score facts and exact enclosing fixture team identities. Legacy
    /// caches decode without these fields; they cannot supply a scorecard.
    let context: CricketMatchContext?
    let homeTeamID: String?
    let awayTeamID: String?
    let matchOrdinal: Int?

    /// A day rollover changes discovery authority, not the canonical Test or
    /// ownership of a stream already playing. Lunch/Tea changes do not churn it.
    var broadcastDayIdentity: String? {
        guard format == .test else { return nil }
        return "test:\(context?.matchOrdinal.map(String.init) ?? "?"):\(context?.day.map(String.init) ?? "?"):\(context?.matchEndsAt ?? "?")"
    }

    private enum CodingKeys: String, CodingKey {
        case fixtureID, competitionID, competitionName, format, status, observedAt, verified
        case context, homeTeamID, awayTeamID, matchOrdinal
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fixtureID = try values.decode(String.self, forKey: .fixtureID)
        competitionID = try values.decode(String.self, forKey: .competitionID)
        competitionName = try values.decode(String.self, forKey: .competitionName)
        format = try values.decode(CricketFixtureCatalog.Format.self, forKey: .format)
        status = try values.decode(CricketFixtureCatalog.Status.self, forKey: .status)
        observedAt = try values.decode(Date.self, forKey: .observedAt)
        verified = try values.decode(Bool.self, forKey: .verified)
        homeTeamID = try? values.decode(String.self, forKey: .homeTeamID)
        awayTeamID = try? values.decode(String.self, forKey: .awayTeamID)
        let acceptsOrdinal = format == .odi || format == .t20
        matchOrdinal = (try? values.decode(Int.self, forKey: .matchOrdinal)).flatMap { acceptsOrdinal && (1...99).contains($0) ? $0 : nil }
        let candidate = try? values.decode(CricketMatchContext.self, forKey: .context)
        if let homeTeamID, let awayTeamID {
            context = candidate?.validated(format: format, homeTeamID: homeTeamID, awayTeamID: awayTeamID)
        } else { context = nil }
    }

    init(fixtureID: String, competitionID: String, competitionName: String,
         format: CricketFixtureCatalog.Format, status: CricketFixtureCatalog.Status,
         observedAt: Date, verified: Bool,
         context: CricketMatchContext? = nil, homeTeamID: String? = nil, awayTeamID: String? = nil, matchOrdinal: Int? = nil) {
        self.fixtureID = fixtureID; self.competitionID = competitionID; self.competitionName = competitionName
        self.format = format; self.status = status; self.observedAt = observedAt; self.verified = verified
        self.context = context; self.homeTeamID = homeTeamID; self.awayTeamID = awayTeamID
        self.matchOrdinal = matchOrdinal.flatMap { [CricketFixtureCatalog.Format.odi, .t20].contains(format) && (1...99).contains($0) ? $0 : nil }
    }

    func isLive(at now: Date) -> Bool {
        verified && status == .live && (-300...CricketFixtureCatalog.statusFreshness).contains(now.timeIntervalSince(observedAt))
    }

}

@MainActor
final class CricketFixtureUpdater {
    static let shared = CricketFixtureUpdater()
    private static let cacheKey = "Fotty.CricketFixtures.lastKnownGood.v1"
    private let defaults: UserDefaults
    private let fetch: (URLRequest) async throws -> (Data, URLResponse)
    private var lastAttempt: Date?
    private var retryAt: Date?
    private var isRefreshing = false
    init(defaults: UserDefaults = .standard,
         fetch: @escaping (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }) {
        self.defaults = defaults; self.fetch = fetch
    }

    func cachedSnapshot(now: Date = .init()) -> CricketFixtureCatalog.Snapshot? {
        guard let data = defaults.data(forKey: Self.cacheKey) else { return nil }
        return try? CricketFixtureCatalog.validatedSnapshot(from: data, now: now, reconciledCache: true)
    }
    func refresh(now: Date = .init(), force: Bool = false) async -> CricketFixtureCatalog.Snapshot? {
        let cached = cachedSnapshot(now: now)
        guard !isRefreshing else { return cached }
        if !force {
            if let retryAt {
                if now < retryAt { return cached }
            } else if let lastAttempt,
                      (0..<CricketFixtureCatalog.pollingInterval(snapshot: cached, now: now)).contains(now.timeIntervalSince(lastAttempt)) {
                return cached
            }
        }
        guard let url = Config.footballProxyBaseURL?.appendingPathComponent("api/cricket/fixtures") else { return cached }
        lastAttempt = now; isRefreshing = true
        defer { isRefreshing = false }
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 12)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await fetch(request)
            try Task.checkCancellation()
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let candidate = try CricketFixtureCatalog.validatedSnapshot(from: data, now: now)
            let accepted = CricketFixtureCatalog.accepting(candidate, over: cached)
            // An HTTP200 fallback still means the fixture authority could not
            // be checked. Retry independently of the cached quiet-day cadence.
            let rejectedCandidate = cached.map { accepted == $0 && candidate != $0 } ?? false
            retryAt = !candidate.sourceStatus.verifiesCurrentRows || rejectedCandidate
                || accepted.coverage.contains(where: { $0.status == .unavailable }) ? now.addingTimeInterval(5 * 60) : nil
            defaults.set(try JSONEncoder().encode(accepted), forKey: Self.cacheKey)
            return accepted
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                lastAttempt = nil
                retryAt = nil
            }
            // Retry outages promptly, even if the prior schedule was quiet.
            else { retryAt = now.addingTimeInterval(5 * 60) }
            return cached
        }
    }
}
