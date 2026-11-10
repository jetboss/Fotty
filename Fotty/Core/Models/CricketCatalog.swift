import Foundation

enum CPLTeam: String, CaseIterable, Sendable {
    case antigua = "Antigua & Barbuda Falcons"
    case barbados = "Barbados Tridents"
    case guyana = "Guyana Amazon Warriors"
    case jamaica = "Jamaica Kingsmen"
    case saintLucia = "Saint Lucia Kings"
    case stKitts = "St Kitts & Nevis Patriots"
    case trinbago = "Trinbago Knight Riders"

    private var aliases: [String] {
        switch self {
        case .antigua: return [rawValue, "Antigua and Barbuda Falcons", "Antigua Falcons"]
        case .barbados: return [rawValue, "Barbados Royals"]
        case .saintLucia: return [rawValue, "St Lucia Kings"]
        case .stKitts: return [rawValue, "St Kitts and Nevis Patriots", "Saint Kitts and Nevis Patriots", "St Kitts Nevis Patriots"]
        default: return [rawValue]
        }
    }

    private static let normalizedAliasNeedles: [CPLTeam: [String]] = Dictionary(
        uniqueKeysWithValues: allCases.map { team in
            (team, team.aliases.map { " " + normalized($0) + " " })
        }
    )

    static func containsTwoDistinctTeams(in text: String) -> Bool {
        let haystack = normalizedHaystack(text)
        var foundTeam = false
        for team in allCases where team.matches(normalizedHaystack: haystack) {
            if foundTeam { return true }
            foundTeam = true
        }
        return false
    }

    private func matches(normalizedHaystack: String) -> Bool {
        Self.normalizedAliasNeedles[self]?.contains { normalizedHaystack.contains($0) } ?? false
    }

    private static func normalizedHaystack(_ text: String) -> String {
        " " + normalized(text) + " "
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "&", with: "and")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    init?(manifestKey: String) {
        switch manifestKey {
        case "antigua": self = .antigua
        case "barbados": self = .barbados
        case "guyana": self = .guyana
        case "jamaica": self = .jamaica
        case "saintLucia": self = .saintLucia
        case "stKitts": self = .stKitts
        case "trinbago": self = .trinbago
        default: return nil
        }
    }
}

enum CricketCatalogFilter: String, CaseIterable, Identifiable {
    case all, cpl, channels
    var id: Self { self }
    var displayName: String {
        switch self {
        case .all: return "All cricket"
        case .cpl: return "CPL"
        case .channels: return "Channels"
        }
    }

    func includes(_ event: AnalyticalDataEngine.EventReference) -> Bool {
        switch self {
        case .all: return true
        case .cpl: return event.isCPLFixture
        case .channels: return event.isBroadcastChannel
        }
    }
}

/// Local channel identities survive a fixture/master-catalog outage. Their
/// existence makes no claim about the programme currently being broadcast.
enum CricketBroadcastChannel: String, CaseIterable, Sendable {
    case willow, foxCricket

    var canonicalID: String {
        switch self {
        case .willow: "cricket-channel:willow"
        case .foxCricket: "cricket-channel:fox-cricket"
        }
    }

    var title: String {
        switch self {
        case .willow: "Willow Cricket"
        case .foxCricket: "Fox Cricket"
        }
    }

    static func identifying(title: String?) -> Self? {
        guard let title else { return nil }
        let normalized = title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        switch normalized {
        case "willow", "willowtv", "willowcricket", "willowhd", "willowcrickethd", "willowcricket247": return .willow
        case "foxcricket", "foxcrickethd": return .foxCricket
        default: return nil
        }
    }

    nonisolated static func identifying(request: StreamPlaybackRequest) -> Self? {
        guard request.category == "cricket", request.kickoffDate == nil,
              let channel = allCases.first(where: { $0.canonicalID == request.matchID }),
              identifying(title: request.displayTitle) == channel,
              identifying(title: request.homeTeam) == channel,
              request.awayTeam.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let event = request.preferredEvent {
            guard event.id == channel.canonicalID, event.category == "cricket",
                  identifying(title: event.title) == channel,
                  event.kickoffDate == nil, event.teams == nil,
                  event.cricketFixture == nil, event.sportsFixture == nil,
                  event.competitionID == nil, !event.hasCatalogIdentityConflict else { return nil }
        }
        return channel
    }
}

