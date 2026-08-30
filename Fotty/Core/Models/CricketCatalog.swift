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

/// Small, explicitly dated schedule snapshot, not a live-score or EPG service.
/// Sources checked 27 Aug 2026:
/// https://cplt20.prezly.com/republic-bank-cpl-fixtures-confirmed-for-2026
/// https://wp.cplt20.com/wp-json/wp/v2/news/20232 (27 July TKR opponent swap)
/// https://cplt20.prezly.com/barbados-franchise-to-play-as-tridents
/// Refresh this snapshot from league announcements before each beta release
/// during the season. Never roll these dates into the next year automatically.
enum CPLSchedule {
    static let sourceLabel = "CPL published schedule · checked 27 Aug 2026"
    static let sourceNote = "Times are shown in your time zone. This saved schedule may change; it is not a live score or broadcast confirmation."

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

    @MainActor
    static func merging(into catalog: [AnalyticalDataEngine.EventReference], at now: Date = .init()) -> [AnalyticalDataEngine.EventReference] {
        // Drop our own cached rows first: only a fresh provider match may supply
        // sources. The snapshot remains useful offline but cannot promise Watch.
        var remaining = catalog.filter { !$0.id.hasPrefix("cpl-2026-") }
        let start = fixtures[0].kickoff.addingTimeInterval(-7 * 24 * 3600)
        let end = fixtures[fixtures.count - 1].kickoff.addingTimeInterval(36 * 3600)
        guard now >= start, now <= end else { return remaining }

        let active = fixtures.filter { $0.kickoff >= now.addingTimeInterval(-36 * 3600) }
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
