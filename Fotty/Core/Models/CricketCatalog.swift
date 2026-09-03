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

    func matches(in text: String) -> Bool {
        let haystack = " " + Self.normalized(text) + " "
        return aliases.contains { haystack.contains(" " + Self.normalized($0) + " ") }
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

/// Bundled last-known-good schedule plus a strictly validated remote update path.
/// This is not a live-score, broadcast-rights or EPG service.
/// Published sources:
/// https://cplt20.prezly.com/republic-bank-cpl-fixtures-confirmed-for-2026
/// https://wp.cplt20.com/wp-json/wp/v2/news/20232 (27 July TKR opponent swap)
/// https://cplt20.prezly.com/barbados-franchise-to-play-as-tridents
enum CPLSchedule {
    static let sourceLabel = "CPL fixture schedule · automatically checked"
    static let sourceNote = "Times are shown in your time zone. Fotty keeps the last verified schedule if an update is incomplete; fixtures do not confirm a broadcast."

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
    }

    private struct Manifest: Decodable, Sendable {
        let schemaVersion: Int
        let competitionId: String
        let season: Int
        let revision: String
        let checkedAt: String
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

    struct Fixture: Sendable {
        let number: Int
        let start: String
        let home: CPLTeam?
        let away: CPLTeam?
        let stage: String?

        init(_ number: Int, _ start: String, _ home: CPLTeam, _ away: CPLTeam) {
            self.number = number; self.start = start; self.home = home; self.away = away; self.stage = nil
        }

        init(_ number: Int, _ start: String, stage: String) {
            self.number = number; self.start = start; self.home = nil; self.away = nil; self.stage = stage
        }

        var id: String { "cpl-2026-\(number)" }
        var kickoff: Date { ISO8601DateFormatter().date(from: start)! }

        @MainActor
        func event(sources: [NexusASource] = []) -> AnalyticalDataEngine.EventReference {
            let homeName = home?.rawValue ?? stage ?? "CPL"
            let awayName = away?.rawValue ?? "Teams to be confirmed"
            return .init(
                id: id, title: "CPL · \(homeName) vs \(awayName)", category: "cricket",
                date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: false,
                teams: NexusATeams(home: NexusATeam(name: homeName, badge: nil), away: NexusATeam(name: awayName, badge: nil)),
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
        .init(36, "2026-09-16T19:00:00-04:00", stage: "Eliminator"),
        .init(37, "2026-09-17T20:00:00-04:00", stage: "Qualifier 1"),
        .init(38, "2026-09-18T19:00:00-04:00", stage: "Qualifier 2"),
        .init(39, "2026-09-20T19:00:00-04:00", stage: "Final")
    ]

    static func validatedSnapshot(from data: Data, now: Date = .init()) throws -> Snapshot {
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.schemaVersion == 1,
              manifest.competitionId == "cpl",
              manifest.season == 2026,
              !manifest.revision.isEmpty else {
            throw ValidationError.invalidHeader
        }
        let formatter = ISO8601DateFormatter()
        guard let checkedAt = formatter.date(from: manifest.checkedAt),
              checkedAt <= now.addingTimeInterval(24 * 3600) else {
            throw ValidationError.invalidCheckDate
        }
        guard manifest.fixtures.count == 39 else {
            throw ValidationError.invalidFixtureCount
        }

        let expectedStages = [36: "Eliminator", 37: "Qualifier 1", 38: "Qualifier 2", 39: "Final"]
        var seenNumbers = Set<Int>()
        var seenUpstreamIDs = Set<String>()
        var previousKickoff = Date.distantPast
        var decoded: [Fixture] = []
        for record in manifest.fixtures {
            guard (1...39).contains(record.number),
                  seenNumbers.insert(record.number).inserted,
                  !record.upstreamId.isEmpty,
                  seenUpstreamIDs.insert(record.upstreamId).inserted,
                  let kickoff = formatter.date(from: record.start),
                  Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: kickoff).year == manifest.season,
                  kickoff >= previousKickoff else {
                throw ValidationError.invalidFixture(record.number)
            }
            previousKickoff = kickoff

            if record.number <= 35 {
                guard let team1Key = record.team1,
                      let team2Key = record.team2,
                      let team1 = CPLTeam(manifestKey: team1Key),
                      let team2 = CPLTeam(manifestKey: team2Key),
                      team1 != team2,
                      record.stage == nil else {
                    throw ValidationError.invalidFixture(record.number)
                }
                decoded.append(.init(record.number, record.start, team1, team2))
            } else {
                guard record.team1 == nil,
                      record.team2 == nil,
                      record.stage == expectedStages[record.number] else {
                    throw ValidationError.invalidFixture(record.number)
                }
                decoded.append(.init(record.number, record.start, stage: record.stage!))
            }
        }
        guard seenNumbers == Set(1...39) else {
            throw ValidationError.invalidFixtureCount
        }
        return Snapshot(revision: manifest.revision, checkedAt: checkedAt, fixtures: decoded)
    }

    @MainActor
    static func merging(
        into catalog: [AnalyticalDataEngine.EventReference],
        fixtures scheduleFixtures: [Fixture] = fixtures,
        at now: Date = .init()
    ) -> [AnalyticalDataEngine.EventReference] {
        // Drop our own cached rows first: only a fresh provider match may supply
        // sources. The snapshot remains useful offline but cannot promise Watch.
        var remaining = catalog.filter { !$0.id.hasPrefix("cpl-2026-") }
        guard let firstFixture = scheduleFixtures.first,
              let lastFixture = scheduleFixtures.last else { return remaining }
        let start = firstFixture.kickoff.addingTimeInterval(-7 * 24 * 3600)
        let end = lastFixture.kickoff.addingTimeInterval(8 * 3600)
        guard now >= start, now <= end else { return remaining }

        // T20 rows should not linger into the following day. Eight hours covers
        // rain delays while agreeing with the six-hour display timing policy.
        let active = scheduleFixtures.filter { $0.kickoff >= now.addingTimeInterval(-8 * 3600) }
        var events: [AnalyticalDataEngine.EventReference] = []
        for fixture in active {
            let matching = remaining.filter { matches($0, fixture: fixture) }
            let matchedIDs = Set(matching.map(\.id))
            remaining.removeAll { matchedIDs.contains($0.id) }
            var seenSources = Set<String>()
            let sources = matching.flatMap { $0.sources ?? [] }.filter {
                StreamPluginProviderMatching.isActiveCatalogSource($0)
                    && seenSources.insert("\($0.source)|\($0.id)").inserted
            }
            events.append(fixture.event(sources: sources))
        }
        return remaining + events
    }

    @MainActor
    static func matches(_ event: AnalyticalDataEngine.EventReference, fixture: Fixture) -> Bool {
        guard event.normalizedCategory == "cricket", !event.isBroadcastChannel,
              let kickoff = event.kickoffDate, abs(kickoff.timeIntervalSince(fixture.kickoff)) <= 60 * 60,
              let home = fixture.home, let away = fixture.away else { return false }
        return (home.matches(in: event.homeName) && away.matches(in: event.awayName))
            || (away.matches(in: event.homeName) && home.matches(in: event.awayName))
    }
}

/// Retrieves the small reviewed manifest independently from the stream provider.
/// Only a complete, newer, structurally valid schedule replaces the cached copy.
@MainActor
final class CPLScheduleUpdater {
    static let shared = CPLScheduleUpdater()

    private static let cacheKey = "Fotty.CPLSchedule.lastKnownGood.v1"
    private let session: URLSession
    private let defaults: UserDefaults
    private var lastAttempt: Date?

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
    }

    func cachedSnapshot(now: Date = .init()) -> CPLSchedule.Snapshot? {
        guard let data = defaults.data(forKey: Self.cacheKey) else { return nil }
        return try? CPLSchedule.validatedSnapshot(from: data, now: now)
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
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  data.count <= 128 * 1024 else {
                return cachedSnapshot(now: now)
            }
            let candidate = try CPLSchedule.validatedSnapshot(from: data, now: now)
            if let cached = cachedSnapshot(now: now), cached.checkedAt > candidate.checkedAt {
                return cached
            }
            defaults.set(data, forKey: Self.cacheKey)
            return candidate
        } catch {
            print("[CPLSchedule] Remote update rejected; keeping last-known-good schedule: \(error.localizedDescription)")
            return cachedSnapshot(now: now)
        }
    }
}