@MainActor
enum CricketChannelCatalog {
    /// Canonicalize only known channels. Fixtures and unrelated channels retain
    /// their own identity; Willow 2 must never supply the main Willow channel.
    static func merging(into events: [EventReference]) -> [EventReference] {
        let reservedIDs = Set(CricketBroadcastChannel.allCases.map(\.canonicalID))
        let retained = events.filter { event in
            if reservedIDs.contains(event.id) { return false }
            return event.normalizedCategory != "cricket"
                || CricketBroadcastChannel.identifying(title: event.title) == nil
        }
        return retained + CricketBroadcastChannel.allCases.map { event(for: $0, in: events) }
    }

    static func event(for channel: CricketBroadcastChannel, in events: [EventReference]) -> EventReference {
        var seen = Set<String>()
        let sources = events.filter { self.channel(for: $0) == channel }.flatMap { $0.sources ?? [] }.filter { source in
            guard !source.id.isEmpty, StreamPluginProviderMatching.isActiveCatalogSource(source) else { return false }
            return seen.insert(source.source + "\u{0}" + source.id).inserted
        }
        return .init(id: channel.canonicalID, title: channel.title, category: "cricket", date: nil,
            poster: nil, popular: false, teams: nil, sources: sources)
    }

    /// Explicit channel navigation is independent of fixture-team/date matching.
    /// Only the two reviewed channel identities can use this path.
    static func canonicalEvent(for event: EventReference, in events: [EventReference]) -> EventReference? {
        guard let channel = channel(for: event) else { return nil }
        return self.event(for: channel, in: events)
    }

    private static func channel(for event: EventReference) -> CricketBroadcastChannel? {
        guard event.normalizedCategory == "cricket", !event.hasCatalogIdentityConflict,
              event.kickoffDate == nil,
              event.cricketFixture == nil, event.sportsFixture == nil,
              event.competitionID == nil, event.teams == nil,
              let channel = CricketBroadcastChannel.identifying(title: event.title) else { return nil }
        if let reserved = CricketBroadcastChannel.allCases.first(where: { $0.canonicalID == event.id }),
           reserved != channel { return nil }
        return channel
    }
}

/// Bundled last-known-good schedule plus a strictly validated remote update path.
/// This is not a live-score, broadcast-rights or EPG service.
/// Published sources:
/// https://cplt20.prezly.com/republic-bank-cpl-fixtures-confirmed-for-2026
/// https://wp.cplt20.com/wp-json/wp/v2/news/20232 (27 July TKR opponent swap)
/// https://cplt20.prezly.com/barbados-franchise-to-play-as-tridents
enum CPLSchedule {
    static let sourceLabel = "CPL fixture schedule · automatically checked"
    static let sourceNote = "A fixture does not confirm broadcast availability."
    /// The app checks every 30 minutes while active. Two hours tolerates a short
    /// outage without allowing an old schedule to continue looking current.
    static let verificationFreshnessWindow: TimeInterval = 2 * 3600

    enum SourceStatus: String, Decodable, Equatable, Sendable {
        case verified
        case liveVerified = "live-verified"
        case lastKnownGood = "last-known-good"

        var isCurrentVerification: Bool {
            self == .verified || self == .liveVerified
        }
    }

    enum ValidationError: Error, Equatable {
        case invalidHeader
        case invalidCheckDate
        case invalidFixtureCount
        case invalidFixture(Int)
    }

    struct Snapshot: Sendable {
        let revision: String
        let checkedAt: Date
        let fixtures: [Fixture]
        let sourceStatus: SourceStatus
        let season: Int

        init(
            revision: String,
            checkedAt: Date,
            fixtures: [Fixture],
            sourceStatus: SourceStatus,
            season: Int = 2026
        ) {
            self.revision = revision
            self.checkedAt = checkedAt
            self.fixtures = fixtures
            self.sourceStatus = sourceStatus
            self.season = season
        }

