import Foundation

/// Automatic schedule receipts are independent of broadcast listings and scores.
/// A successful competition check can advance while another competition fails.
enum SportsFixtureCatalog {
    static let maximumPayloadBytes = 2 * 1024 * 1024
    static let maximumFixtures = 3_000
    static let fixtureIDPrefix = "sports-fixture:"
    static let kickoffTolerance: TimeInterval = 15 * 60
    static let statusFreshness: TimeInterval = 30 * 60
    /// Owner decision (21 Nov 2026): a failed, missing, older or odd read of a
    /// league never makes its confirmed matches look worse. Scheduled and live
    /// rows keep their confirmation for this long after the league's last
    /// accepted read. Only an explicit hold (two disagreeing observations) or a
    /// newer accepted fact changes them.
    static let confirmationGrace: TimeInterval = 6 * 3600

    enum SourceStatus: String, Codable, Sendable {
        case verified, partial, unavailable
        case lastKnownGood = "last-known-good"
        var verifiesCurrentRows: Bool { self == .verified || self == .partial }
    }
    enum Status: String, Codable, Sendable {
        case scheduled, live, finished, postponed, cancelled, unknown
        var stopsPlayback: Bool { self == .finished || self == .cancelled || self == .postponed }
    }
    enum EventKind: String, Codable, Sendable { case match, session, tournament, card }
    struct Participant: Codable, Equatable, Sendable {
        let id: String
        let name: String
        var role: String? = nil
    }
    struct Squad: Codable, Equatable, Sendable {
        enum Gender: String, Codable, Sendable { case men, women, mixed, unknown }
        let gender: Gender
        let ageGroup: String
    }
    struct Source: Codable, Equatable, Sendable {
        /// `retained` is app-only: a row kept unchanged through a failed read
        /// (owner decision, 21 Nov 2026). It stays confirmed within
        /// `confirmationGrace` but never supplies a current score or minute.
        enum Verification: String, Codable, Sendable { case verified, held, retained }
        let name: String
        let url: String
        let observedAt: String
        var updatedAt: String? = nil
        /// The server requires repeated source evidence before admitting an
        /// identity correction. Offline clients can receive the proof later.
        var correctionConfirmedAt: String? = nil
        let verification: Verification?

        init(name: String, url: String, observedAt: String, updatedAt: String? = nil,
             correctionConfirmedAt: String? = nil, verification: Verification? = nil) {
            self.name = name; self.url = url; self.observedAt = observedAt; self.updatedAt = updatedAt
            self.correctionConfirmedAt = correctionConfirmedAt; self.verification = verification
        }