        func isFreshlyVerified(at now: Date) -> Bool {
            CPLSchedule.isFreshlyVerified(
                checkedAt: checkedAt,
                sourceStatus: sourceStatus,
                at: now
            )
        }
    }

    static func isFreshlyVerified(
        checkedAt: Date?,
        sourceStatus: SourceStatus,
        at now: Date
    ) -> Bool {
        guard let checkedAt else { return false }
        let age = now.timeIntervalSince(checkedAt)
        return sourceStatus.isCurrentVerification
            && age >= -5 * 60
            && age <= verificationFreshnessWindow
    }

    private struct Manifest: Decodable, Sendable {
        let schemaVersion: Int
        let competitionId: String
        let season: Int
        let revision: String
        let checkedAt: String
        let sourceStatus: String?
        let fixtureCount: Int?
        let teamNames: [String: String]?
        let fixtures: [Record]
    }

    private struct Record: Decodable, Sendable {
        let number: Int
        let upstreamId: String
        let start: String
        let team1: String?
        let team2: String?
        let stage: String?
    }

    struct Fixture: Equatable, Sendable {
        let season: Int
        let number: Int
        let start: String
        let home: CPLTeam?
        let away: CPLTeam?
        let homeName: String?
        let awayName: String?
        let stage: String?

        init(
            _ number: Int,
            _ start: String,
            _ home: CPLTeam,
            _ away: CPLTeam,
            stage: String? = nil,
            season: Int = 2026
        ) {
            self.season = season; self.number = number; self.start = start; self.home = home; self.away = away
            self.homeName = home.rawValue; self.awayName = away.rawValue; self.stage = stage
        }

        init(_ number: Int, _ start: String, stage: String, season: Int = 2026) {
            self.season = season; self.number = number; self.start = start; self.home = nil; self.away = nil
            self.homeName = nil; self.awayName = nil; self.stage = stage
        }

        init(
            _ number: Int,
            _ start: String,
            homeName: String,
            awayName: String,
            stage: String? = nil,
            season: Int
        ) {
            self.season = season; self.number = number; self.start = start
            self.home = nil; self.away = nil; self.homeName = homeName; self.awayName = awayName; self.stage = stage
        }

        var id: String { "cpl-\(season)-\(number)" }
        var kickoff: Date { ISO8601DateFormatter().date(from: start)! }

        @MainActor
        func event(sources: [NexusASource] = []) -> AnalyticalDataEngine.EventReference {
            let title: String
            let teams: NexusATeams?
            if let homeName, let awayName {
                let competition = stage.map { "CPL \($0)" } ?? "CPL"
                title = "\(competition) · \(homeName) vs \(awayName)"
                teams = NexusATeams(
                    home: NexusATeam(name: homeName, badge: nil),
                    away: NexusATeam(name: awayName, badge: nil)
                )
            } else {
                title = stage.map { "CPL \($0)" } ?? "CPL fixture"
                teams = nil
            }
            return .init(
                id: id, title: title, category: "cricket",
                date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: false,
                teams: teams,
                sources: sources
            )
        }
    }

    // Explicit offsets preserve venue-local dates (Jamaica is UTC−5; the other
    // host countries are UTC−4). Match numbers stay stable after rescheduling.
    static let fixtures: [Fixture] = [
        .init(1, "2026-08-07T19:00:00-04:00", .jamaica, .antigua),
        .init(2, "2026-08-08T19:00:00-04:00", .stKitts, .trinbago),
        .init(3, "2026-08-09T19:00:00-04:00", .antigua, .saintLucia),
        .init(4, "2026-08-11T19:00:00-05:00", .jamaica, .barbados),
        .init(5, "2026-08-12T19:00:00-04:00", .saintLucia, .stKitts),
        .init(6, "2026-08-13T19:00:00-05:00", .jamaica, .guyana),
        .init(7, "2026-08-14T19:00:00-04:00", .saintLucia, .antigua),
        .init(8, "2026-08-15T19:00:00-05:00", .jamaica, .trinbago),
        .init(9, "2026-08-16T19:00:00-04:00", .saintLucia, .barbados),
        .init(10, "2026-08-18T19:00:00-05:00", .jamaica, .stKitts),
        .init(11, "2026-08-19T19:00:00-04:00", .saintLucia, .guyana),
        .init(12, "2026-08-20T19:00:00-04:00", .antigua, .stKitts),
        .init(13, "2026-08-21T19:00:00-04:00", .saintLucia, .jamaica),
        .init(14, "2026-08-22T19:00:00-04:00", .antigua, .trinbago),
        .init(15, "2026-08-23T19:00:00-04:00", .antigua, .guyana),
        .init(16, "2026-08-25T19:00:00-04:00", .antigua, .barbados),
        .init(17, "2026-08-26T19:00:00-04:00", .trinbago, .saintLucia),
        .init(18, "2026-08-27T19:00:00-04:00", .stKitts, .jamaica),
        .init(19, "2026-08-28T20:00:00-04:00", .trinbago, .barbados),
        .init(20, "2026-08-29T19:00:00-04:00", .trinbago, .jamaica),
        .init(21, "2026-08-30T19:00:00-04:00", .stKitts, .antigua),
        .init(22, "2026-08-31T17:00:00-04:00", .trinbago, .guyana),
        .init(23, "2026-09-01T19:00:00-04:00", .stKitts, .barbados),
        .init(24, "2026-09-02T19:00:00-04:00", .trinbago, .antigua),
        .init(25, "2026-09-03T19:00:00-04:00", .stKitts, .saintLucia),
        .init(26, "2026-09-04T19:00:00-04:00", .guyana, .jamaica),
        .init(27, "2026-09-05T20:00:00-04:00", .barbados, .trinbago),
        .init(28, "2026-09-06T10:00:00-04:00", .guyana, .stKitts),
        .init(29, "2026-09-06T19:00:00-04:00", .barbados, .saintLucia),
        .init(30, "2026-09-08T19:00:00-04:00", .guyana, .antigua),
        .init(31, "2026-09-09T19:00:00-04:00", .guyana, .saintLucia),
        .init(32, "2026-09-10T19:00:00-04:00", .barbados, .stKitts),
        .init(33, "2026-09-11T19:00:00-04:00", .guyana, .trinbago),
        .init(34, "2026-09-12T20:00:00-04:00", .barbados, .jamaica),
        .init(35, "2026-09-13T19:00:00-04:00", .barbados, .guyana),
        .init(36, "2026-09-16T19:00:00-04:00", .barbados, .jamaica, stage: "Eliminator"),
        .init(37, "2026-09-17T20:00:00-04:00", .guyana, .antigua, stage: "Qualifier 1"),
        .init(38, "2026-09-18T19:00:00-04:00", .guyana, .jamaica, stage: "Qualifier 2"),
        .init(39, "2026-09-20T19:00:00-04:00", .antigua, .jamaica, stage: "Final")
    ]

    static func validatedSnapshot(from data: Data, now: Date = .init()) throws -> Snapshot {
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: now)
        guard manifest.schemaVersion == 1,
              manifest.competitionId == "cpl",
              (currentYear - 1...currentYear + 2).contains(manifest.season),
              !manifest.revision.isEmpty else {
            throw ValidationError.invalidHeader
        }
        let formatter = ISO8601DateFormatter()
        guard let checkedAt = formatter.date(from: manifest.checkedAt),
              checkedAt <= now.addingTimeInterval(24 * 3600) else {
            throw ValidationError.invalidCheckDate
        }
        let sourceStatus: SourceStatus
        if let rawStatus = manifest.sourceStatus {
            guard let decodedStatus = SourceStatus(rawValue: rawStatus) else {
                throw ValidationError.invalidHeader
            }
            sourceStatus = decodedStatus
        } else {
            // Reviewed manifests bundled with the app predate the runtime status
            // field. They remain safe fallback data, but are never called fresh.
            sourceStatus = .lastKnownGood
        }
        guard (2...100).contains(manifest.fixtures.count),
              manifest.fixtureCount.map({ $0 == manifest.fixtures.count }) ?? true else {
            throw ValidationError.invalidFixtureCount
        }