        private enum CodingKeys: String, CodingKey { case name, url, observedAt, updatedAt, correctionConfirmedAt, verification }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = try values.decode(String.self, forKey: .name)
            url = try values.decode(String.self, forKey: .url)
            observedAt = try values.decode(String.self, forKey: .observedAt)
            updatedAt = try values.decodeIfPresent(String.self, forKey: .updatedAt)
            correctionConfirmedAt = try values.decodeIfPresent(String.self, forKey: .correctionConfirmedAt)
            // Only absence is the legacy cohort contract, never null/unknown.
            verification = values.contains(.verification) ? try values.decode(Verification.self, forKey: .verification) : nil
        }
    }
    struct Fixture: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let sport: String
        let start: String
        let status: Status
        let eventKind: EventKind
        let title: String
        let competitionId: String
        let competitionName: String
        let participants: [Participant]
        let squad: Squad
        let source: Source
        let reportedScore: UCLReportedScore?
        let footballLive: FootballFixtureLive?
        var kickoff: Date? { SportsFixtureCatalog.date(start) }
        var competitionKey: String { "\(sport)|\(competitionId)" }

        init(id: String, sport: String, start: String, status: Status, eventKind: EventKind, title: String,
             competitionId: String, competitionName: String, participants: [Participant], squad: Squad,
             source: Source, reportedScore: UCLReportedScore? = nil, footballLive: FootballFixtureLive? = nil) {
            self.id = id; self.sport = sport; self.start = start; self.status = status; self.eventKind = eventKind
            self.title = title; self.competitionId = competitionId; self.competitionName = competitionName
            self.participants = participants; self.squad = squad; self.source = source
            self.footballLive = footballLive?.validated(sport: sport, status: status, kind: eventKind, participants: participants)
            self.reportedScore = reportedScore?.validated(sport: sport, competitionID: competitionId, kind: eventKind,
                participants: participants, squad: squad, status: status, sourceName: source.name, sourceUpdatedAt: source.updatedAt)
        }

        private enum CodingKeys: String, CodingKey {
            case id, sport, start, status, eventKind, title, competitionId, competitionName, participants, squad, source, reportedScore, footballLive
        }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            sport = try values.decode(String.self, forKey: .sport)
            start = try values.decode(String.self, forKey: .start)
            status = try values.decode(Status.self, forKey: .status)
            eventKind = try values.decode(EventKind.self, forKey: .eventKind)
            title = try values.decode(String.self, forKey: .title)
            competitionId = try values.decode(String.self, forKey: .competitionId)
            competitionName = try values.decode(String.self, forKey: .competitionName)
            participants = try values.decode([Participant].self, forKey: .participants)
            squad = try values.decode(Squad.self, forKey: .squad)
            source = try values.decode(Source.self, forKey: .source)
            let live = try? values.decode(FootballFixtureLive.self, forKey: .footballLive)
            footballLive = live?.validated(sport: sport, status: status, kind: eventKind, participants: participants)
            let candidate = try? values.decode(UCLReportedScore.self, forKey: .reportedScore)
            reportedScore = candidate?.validated(sport: sport, competitionID: competitionId, kind: eventKind,
                participants: participants, squad: squad, status: status, sourceName: source.name, sourceUpdatedAt: source.updatedAt)
        }
    }
    struct Coverage: Codable, Equatable, Sendable {
        enum Status: String, Codable, Sendable { case covered, unavailable, unsupported }
        let sport: String
        let competitionId: String
        let competitionName: String
        let status: Status
        let checkedAt: String?
        let fixtureCount: Int
        let pendingFixtureCount: Int
        let nextStart: String?
        var competitionKey: String { "\(sport)|\(competitionId)" }
        var receiptDate: Date? { checkedAt.flatMap(SportsFixtureCatalog.date) }
    }
    struct Snapshot: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let complete: Bool
        let checkedAt: String
        let revision: String
        let sourceStatus: SourceStatus
        let fixtures: [Fixture]
        let coverage: [Coverage]
        var receiptDate: Date? { SportsFixtureCatalog.date(checkedAt) }
    }
    enum ValidationError: Error { case header, receipt, fixture, coverage, size }

    static func date(_ value: String) -> Date? {
        guard value.range(of: #"(?:Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else { return nil }
        return CatalogISO8601DateParser.date(value)
    }

    static func validatedSnapshot(from data: Data, now: Date = .init()) throws -> Snapshot {
        guard data.count <= maximumPayloadBytes else { throw ValidationError.size }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        guard snapshot.schemaVersion == 1, snapshot.complete,
              validText(snapshot.revision, maximum: 160), snapshot.fixtures.count <= maximumFixtures,
              !snapshot.coverage.isEmpty, snapshot.coverage.count <= 128 else { throw ValidationError.header }
        guard let receipt = snapshot.receiptDate, receipt <= now.addingTimeInterval(300),
              receipt >= now.addingTimeInterval(-30 * 86400) else { throw ValidationError.receipt }
        var coverageByKey: [String: Coverage] = [:]
        for coverage in snapshot.coverage {
            guard validIdentifier(coverage.sport), validIdentifier(coverage.competitionId),
                  validText(coverage.competitionName, maximum: 200), coverageByKey[coverage.competitionKey] == nil,
                  (0...maximumFixtures).contains(coverage.fixtureCount), (0...10_000).contains(coverage.pendingFixtureCount),
                  coverage.nextStart.map({ date($0) != nil }) ?? true else { throw ValidationError.coverage }
            if let checked = coverage.checkedAt {
                guard let observed = date(checked), observed <= receipt.addingTimeInterval(300),
                      observed >= now.addingTimeInterval(-30 * 86400) else { throw ValidationError.coverage }
            } else if coverage.status == .covered || coverage.fixtureCount > 0 { throw ValidationError.coverage }
            coverageByKey[coverage.competitionKey] = coverage
        }
        var ids = Set<String>()
        var identities = Set<String>()
        for fixture in snapshot.fixtures {
            guard validText(fixture.id, maximum: 200), fixture.id.hasPrefix(fixtureIDPrefix + fixture.competitionId + ":"),
                  ids.insert(fixture.id).inserted, validIdentifier(fixture.sport), validIdentifier(fixture.competitionId),
                  let coverage = coverageByKey[fixture.competitionKey], coverage.status != .unsupported,
                  validText(fixture.title, maximum: 300), validText(fixture.competitionName, maximum: 200),
                  fixture.competitionName == coverage.competitionName,
                  fixture.participants.count <= 100, fixture.eventKind != .match || fixture.participants.count == 2,
                  validText(fixture.squad.ageGroup, maximum: 40),
                  let kickoff = fixture.kickoff, kickoff >= now.addingTimeInterval(-30 * 86400),
                  kickoff <= now.addingTimeInterval(90 * 86400), validText(fixture.source.name, maximum: 100),
                  let url = URL(string: fixture.source.url), url.scheme == "https", url.host != nil,
                  url.user == nil, url.password == nil,
                  let observed = date(fixture.source.observedAt), observed <= receipt.addingTimeInterval(300),
                  observed >= now.addingTimeInterval(-30 * 86400),
                  (coverage.status == .unavailable && fixture.source.verification != nil)
                    || coverage.checkedAt == fixture.source.observedAt,
                  fixture.source.updatedAt.map({ date($0).map { $0 <= receipt.addingTimeInterval(300) } ?? false }) ?? true,
                  fixture.source.correctionConfirmedAt.map({ date($0).map { $0 <= observed } ?? false }) ?? true
            else { throw ValidationError.fixture }
            guard fixture.source.verification != .held || coverage.status == .unavailable else { throw ValidationError.fixture }
            var participantIDs = Set<String>()
            var names = Set<String>()
            for participant in fixture.participants {
                guard validText(participant.id, maximum: 120), participantIDs.insert(participant.id).inserted,
                      validParticipantName(participant.name), names.insert(nameKey(participant.name)).inserted,
                      participant.role.map({ validText($0, maximum: 40) }) ?? true else { throw ValidationError.fixture }
            }
            let titleIdentity = fixture.eventKind == .match ? "" : nameKey(fixture.title)
            let identity = "\(fixture.competitionKey)|\(fixture.eventKind.rawValue)|"
                + "\(kickoff.timeIntervalSince1970)|\(fixture.participants.map(\.id).joined(separator: ","))|"
                + "\(fixture.squad.gender.rawValue)|\(fixture.squad.ageGroup)|\(titleIdentity)"
            guard identities.insert(identity).inserted else { throw ValidationError.fixture }
        }
        for coverage in snapshot.coverage {
            let count = snapshot.fixtures.filter { $0.competitionKey == coverage.competitionKey }.count
            guard count == coverage.fixtureCount, coverage.status != .unsupported || count == 0 else { throw ValidationError.coverage }
        }
        return snapshot
    }

    /// Keep each failed, missing, replayed or contradictory lane's accepted
    /// facts and receipt; an aggregate check is never a competition receipt.
    static func accepting(_ candidate: Snapshot, over cached: Snapshot?) -> Snapshot {
        guard let cached else { return candidate }
        guard candidate.sourceStatus.verifiesCurrentRows else { return cached }
        let oldCoverage = Dictionary(uniqueKeysWithValues: cached.coverage.map { ($0.competitionKey, $0) })
        let oldFixtures = Dictionary(grouping: cached.fixtures, by: \.competitionKey)
        let newFixtures = Dictionary(grouping: candidate.fixtures, by: \.competitionKey)
        var fixtures: [Fixture] = []
        var coverage: [Coverage] = []
        let incoming = Dictionary(uniqueKeysWithValues: candidate.coverage.map { ($0.competitionKey, $0) })
        for key in Set(oldCoverage.keys).union(incoming.keys).sorted() {
            let next = incoming[key]
            let previous = oldCoverage[key]
            let oldRows = oldFixtures[key] ?? []
            let nextRows = newFixtures[key] ?? []
            let oldByID = Dictionary(uniqueKeysWithValues: oldRows.map { ($0.id, $0) })
            func admits(_ row: Fixture) -> Bool {
                guard let old = oldByID[row.id] else {
                    return (date(row.source.observedAt) ?? .distantPast) >= (previous?.receiptDate ?? .distantPast)
                }
                guard old.sport == row.sport, old.competitionId == row.competitionId,
                      (date(row.source.observedAt) ?? .distantPast) >= (date(old.source.observedAt) ?? .distantPast),
                      !([Status.finished, .cancelled].contains(old.status) && ![Status.finished, .cancelled].contains(row.status)) else { return false }
                let sameIdentity = old.eventKind == row.eventKind && sameParticipantIdentity(old.participants, row.participants)
                    && old.squad == row.squad
                let labelsChanged = old.participants != row.participants || old.title != row.title
                let laterReceipt = (date(row.source.observedAt) ?? .distantPast)
                    > (date(old.source.observedAt) ?? .distantFuture)
                let confirmedCorrection = row.source.correctionConfirmedAt.flatMap(date).map {
                    $0 <= (date(row.source.observedAt) ?? .distantPast)
                        && $0 > (date(old.source.observedAt) ?? .distantFuture)
                } ?? false
                let schedulingCorrection = old.start != row.start || (old.status == .live && row.status == .scheduled)
                guard !schedulingCorrection || confirmedCorrection,
                      old.status == row.status || laterReceipt else { return false }
                return (sameIdentity && (!labelsChanged || laterReceipt)) || confirmedCorrection
            }
            let identitiesAgree = nextRows.allSatisfy(admits)
            let watermark = max(previous?.receiptDate ?? .distantPast,
                                oldRows.compactMap { date($0.source.observedAt) }.max() ?? .distantPast)
            let advances = next?.status == .covered && identitiesAgree
                && (next?.receiptDate ?? .distantPast) >= watermark
            if advances, let next { coverage.append(next); fixtures += nextRows }
            else if let next, next.status == .unavailable,
                    nextRows.contains(where: { $0.source.verification != nil }) {
                // An isolated response may advance strictly admitted rows while
                // retaining disputed records and the last complete lane receipt.
                var rows = Dictionary(uniqueKeysWithValues: oldRows.map { ($0.id, held($0)) })
                for row in nextRows {
                    if row.source.verification == .verified, admits(row) { rows[row.id] = row }
                    else if row.source.verification == .held, oldByID[row.id] == nil { rows[row.id] = row }
                    else if row.source.verification == .held, let old = oldByID[row.id], row == held(old, markLegacy: true) {
                        rows[row.id] = row
                    }
                }
                let retained = rows.values.sorted { $0.id < $1.id }
                let checkedAt = (previous?.receiptDate ?? .distantPast) > (next.receiptDate ?? .distantPast)
                    ? previous?.checkedAt : next.checkedAt
                coverage.append(.init(sport: next.sport, competitionId: next.competitionId,
                    competitionName: next.competitionName, status: .unavailable, checkedAt: checkedAt,
                    fixtureCount: retained.count, pendingFixtureCount: next.pendingFixtureCount, nextStart: next.nextStart))
                fixtures += retained
            }
            else if let next, next.status == .unsupported, nextRows.isEmpty, oldRows.isEmpty {
                // A lane the server does not cover is not a failed read.
                coverage.append(next)
            }
            else if let previous {
                // Failure changes availability, never the last accepted time or
                // the accepted facts (owner decision, 21 Nov 2026).
                let failed = next == nil || next?.status != .covered || !identitiesAgree
                coverage.append(.init(sport: previous.sport, competitionId: previous.competitionId,
                    competitionName: previous.competitionName, status: failed ? .unavailable : previous.status,
                    checkedAt: previous.checkedAt, fixtureCount: oldRows.count,
                    pendingFixtureCount: previous.pendingFixtureCount, nextStart: previous.nextStart))
                fixtures += failed ? oldRows.map(retained) : oldRows
            } else if let next { coverage.append(next); fixtures += nextRows }
        }
        // The cache union is bounded just like a transported snapshot.
        guard fixtures.count <= maximumFixtures else { return cached }
        let checkedAt = (cached.receiptDate ?? .distantPast) > (candidate.receiptDate ?? .distantPast)
            ? cached.checkedAt : candidate.checkedAt
        return .init(schemaVersion: 1, complete: true, checkedAt: checkedAt, revision: candidate.revision,
                     sourceStatus: coverage.contains(where: { $0.status == .unavailable }) ? .partial : candidate.sourceStatus,
                     fixtures: fixtures, coverage: coverage)
    }

    /// Why each league in `accepted` is unavailable after reading `candidate`
    /// (competition ID → reason code). Diagnostics only: no names or URLs.
    static func laneFailures(candidate: Snapshot, accepted: Snapshot) -> [String: String] {
        let incoming = Dictionary(candidate.coverage.map { ($0.competitionKey, $0) }, uniquingKeysWith: { first, _ in first })
        var failures: [String: String] = [:]
        for lane in accepted.coverage where lane.status == .unavailable {
            guard let next = incoming[lane.competitionKey] else { failures[lane.competitionId] = "missing"; continue }
            switch next.status {
            case .covered:
                failures[lane.competitionId] = (next.receiptDate ?? .distantPast) < (lane.receiptDate ?? .distantPast)
                    ? "older_receipt" : "rows_disagree"
            case .unavailable: failures[lane.competitionId] = "server_unavailable"
            case .unsupported: failures[lane.competitionId] = "server_unsupported"
            }
        }
        return failures
    }

    /// A row explicitly verified by an earlier read keeps its facts after a
    /// failed read, marked so its live score is not re-presented as current.
    private static func retained(_ fixture: Fixture) -> Fixture {
        guard fixture.source.verification == .verified else { return fixture }
        let source = Source(name: fixture.source.name, url: fixture.source.url, observedAt: fixture.source.observedAt,
                            updatedAt: fixture.source.updatedAt, correctionConfirmedAt: fixture.source.correctionConfirmedAt,
                            verification: .retained)
        return Fixture(id: fixture.id, sport: fixture.sport, start: fixture.start, status: fixture.status,
                       eventKind: fixture.eventKind, title: fixture.title, competitionId: fixture.competitionId,
                       competitionName: fixture.competitionName, participants: fixture.participants,
                       squad: fixture.squad, source: source, reportedScore: fixture.reportedScore, footballLive: fixture.footballLive)
    }

    private static func held(_ fixture: Fixture, markLegacy: Bool = false) -> Fixture {
        // Legacy observations stay legacy; new row receipts are explicitly
        // demoted when retained without admission by this response.
        guard markLegacy || fixture.source.verification != nil else { return fixture }
        var source = fixture.source
        source = Source(name: source.name, url: source.url, observedAt: source.observedAt,
                        updatedAt: source.updatedAt, correctionConfirmedAt: source.correctionConfirmedAt,
                        verification: .held)
        return Fixture(id: fixture.id, sport: fixture.sport, start: fixture.start, status: fixture.status,
                       eventKind: fixture.eventKind, title: fixture.title, competitionId: fixture.competitionId,
                       competitionName: fixture.competitionName, participants: fixture.participants,
                       squad: fixture.squad, source: source, reportedScore: fixture.reportedScore, footballLive: fixture.footballLive)
    }

    static func pollingInterval(snapshot: Snapshot?, now: Date) -> TimeInterval {
        guard let snapshot, snapshot.sourceStatus.verifiesCurrentRows,
              !snapshot.coverage.contains(where: { $0.status == .unavailable }) else { return SportsFixtureUpdater.retryInterval }
        for fixture in snapshot.fixtures where !fixture.status.stopsPlayback {
            guard let kickoff = fixture.kickoff else { continue }
            let age = now.timeIntervalSince(kickoff)
            // Matches in play follow the server's five-minute refresh closely.
            if fixture.status == .live || (-600...3 * 3600).contains(age) { return 2 * 60 }
            if (-1800...12 * 3600).contains(age) { return 5 * 60 }
            if (-24 * 3600..<0).contains(age) { return 15 * 60 }
        }
        return 4 * 3600
    }

    static func nameKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "&", with: " and ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    static func sameParticipantIdentity(_ lhs: [Participant], _ rhs: [Participant]) -> Bool {
        lhs.map { "\($0.id)|\($0.role ?? "")" }.sorted() == rhs.map { "\($0.id)|\($0.role ?? "")" }.sorted()
    }
    private static func orderedParticipants(_ participants: [Participant]) -> [Participant] {
        if participants.count == 2, let home = participants.first(where: { $0.role == "home" }),
           let away = participants.first(where: { $0.role == "away" }) { return [home, away] }
        return participants
    }
    private static func validText(_ value: String, maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= maximum
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
    private static func validIdentifier(_ value: String) -> Bool {
        validText(value, maximum: 100) && value.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil
    }
    private static func validParticipantName(_ value: String) -> Bool {
        validText(value, maximum: 120) && !["home", "away", "tbd", "tbc", "unknown", "teams to be confirmed"].contains(nameKey(value))
    }

    @MainActor
    static func providerMatches(_ event: EventReference, fixture: SportsFixtureMetadata, kickoff: Date?,
                                allowUnmarkedLeague: Bool = false, admittingUnmarkedLeague: Bool = false) -> Bool {
        guard !event.hasCatalogIdentityConflict, !event.isBroadcastChannel, event.normalizedCategory == fixture.sport,
              let kickoff, event.kickoffDate.map({ abs($0.timeIntervalSince(kickoff)) <= kickoffTolerance }) == true else { return false }
        if let metadata = event.sportsFixture {
            return metadata.fixtureID == fixture.fixtureID
                && metadata.competitionID == fixture.competitionID && metadata.eventKind == fixture.eventKind
                && sameParticipantIdentity(metadata.participants, fixture.participants) && metadata.squad == fixture.squad
                && (fixture.eventKind == .match || nameKey(metadata.title) == nameKey(fixture.title))
        }
        // An explicit competition category or delimited prefix is evidence;
        // roster membership and loose title substrings are not.
        let category = nameKey(event.category ?? "")
        let prefix = (event.title ?? "").components(separatedBy: " · ").first ?? ""
        if let competitionID = event.competitionID, competitionID != fixture.competitionID { return false }
        let explicitCategories: Set<String> = ["nba", "wnba", "mlb", "nhl", "nfl", "atp", "wta", "f1", "pga", "ufc"]
        if explicitCategories.contains(category), category != nameKey(fixture.competitionID) { return false }
        if (event.title ?? "").contains(" · "), nameKey(prefix) != nameKey(fixture.competitionName) { return false }
        let explicitLeague = event.competitionID == fixture.competitionID
            || category == nameKey(fixture.competitionID) || nameKey(prefix) == nameKey(fixture.competitionName)
        let footballCompetitions: Set<String> = ["premier-league", "champions-league", "la-liga", "serie-a", "bundesliga", "ligue-1"]
        let reviewedCup = fixture.sport == "football" && fixture.competitionID == "carabao-cup"
        let reviewedFootball = fixture.sport == "football" && (footballCompetitions.contains(fixture.competitionID) || reviewedCup)
        let evidence = [event.id, event.title ?? "", event.category ?? ""]
        let evidenceKey = nameKey(evidence.joined(separator: " "))
        if reviewedFootball {
            // Cup facts must not absorb a league broadcast (or vice versa).
            // The reviewed Cup lane admits its own markers, never every cup or
            // shared PL roster. Its authority comes from the current receipt.
            if reviewedCup {
                guard fixture.verified, fixture.squad == Squad(gender: .men, ageGroup: "senior") else { return false }
            }
            let conflicts = reviewedCup
                ? ["premier league", "champions league", "uefa champions", "la liga", "laliga", "serie a", "bundesliga", "ligue 1",
                   "fa cup", "community shield", "championship", "europa", "conference", "friendly"]
                : ["fa cup", "efl cup", "league cup", "carabao", "community shield", "championship",
                   "premier league 2", "premier league cup", "europa", "conference", "friendly"]
            guard !conflicts.contains(where: { evidenceKey.contains($0) }) else { return false }
            if reviewedCup {
                let tokens = Set(evidenceKey.split(separator: " ").map(String.init))
                guard tokens.isDisjoint(with: ["epl", "ucl"]) else { return false }
            }
        }
        if !explicitLeague {
            // The merge owner checks every admitted fixture for uniqueness.
            // Football also needs both reviewed senior club identities and an
            // exact official start, not roster-only competition inference.
            guard allowUnmarkedLeague, fixture.verified,
                  ["mlb", "nhl"].contains(fixture.competitionID) || reviewedFootball,
                  fixture.squad == Squad(gender: .men, ageGroup: "senior"),
                  event.kickoffDate == kickoff else { return false }
            if reviewedFootball {
                // Only an admitting caller may establish an unmarked football
                // identity, and only between reviewed senior clubs.
                guard admittingUnmarkedLeague,
                      FootballCompetitionCatalog.canonicalClubID(for: event.homeName) != nil,
                      FootballCompetitionCatalog.canonicalClubID(for: event.awayName) != nil,
                      fixture.participants.allSatisfy({ FootballCompetitionCatalog.canonicalClubID(for: $0.name) != nil }) else { return false }
            } else {
                let leagueTokens = Set(evidenceKey.split(separator: " ").map(String.init))
                let conflicting = fixture.sport == "baseball" ? ["npb", "kbo"] : ["khl", "ahl"]
                guard !conflicting.contains(where: leagueTokens.contains) else { return false }
            }
        }
        // Sessions, tournaments and fight cards cannot use a two-team fallback.
        guard fixture.eventKind == .match, fixture.participants.count == 2 else { return false }
        func participantKey(_ name: String) -> String {
            if fixture.sport == "football", let club = FootballCompetitionCatalog.canonicalClubID(for: name) {
                return "football:\(club)"
            }
            return SportsTeamIdentity.known(name: name, category: fixture.sport)?.id ?? nameKey(name)
        }
        let participants = orderedParticipants(fixture.participants)
        guard participantKey(event.homeName) == participantKey(participants[0].name),
              participantKey(event.awayName) == participantKey(participants[1].name) else { return false }
        var squadEvidence = [event.homeName, event.awayName, event.title ?? ""]
        if fixture.sport == "football" { squadEvidence.append(event.id) }
        let text = nameKey(squadEvidence.joined(separator: " "))
        let hasWomen = text.range(of: #"\b(?:women|womens|ladies)\b"#, options: .regularExpression) != nil
        let hasMen = text.range(of: #"\b(?:men|mens)\b"#, options: .regularExpression) != nil
        let hasYouth = text.range(of: #"\b(?:u\s?\d{1,2}|under\s?\d{1,2}|youth|academy|reserves?)\b"#, options: .regularExpression) != nil
        let hasCollege = text.range(of: #"\bcollege\b"#, options: .regularExpression) != nil
        let collegeCohorts: [String: Squad.Gender] = ["college-football": .men,
            "college-basketball-men": .men, "college-basketball-women": .women]
        let reviewedCollege = collegeCohorts[fixture.competitionID]
        if let reviewedCollege, fixture.squad.ageGroup != "college" || fixture.squad.gender != reviewedCollege { return false }
        let ageMatches: Bool
        switch fixture.squad.ageGroup {
        case "senior": ageMatches = !hasYouth && !hasCollege
        case "college": ageMatches = !hasYouth && (hasCollege || reviewedCollege != nil)
        default: ageMatches = text.contains(nameKey(fixture.squad.ageGroup))
        }
        guard fixture.squad.gender != .unknown, fixture.squad.ageGroup != "unknown",
              fixture.squad.gender != .mixed,
              !(fixture.squad.gender == .women && hasMen),
              (fixture.squad.gender == .women) == (hasWomen || ["wnba", "wta", "college-basketball-women"].contains(fixture.competitionID)),
              ageMatches else { return false }
        return true
    }

    @MainActor
    static func upcomingSearchEvents(from snapshot: Snapshot?, at now: Date) -> [EventReference] {
        guard let snapshot, snapshot.sourceStatus.verifiesCurrentRows,
              SportsSearchSchedule.isFresh(snapshot.receiptDate, at: now) else { return [] }
        let latest = now.addingTimeInterval(SportsSearchSchedule.futureHorizon)
        return snapshot.fixtures.compactMap { fixture in
            guard fixture.sport != "cricket", fixture.status == .scheduled,
                  let kickoff = fixture.kickoff, kickoff > now, kickoff <= latest,
                  fixture.eventKind != .match || fixture.participants.count == 2,
                  let coverage = snapshot.coverage.first(where: { $0.competitionKey == fixture.competitionKey }),
                  coverage.status == .covered,
                  SportsSearchSchedule.isFresh(coverage.receiptDate, at: now) else { return nil }
            let metadata = fixtureMetadata(for: fixture, in: snapshot, at: now)
            // A publisher's last-change timestamp need not advance for an
            // unchanged future fixture. Require a fresh observation receipt;
            // retain the stricter metadata clock used for current LIVE claims.
            guard metadata.verified,
                  SportsSearchSchedule.isFresh(date(fixture.source.observedAt), at: now) else { return nil }
            return projectedEvent(for: fixture, metadata: metadata, kickoff: kickoff)
        }
    }

    @MainActor
    static func terminalEvents(from snapshot: Snapshot?) -> [EventReference] {
        guard let snapshot, snapshot.sourceStatus.verifiesCurrentRows else { return [] }
        return snapshot.fixtures.compactMap { fixture in
            guard fixture.sport != "cricket", fixture.status == .finished || fixture.status == .cancelled,
                  let kickoff = fixture.kickoff,
                  fixture.eventKind != .match || fixture.participants.count == 2 else { return nil }
            let metadata = fixtureMetadata(for: fixture, in: snapshot)
            // An unavailable cohort cannot turn retained rows into new terminal
            // evidence. These facts reconcile saves, never advertise playback.
            guard metadata.verified else { return nil }
            return projectedEvent(for: fixture, metadata: metadata, kickoff: kickoff)
        }
    }

    @MainActor
    /// Home rows plus the schedule's current fixtures. Earlier projections of
    /// this schedule are replaced; other rows (CPL, cricket) pass through.
    static func merging(into catalog: [EventReference], snapshot: Snapshot?, at now: Date = .init()) -> [EventReference] {
        let remaining = catalog.filter { !$0.id.hasPrefix(fixtureIDPrefix) }
        guard let snapshot else { return remaining }
        let projected = snapshot.fixtures.compactMap { fixture -> EventReference? in
            guard fixture.sport != "cricket", let kickoff = fixture.kickoff,
                  fixture.eventKind != .match || fixture.participants.count == 2,
                  fixture.status != .finished, fixture.status != .cancelled,
                  kickoff >= now.addingTimeInterval(-14 * 86400),
                  kickoff <= now.addingTimeInterval(CatalogTimingPolicy.retentionFutureHorizon) else { return nil }
            return projectedEvent(for: fixture, metadata: fixtureMetadata(for: fixture, in: snapshot, at: now), kickoff: kickoff)
        }
        return remaining + projected
    }

    private static func fixtureMetadata(for fixture: Fixture, in snapshot: Snapshot,
                                        at now: Date = .init()) -> SportsFixtureMetadata {
        let laneCoverage = snapshot.coverage.first { $0.competitionKey == fixture.competitionKey }
        // A league whose latest read failed keeps its last confirmed scheduled
        // and live facts within `confirmationGrace` of its last accepted read.
        let retained = laneCoverage?.status == .unavailable && fixture.source.verification != .held
            && (fixture.status == .scheduled || fixture.status == .live)
            && laneCoverage?.receiptDate.map { (-300...confirmationGrace).contains(now.timeIntervalSince($0)) } == true
        let covered = laneCoverage?.status == .covered || retained
        let identityObservedAt = date(fixture.source.observedAt) ?? .distantPast
        let observedAt = min(identityObservedAt, fixture.source.updatedAt.flatMap(date) ?? .distantFuture)
        let freshVerifiedRow = fixture.source.verification == .verified
            && (-300...statusFreshness).contains(now.timeIntervalSince(identityObservedAt))
        let verifiedRow = fixture.source.verification == .verified && (covered || freshVerifiedRow)
        // A row kept through a failed read stays confirmed, but its score and
        // minute are never shown again until a current read supplies them.
        let liveFactsCurrent = laneCoverage?.status == .covered || freshVerifiedRow
        let footballLive = liveFactsCurrent ? fixture.footballLive : nil
        let reportedScore = liveFactsCurrent ? fixture.reportedScore : nil
        let sport = ["motor-sports", "motorsports"].contains(fixture.sport) ? "motorsport" : fixture.sport
        return SportsFixtureMetadata(fixtureID: fixture.id, sport: sport,
            competitionID: fixture.competitionId, competitionName: fixture.competitionName,
            eventKind: fixture.eventKind, title: fixture.title, participants: fixture.participants, squad: fixture.squad,
            status: fixture.status, observedAt: observedAt,
            verified: (verifiedRow || ((fixture.source.verification == nil || fixture.source.verification == .retained) && covered))
                && snapshot.sourceStatus.verifiesCurrentRows, reportedScore: reportedScore,
            reportedScoreObservedAt: reportedScore == nil ? nil : date(fixture.source.observedAt),
            identityObservedAt: identityObservedAt, footballLive: footballLive,
            footballLiveMayBeDelayed: footballLive != nil && fixture.source.name == "football-data.org")
    }

    @MainActor
    private static func projectedEvent(for fixture: Fixture, metadata: SportsFixtureMetadata, kickoff: Date) -> EventReference {
        let participants = orderedParticipants(fixture.participants)
        let teams: NexusATeams? = fixture.eventKind == .match ? .init(
            home: .init(name: participants[0].name, badge: nil),
            away: .init(name: participants[1].name, badge: nil)) : nil
        return .init(id: fixture.id, title: fixture.title, category: fixture.sport,
            date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: false, teams: teams, sportsFixture: metadata, competitionID: fixture.competitionId)
    }
}

/// The publisher may have goals, an explicit match clock, or both.
struct FootballFixtureLive: Codable, Equatable, Sendable {
    let home: Int?
    let away: Int?
    let clock: String?

    init?(home: Int?, away: Int?, clock: String?) {
        if let home, let away, (0...99).contains(home), (0...99).contains(away) {
            self.home = home
            self.away = away
        } else {
            self.home = nil
            self.away = nil
        }
        self.clock = clock.flatMap(Self.validatedClock)
        guard self.home != nil || self.clock != nil else { return nil }
    }

    private enum CodingKeys: String, CodingKey { case home, away, clock }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let live = Self(home: try? values.decode(Int.self, forKey: .home),
                              away: try? values.decode(Int.self, forKey: .away),
                              clock: try? values.decode(String.self, forKey: .clock)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Empty football score and clock"))
        }
        self = live
    }

    private static func validatedClock(_ value: String) -> String? {
        if ["HT", "ET", "PEN"].contains(value) { return value }
        guard value.utf8.count <= 10, value.last == "′" else { return nil }
        let numbers = value.dropLast().split(separator: "+", omittingEmptySubsequences: false)
        guard (1...2).contains(numbers.count), let minute = Int(numbers[0]), (0...150).contains(minute),
              String(minute) == String(numbers[0]) else { return nil }
        if numbers.count == 2 {
            guard let added = Int(numbers[1]), (1...99).contains(added), String(added) == String(numbers[1]) else { return nil }
        }
        return value
    }

    func validated(sport: String, status: SportsFixtureCatalog.Status, kind: SportsFixtureCatalog.EventKind,
                   participants: [SportsFixtureCatalog.Participant]) -> Self? {
        guard sport == "football", status == .live, kind == .match, participants.count == 2,
              participants.contains(where: { $0.role == "home" }), participants.contains(where: { $0.role == "away" }) else { return nil }
        return self
    }
}

struct SportsFixtureMetadata: Codable, Equatable, Sendable {
    let fixtureID: String
    let sport: String
    let competitionID: String
    let competitionName: String
    let eventKind: SportsFixtureCatalog.EventKind
    let title: String
    let participants: [SportsFixtureCatalog.Participant]
    let squad: SportsFixtureCatalog.Squad
    let status: SportsFixtureCatalog.Status
    let observedAt: Date
    let verified: Bool
    let reportedScore: UCLReportedScore?
    let reportedScoreObservedAt: Date?
    let footballLive: FootballFixtureLive?
    let footballLiveMayBeDelayed: Bool?
    /// Successful verification of fixture identity is independent of the
    /// publisher's last status change. It never upgrades LIVE/terminal status.
    let identityObservedAt: Date?
    var identityReceipt: Date { identityObservedAt ?? observedAt }

    private enum CodingKeys: String, CodingKey {
        case fixtureID, sport, competitionID, competitionName, eventKind, title, participants, squad, status
        case observedAt, verified, reportedScore, reportedScoreObservedAt, identityObservedAt, footballLive, footballLiveMayBeDelayed
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fixtureID = try values.decode(String.self, forKey: .fixtureID)
        sport = try values.decode(String.self, forKey: .sport)
        competitionID = try values.decode(String.self, forKey: .competitionID)
        competitionName = try values.decode(String.self, forKey: .competitionName)
        eventKind = try values.decode(SportsFixtureCatalog.EventKind.self, forKey: .eventKind)
        title = try values.decode(String.self, forKey: .title)
        participants = try values.decode([SportsFixtureCatalog.Participant].self, forKey: .participants)
        squad = try values.decode(SportsFixtureCatalog.Squad.self, forKey: .squad)
        status = try values.decode(SportsFixtureCatalog.Status.self, forKey: .status)
        observedAt = try values.decode(Date.self, forKey: .observedAt)
        identityObservedAt = try values.decodeIfPresent(Date.self, forKey: .identityObservedAt)
        verified = try values.decode(Bool.self, forKey: .verified)
        let candidate = try? values.decode(UCLReportedScore.self, forKey: .reportedScore)
        reportedScore = candidate?.isWellFormed == true ? candidate : nil
        footballLiveMayBeDelayed = try? values.decode(Bool.self, forKey: .footballLiveMayBeDelayed)
        reportedScoreObservedAt = try? values.decode(Date.self, forKey: .reportedScoreObservedAt)
        let live = try? values.decode(FootballFixtureLive.self, forKey: .footballLive)
        footballLive = live?.validated(sport: sport, status: status, kind: eventKind, participants: participants)
    }

    init(fixtureID: String, sport: String, competitionID: String, competitionName: String,
         eventKind: SportsFixtureCatalog.EventKind, title: String, participants: [SportsFixtureCatalog.Participant],
         squad: SportsFixtureCatalog.Squad, status: SportsFixtureCatalog.Status, observedAt: Date, verified: Bool,
         reportedScore: UCLReportedScore? = nil, reportedScoreObservedAt: Date? = nil, identityObservedAt: Date? = nil,
         footballLive: FootballFixtureLive? = nil, footballLiveMayBeDelayed: Bool = false) {
        self.fixtureID = fixtureID; self.sport = sport; self.competitionID = competitionID; self.competitionName = competitionName
        self.eventKind = eventKind; self.title = title; self.participants = participants; self.squad = squad
        self.status = status; self.observedAt = observedAt; self.verified = verified
        self.reportedScore = reportedScore; self.reportedScoreObservedAt = reportedScoreObservedAt
        self.identityObservedAt = identityObservedAt
        self.footballLiveMayBeDelayed = footballLiveMayBeDelayed ? true : nil
        self.footballLive = footballLive?.validated(sport: sport, status: status, kind: eventKind, participants: participants)
    }
    func isLive(at now: Date) -> Bool {
        verified && status == .live && (-300...SportsFixtureCatalog.statusFreshness).contains(now.timeIntervalSince(observedAt))
    }
    /// Owner decision (21 Nov 2026): a match confirmed LIVE after kickoff stays
    /// in play until three hours after kickoff unless a newer fact ends it. A
    /// missed refresh must not drop it to "Start unconfirmed". Score and minute
    /// display still require the fresh `isLive` receipt.
    static let confirmedInPlayWindow: TimeInterval = 3 * 3600
    func isInPlay(at now: Date, kickoff: Date?) -> Bool {
        if isLive(at: now) { return true }
        guard let kickoff, verified, status == .live, observedAt >= kickoff.addingTimeInterval(-300) else { return false }
        return (0..<Self.confirmedInPlayWindow).contains(now.timeIntervalSince(kickoff))
    }
    /// A verified LIVE receipt that aged past `statusFreshness` without any
    /// newer status (for example one failed fixture refresh mid-match). It is
    /// never displayed as confirmed LIVE, but it keeps the fixture eligible for
    /// an exact source lookup until the generic four-hour broadcast window
    /// from kickoff ends. A terminal receipt still wins immediately.
    static let unconfirmedLiveWindow: TimeInterval = 4 * 3600
    func isUnconfirmedLive(at now: Date, kickoff: Date) -> Bool {
        // The LIVE fact itself must postdate kickoff (5 min skew): an early
        // publisher status is not evidence that this match is under way.
        verified && status == .live && !isLive(at: now)
            && observedAt >= kickoff.addingTimeInterval(-300)
            && now.timeIntervalSince(observedAt) > SportsFixtureCatalog.statusFreshness
            && (0..<Self.unconfirmedLiveWindow).contains(now.timeIntervalSince(kickoff))
    }
}

@MainActor
final class SportsFixtureUpdater {
    static let shared = SportsFixtureUpdater()
    private static let cacheKey = "Fotty.SportsFixtures.lastKnownGood.v1"
    private let defaults: UserDefaults
    private let fetch: (URLRequest) async throws -> (Data, URLResponse)
    private var lastAttempt: Date?
    private var retryAt: Date?
    private var isRefreshing = false
    /// The app's own ESPN live layer for leagues whose server read is stale or
    /// failed during a live window (owner decision, 21 Nov 2026).
    private let liveFallbackEnabled: Bool
    private var isFetchingFallback = false
    private var fallbackReads: [String: SportsFixtureCatalog.LiveFallback.Read] = [:]
    private var lastFallbackResults: [String: String] = [:]
    init(defaults: UserDefaults = .standard,
         fetch: @escaping (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) },
         liveFallbackEnabled: Bool = !AppRuntime.isAutomatedTesting) {
        self.defaults = defaults; self.fetch = fetch; self.liveFallbackEnabled = liveFallbackEnabled
    }
    /// A failed or partial read is retried within this interval; Home and the
    /// viewing session call `refresh` every 90 s, which honours it.
    static let retryInterval: TimeInterval = 5 * 60
    private var lastLaneFailures: [String: String] = [:]
    private var recordsDiagnostics: Bool { !AppRuntime.isAutomatedTesting }

    /// One receipt per failed read and per league whose failure starts or
    /// changes reason, so the 250-record buffer is never flooded. Competition
    /// IDs and reason codes only.
    private func recordOutcome(result: String, failures: [String: String]?, serverStatus: String?) {
        guard recordsDiagnostics else { return }
        let store = FottyQualityStore.shared
        if result != "accepted" || failures?.isEmpty == false {
            var details = ["feed": "sports_fixtures", "result": result,
                           "source_count": String(failures?.count ?? 0)]
            if let serverStatus { details["mode"] = serverStatus }
            store.record(category: .footballData, name: "sports_fixture_refresh",
                         outcome: result == "accepted" ? .info : .failure, details: details)
        }
        guard let failures else { return }
        for (competition, reason) in failures.sorted(by: { $0.key < $1.key }) where lastLaneFailures[competition] != reason {
            store.record(category: .footballData, name: "sports_lane_unavailable", outcome: .failure,
                         details: ["feed": "sports_fixtures", "source": competition, "reason_code": reason])
        }
        for competition in lastLaneFailures.keys where failures[competition] == nil {
            store.record(category: .footballData, name: "sports_lane_recovered", outcome: .recovered,
                         details: ["feed": "sports_fixtures", "source": competition])
        }
        lastLaneFailures = failures
    }

    func cachedSnapshot(now: Date = .init()) -> SportsFixtureCatalog.Snapshot? {
        guard let data = defaults.data(forKey: Self.cacheKey) else { return nil }
        return try? SportsFixtureCatalog.validatedSnapshot(from: data, now: now)
    }
    func refresh(now: Date = .init(), force: Bool = false) async -> SportsFixtureCatalog.Snapshot? {
        let base = await refreshServerSnapshot(now: now, force: force)
        return await applyingLiveFallback(to: base, now: now)
    }

    /// Leagues whose server read is stale or failed while one of their matches
    /// is in its live window get ESPN's live status, score and minute. Only
    /// scheduled → live and live updates; never finished, cancelled or a new
    /// fixture. The result is never persisted as a server receipt.
    private func applyingLiveFallback(to snapshot: SportsFixtureCatalog.Snapshot?, now: Date) async -> SportsFixtureCatalog.Snapshot? {
        guard liveFallbackEnabled, let snapshot else { return snapshot }
        let leagues = SportsFixtureCatalog.LiveFallback.leaguesNeedingFallback(in: snapshot, at: now)
        fallbackReads = fallbackReads.filter { leagues.contains($0.key) }
        guard !leagues.isEmpty else { return snapshot }
        if !isFetchingFallback {
            isFetchingFallback = true
            defer { isFetchingFallback = false }
            for league in leagues.sorted() {
                if let read = fallbackReads[league], (0..<SportsFixtureCatalog.LiveFallback.readInterval).contains(now.timeIntervalSince(read.observedAt)) { continue }
                guard let url = SportsFixtureCatalog.LiveFallback.scoreboardURL(for: league, at: now) else { continue }
                var result = "applied"
                do {
                    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    let (data, response) = try await fetch(request)
                    try Task.checkCancellation()
                    guard (response as? HTTPURLResponse)?.statusCode == 200,
                          data.count <= SportsFixtureCatalog.LiveFallback.maximumPayloadBytes else { throw URLError(.badServerResponse) }
                    let events = try SportsFixtureCatalog.LiveFallback.events(from: data, league: league)
                    fallbackReads[league] = .init(events: events, observedAt: now)
                    if events.isEmpty { result = "none_in_play" }
                } catch {
                    if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { return snapshot }
                    fallbackReads[league] = .init(events: [], observedAt: now)
                    result = "failed"
                }
                if recordsDiagnostics, lastFallbackResults[league] != result {
                    FottyQualityStore.shared.record(category: .footballData, name: "sports_live_fallback",
                        outcome: result == "failed" ? .failure : .info,
                        details: ["feed": "espn", "source": league, "result": result])
                }
                lastFallbackResults[league] = result
            }
        }
        return SportsFixtureCatalog.LiveFallback.overlay(snapshot, reads: fallbackReads, at: now)
    }

    private func refreshServerSnapshot(now: Date, force: Bool) async -> SportsFixtureCatalog.Snapshot? {
        let cached = cachedSnapshot(now: now)
        guard !isRefreshing else { return cached }
        if !force {
            if let retryAt { if now < retryAt { return cached } }
            else if let lastAttempt,
                    (0..<SportsFixtureCatalog.pollingInterval(snapshot: cached, now: now)).contains(now.timeIntervalSince(lastAttempt)) { return cached }
        }
        guard let url = Config.footballProxyBaseURL?.appendingPathComponent("api/sports/fixtures") else { return cached }
        lastAttempt = now; isRefreshing = true
        defer { isRefreshing = false }
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 12)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await fetch(request)
            try Task.checkCancellation()
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let candidate = try SportsFixtureCatalog.validatedSnapshot(from: data, now: now)
            let accepted = SportsFixtureCatalog.accepting(candidate, over: cached)
            let rejected = cached.map { accepted == $0 && candidate != $0 } ?? false
            retryAt = !candidate.sourceStatus.verifiesCurrentRows || rejected || accepted.coverage.contains(where: { $0.status == .unavailable })
                ? now.addingTimeInterval(Self.retryInterval) : nil
            defaults.set(try JSONEncoder().encode(accepted), forKey: Self.cacheKey)
            recordOutcome(result: rejected ? "unchanged" : "accepted",
                          failures: SportsFixtureCatalog.laneFailures(candidate: candidate, accepted: accepted),
                          serverStatus: candidate.sourceStatus.rawValue)
            return accepted
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                lastAttempt = nil; retryAt = nil
            } else {
                retryAt = now.addingTimeInterval(Self.retryInterval)
                recordOutcome(result: error is SportsFixtureCatalog.ValidationError ? "invalid" : "failed",
                              failures: nil, serverStatus: nil)
            }
            return cached
        }
    }
}

// MARK: - App ESPN live layer (owner decision, 21 Nov 2026)

extension SportsFixtureCatalog {
    enum LiveFallback {
        struct Event: Equatable, Sendable {
            let kickoff: Date
            let homeNames: [String]
            let awayNames: [String]
            let homeScore: Int?
            let awayScore: Int?
            let clock: String?
        }
        struct Read: Equatable, Sendable {
            let events: [Event]
            let observedAt: Date
        }

        /// Fotty competition → ESPN soccer league slug.
        static let leagues: [String: String] = [
            "premier-league": "eng.1", "champions-league": "uefa.champions", "la-liga": "esp.1",
            "serie-a": "ita.1", "bundesliga": "ger.1", "ligue-1": "fra.1",
        ]
        static let readInterval: TimeInterval = 90
        static let maximumPayloadBytes = 1_500_000
        /// The server refreshes every five minutes; older than this is stale.
        static let staleLaneAge: TimeInterval = 12 * 60
        private static let teamNameNoise: Set<String> = ["fc", "cf", "ac", "as", "ss", "ssc", "sc", "us", "afc", "cd", "ud",
            "sd", "rcd", "rc", "club", "calcio", "de", "del", "la", "le", "sv", "vfl", "vfb", "tsg", "fsv", "bsc", "osc",
            "ogc", "fk", "sk", "rb", "stade"]