        var seenNumbers = Set<Int>()
        var seenUpstreamIDs = Set<String>()
        var seenStages = Set<String>()
        var teamFixtureCount = 0
        var previousKickoff = Date.distantPast
        var decoded: [Fixture] = []
        for record in manifest.fixtures {
            guard (1...manifest.fixtures.count).contains(record.number),
                  seenNumbers.insert(record.number).inserted,
                  !record.upstreamId.isEmpty,
                  seenUpstreamIDs.insert(record.upstreamId).inserted,
                  let kickoff = formatter.date(from: record.start),
                  Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: kickoff).year == manifest.season,
                  kickoff >= previousKickoff else {
                throw ValidationError.invalidFixture(record.number)
            }
            previousKickoff = kickoff

            if let team1Key = record.team1, let team2Key = record.team2 {
                let team1 = CPLTeam(manifestKey: team1Key)
                let team2 = CPLTeam(manifestKey: team2Key)
                let team1Name = team1?.rawValue ?? manifest.teamNames?[team1Key]
                let team2Name = team2?.rawValue ?? manifest.teamNames?[team2Key]
                let stage = record.stage?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let team1Name, let team2Name,
                      validParticipantName(team1Name), validParticipantName(team2Name),
                      team1Name.caseInsensitiveCompare(team2Name) != .orderedSame else {
                    throw ValidationError.invalidFixture(record.number)
                }
                if let stage {
                    guard !stage.isEmpty,
                          stage.count <= 64,
                          seenStages.insert(stage.lowercased()).inserted else {
                        throw ValidationError.invalidFixture(record.number)
                    }
                }
                teamFixtureCount += 1
                if let team1, let team2 {
                    decoded.append(.init(
                        record.number,
                        record.start,
                        team1,
                        team2,
                        stage: stage,
                        season: manifest.season
                    ))
                } else {
                    decoded.append(.init(
                        record.number,
                        record.start,
                        homeName: team1Name,
                        awayName: team2Name,
                        stage: stage,
                        season: manifest.season
                    ))
                }
            } else {
                let stage = record.stage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard record.team1 == nil,
                      record.team2 == nil,
                      !stage.isEmpty,
                      stage.count <= 64,
                      seenStages.insert(stage.lowercased()).inserted else {
                    throw ValidationError.invalidFixture(record.number)
                }
                decoded.append(.init(record.number, record.start, stage: stage, season: manifest.season))
            }
        }
        guard seenNumbers == Set(1...manifest.fixtures.count), teamFixtureCount > 0 else {
            throw ValidationError.invalidFixtureCount
        }
        return Snapshot(
            revision: manifest.revision,
            checkedAt: checkedAt,
            fixtures: decoded,
            sourceStatus: sourceStatus,
            season: manifest.season
        )
    }

    nonisolated static func isManagedFixtureID(_ id: String) -> Bool {
        id.range(of: #"^cpl-\d{4}-\d+$"#, options: .regularExpression) != nil
    }

    /// A fresh timing receipt must not erase participants that were already
    /// resolved for the same playoff round. This also upgrades an older
    /// stage-only on-device cache from the reviewed bundled fallback.
    static func preservingKnownPlayoffParticipants(
        in candidate: [Fixture],
        from known: [Fixture]
    ) -> [Fixture] {
        let knownByRound = Dictionary(uniqueKeysWithValues: known.compactMap { fixture in
            fixture.stage.map { ("\(fixture.season)|\($0.lowercased())", fixture) }
        })
        return candidate.map { fixture in
            guard fixture.homeName == nil,
                  fixture.awayName == nil,
                  let stage = fixture.stage,
                  let resolved = knownByRound["\(fixture.season)|\(stage.lowercased())"],
                  let homeName = resolved.homeName,
                  let awayName = resolved.awayName else { return fixture }
            if let home = resolved.home, let away = resolved.away {
                return Fixture(
                    fixture.number,
                    fixture.start,
                    home,
                    away,
                    stage: stage,
                    season: fixture.season
                )
            }
            return Fixture(
                fixture.number,
                fixture.start,
                homeName: homeName,
                awayName: awayName,
                stage: stage,
                season: fixture.season
            )
        }
    }

    private static func validParticipantName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return (2...64).contains(trimmed.count)
            && trimmed.unicodeScalars.allSatisfy {
                CharacterSet.letters
                    .union(.whitespaces)
                    .union(CharacterSet(charactersIn: "&'.-"))
                    .contains($0)
            }
    }

    @MainActor
    static func merging(
        into catalog: [AnalyticalDataEngine.EventReference],
        fixtures scheduleFixtures: [Fixture] = fixtures,
        at now: Date = .init()
    ) -> [AnalyticalDataEngine.EventReference] {
        // Earlier projections of this schedule are replaced.
        let remaining = catalog.filter { !isManagedFixtureID($0.id) }
        guard let firstFixture = scheduleFixtures.first,
              let lastFixture = scheduleFixtures.last else { return remaining }
        let start = firstFixture.kickoff.addingTimeInterval(-7 * 24 * 3600)
        let end = lastFixture.kickoff.addingTimeInterval(CatalogTimingPolicy.cplWindow)
        guard now >= start, now <= end else { return remaining }

        // T20 rows should not linger into the following day. Eight hours covers
        // rain delays and is shared by discovery, saved rows and channel actions.
        let events = scheduleFixtures
            .filter { $0.kickoff > now.addingTimeInterval(-CatalogTimingPolicy.cplWindow) }
            .map { $0.event() }
        // Within the verified season, any other CPL row must not appear beside
        // the trusted fixture as a second match.
        return remaining.filter { !$0.isCPLFixture } + events
    }

}