        static func leaguesNeedingFallback(in snapshot: Snapshot, at now: Date) -> Set<String> {
            var result = Set<String>()
            for lane in snapshot.coverage where lane.sport == "football" && leagues[lane.competitionId] != nil {
                let stale = lane.status != .covered
                    || (lane.receiptDate.map { now.timeIntervalSince($0) > staleLaneAge } ?? true)
                guard stale, snapshot.fixtures.contains(where: { candidate($0, lane: lane.competitionKey, at: now) }) else { continue }
                result.insert(lane.competitionId)
            }
            return result
        }

        private static func candidate(_ fixture: Fixture, lane: String, at now: Date) -> Bool {
            guard fixture.competitionKey == lane, fixture.eventKind == .match, fixture.source.verification != .held,
                  fixture.status == .scheduled || fixture.status == .live, let kickoff = fixture.kickoff else { return false }
            return kickoff <= now.addingTimeInterval(5 * 60) && kickoff >= now.addingTimeInterval(-3 * 3600)
        }

        static func scoreboardURL(for league: String, at now: Date) -> URL? {
            guard let slug = leagues[league] else { return nil }
            // ESPN pages follow the US Eastern calendar day.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
            let day = calendar.dateComponents([.year, .month, .day], from: now.addingTimeInterval(-5 * 3600))
            guard let year = day.year, let month = day.month, let date = day.day else { return nil }
            return URL(string: String(format: "https://site.api.espn.com/apis/site/v2/sports/soccer/%@/scoreboard?dates=%04d%02d%02d",
                                      slug, year, month, date))
        }

        static func events(from data: Data, league: String) throws -> [Event] {
            guard let slug = leagues[league],
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (root["leagues"] as? [[String: Any]])?.first?["slug"] as? String == slug,
                  let events = root["events"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
            return events.prefix(200).compactMap { event -> Event? in
                guard let status = event["status"] as? [String: Any], let type = status["type"] as? [String: Any],
                      type["state"] as? String == "in", type["completed"] as? Bool == false,
                      let kickoff = (event["date"] as? String).flatMap(espnDate),
                      let competition = (event["competitions"] as? [[String: Any]])?.first,
                      let competitors = competition["competitors"] as? [[String: Any]], competitors.count == 2,
                      let home = competitors.first(where: { $0["homeAway"] as? String == "home" }),
                      let away = competitors.first(where: { $0["homeAway"] as? String == "away" }) else { return nil }
                func names(_ side: [String: Any]) -> [String] {
                    let team = side["team"] as? [String: Any] ?? [:]
                    return ["displayName", "shortDisplayName", "name"].compactMap { team[$0] as? String }
                }
                func score(_ side: [String: Any]) -> Int? {
                    guard let text = side["score"] as? String, (1...2).contains(text.count), text.allSatisfy(\.isASCII) else { return nil }
                    return Int(text)
                }
                let homeNames = names(home), awayNames = names(away)
                guard !homeNames.isEmpty, !awayNames.isEmpty else { return nil }
                let clock = type["name"] as? String == "STATUS_HALFTIME" ? "HT"
                    : minute(status["displayClock"] as? String) ?? minute(type["shortDetail"] as? String)
                return Event(kickoff: kickoff, homeNames: homeNames, awayNames: awayNames,
                             homeScore: score(home), awayScore: score(away), clock: clock)
            }
        }

        /// Rows are updated only from a unique role-aligned match within five
        /// minutes of the official kickoff; anything ambiguous is left as is.
        static func overlay(_ snapshot: Snapshot, reads: [String: Read], at now: Date) -> Snapshot {
            var updates: [String: Fixture] = [:]
            for (league, read) in reads where (0..<staleLaneAge).contains(now.timeIntervalSince(read.observedAt)) {
                guard let lane = snapshot.coverage.first(where: { $0.sport == "football" && $0.competitionId == league }) else { continue }
                let rows = snapshot.fixtures.filter { candidate($0, lane: lane.competitionKey, at: now) }
                var pairs: [(event: Int, row: Int)] = []
                for (eventIndex, event) in read.events.enumerated() {
                    for (rowIndex, row) in rows.enumerated() {
                        let participants = orderedParticipants(row.participants)
                        guard participants.count == 2, participants[0].role == "home", participants[1].role == "away",
                              let kickoff = row.kickoff, abs(kickoff.timeIntervalSince(event.kickoff)) <= 5 * 60,
                              sameTeam([participants[0].name], event.homeNames),
                              sameTeam([participants[1].name], event.awayNames) else { continue }
                        pairs.append((eventIndex, rowIndex))
                    }
                }
                for pair in pairs where pairs.filter({ $0.event == pair.event || $0.row == pair.row }).count == 1 {
                    let row = rows[pair.row], event = read.events[pair.event]
                    let stamp = ISO8601DateFormatter().string(from: read.observedAt)
                    let source = Source(name: "ESPN", url: "https://www.espn.com/soccer/", observedAt: stamp, updatedAt: stamp,
                                        verification: .verified)
                    updates[row.id] = Fixture(id: row.id, sport: row.sport, start: row.start, status: .live,
                        eventKind: row.eventKind, title: row.title, competitionId: row.competitionId,
                        competitionName: row.competitionName, participants: row.participants, squad: row.squad,
                        source: source, reportedScore: nil,
                        footballLive: FootballFixtureLive(home: event.homeScore, away: event.awayScore, clock: event.clock))
                }
            }
            guard !updates.isEmpty else { return snapshot }
            return Snapshot(schemaVersion: snapshot.schemaVersion, complete: snapshot.complete, checkedAt: snapshot.checkedAt,
                            revision: snapshot.revision, sourceStatus: snapshot.sourceStatus,
                            fixtures: snapshot.fixtures.map { updates[$0.id] ?? $0 }, coverage: snapshot.coverage)
        }

        static func teamTokens(_ value: String) -> Set<String> {
            let folded = value.replacingOccurrences(of: "ß", with: "ss")
                .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .lowercased()
            let tokens = folded.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }.map(String.init)
            return Set(tokens.filter { !teamNameNoise.contains($0) && !$0.allSatisfy(\.isNumber) })
        }

        static func sameTeam(_ ours: [String], _ theirs: [String]) -> Bool {
            for left in ours.map(teamTokens) where !left.isEmpty {
                for right in theirs.map(teamTokens) where !right.isEmpty {
                    if left.isSubset(of: right) || right.isSubset(of: left) { return true }
                }
            }
            return false
        }

        static func minute(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty, value.count <= 12,
                  let match = value.wholeMatch(of: #/(\d{1,3})['′]?(?:\s*\+\s*(\d{1,2})['′]?)?/#),
                  let base = Int(match.1), (0...150).contains(base) else { return nil }
            if let extra = match.2.flatMap({ Int($0) }) {
                guard (1...99).contains(extra) else { return nil }
                return "\(base)+\(extra)′"
            }
            return "\(base)′"
        }

        static func espnDate(_ value: String) -> Date? {
            // ESPN omits seconds ("2026-11-21T19:45Z").
            let normalized = value.wholeMatch(of: #/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}Z/#) != nil ? String(value.dropLast()) + ":00Z" : value
            return date(normalized)
        }
    }
}