/// Retrieves the small reviewed manifest independently from the stream provider.
/// Only a complete, newer, structurally valid schedule replaces the cached copy.
@MainActor
final class CPLScheduleUpdater {
    static let shared = CPLScheduleUpdater()

    private static let cacheKey = "Fotty.CPLSchedule.lastKnownGood.v1"
    private let fetch: (URLRequest) async throws -> (Data, URLResponse)
    private let defaults: UserDefaults
    private var lastAttempt: Date?

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.fetch = { try await session.data(for: $0) }
        self.defaults = defaults
    }

    init(defaults: UserDefaults, fetch: @escaping (URLRequest) async throws -> (Data, URLResponse)) {
        self.fetch = fetch
        self.defaults = defaults
    }

    func cachedSnapshot(now: Date = .init()) -> CPLSchedule.Snapshot? {
        guard let data = defaults.data(forKey: Self.cacheKey) else { return nil }
        return try? CPLSchedule.validatedSnapshot(from: data, now: now)
    }

    static func shouldKeepCached(
        _ cached: CPLSchedule.Snapshot,
        over candidate: CPLSchedule.Snapshot
    ) -> Bool {
        if cached.season != candidate.season {
            return cached.season > candidate.season
        }
        if cached.sourceStatus.isCurrentVerification && !candidate.sourceStatus.isCurrentVerification {
            return true
        }
        return cached.sourceStatus.isCurrentVerification == candidate.sourceStatus.isCurrentVerification
            && cached.checkedAt > candidate.checkedAt
    }

    func refresh(now: Date = .init()) async -> CPLSchedule.Snapshot? {
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < 30 * 60 {
            return cachedSnapshot(now: now)
        }
        lastAttempt = now
        guard let url = Config.cplScheduleManifestURL else {
            return cachedSnapshot(now: now)
        }

        do {
            var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 12)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await fetch(request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  data.count <= 128 * 1024 else {
                return cachedSnapshot(now: now)
            }
            let candidate = try CPLSchedule.validatedSnapshot(from: data, now: now)
            if let cached = cachedSnapshot(now: now) {
                // A Worker fallback must never downgrade a successfully verified
                // cached schedule. Among equal-trust snapshots, newest wins.
                if Self.shouldKeepCached(cached, over: candidate) {
                    return cached
                }
            }
            defaults.set(data, forKey: Self.cacheKey)
            return candidate
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                // A cancelled owner did not perform a completed schedule check.
                // The next visible owner may retry; ordinary attempts retain the
                // reviewed thirty-minute source cadence.
                lastAttempt = nil
                return cachedSnapshot(now: now)
            }
            print("[CPLSchedule] Remote update rejected; keeping last-known-good schedule: \(error.localizedDescription)")
            return cachedSnapshot(now: now)
        }
    }
}
