import Foundation
import CryptoKit

struct StreamVixCatalogEntry: Decodable, Sendable, Equatable {
    let id: String
    let type: String?
    let name: String
    let description: String?
    let eventStart: String?
    let category: String?
    let originalName: String?
    let isDynamic: Bool
    let hasMalformedIdentity: Bool

    private enum CodingKeys: String, CodingKey {
        case id, type, name, description, eventStart, category, genre, genres
        case isDynamic = "_dynamic"
        case originalName = "_originalName"
        case behaviorHints, videos, released, startTime, eventstart
    }
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? v.decode(String.self, forKey: .id)) ?? ""
        type = try? v.decode(String.self, forKey: .type)
        name = (try? v.decode(String.self, forKey: .name)) ?? ""
        description = try? v.decode(String.self, forKey: .description)
        eventStart = try? v.decode(String.self, forKey: .eventStart)
        category = try? v.decode(String.self, forKey: .category)
        originalName = try? v.decode(String.self, forKey: .originalName)
        isDynamic = (try? v.decode(Bool.self, forKey: .isDynamic)) ?? false
        var malformed = id.isEmpty || type != "tv" || name.isEmpty || description == nil
            || eventStart == nil || category == nil || !isDynamic
            || (v.contains(.originalName) && originalName == nil)
            || [CodingKeys.behaviorHints, .videos, .released, .startTime, .eventstart].contains(where: v.contains)
        for key in [CodingKeys.genre, .genres] where v.contains(key) {
            malformed = malformed || (try? v.decode([String].self, forKey: key)) != category.map { [$0] }
        }
        hasMalformedIdentity = malformed
    }
}

struct StreamVixOriginalFixture: Sendable, Equatable {
    let dayHeader: String
    let clock: String
    let pairTitle: String
    let competition: String
    let kickoff: Date?

    var category: String { competition == "England - Premier League" ? "premierleague" : "coppe" }
    var competitionID: String { category == "premierleague" ? "premier-league" : "champions-league" }
    var shortLeague: String { category == "premierleague" ? "Premier League" : "UEFA Champions League" }
    var dayMonth: String? {
        guard let kickoff else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "dd/MM"; return f.string(from: kickoff)
    }
    func displayParts(derived: Date) -> (clock: String, dayMonth: String)? {
        guard let rome = TimeZone(identifier: "Europe/Rome") else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian); f.timeZone = rome
        f.dateFormat = "HH:mm"; let time = f.string(from: derived)
        f.dateFormat = "dd/MM"; return (time, f.string(from: derived))
    }
    func publishedTitle(derived: Date) -> String? {
        displayParts(derived: derived).map { "⏰ \($0.clock) : \(pairTitle) - \(shortLeague) \($0.dayMonth)" }
    }
}

enum StreamVixMatchSelection: Equatable {
    case matched(StreamVixCatalogEntry)
    case missing
    case conflicting
}

struct StreamVixStreamEntry: Decodable, Sendable {
    let url: String?
    let isSupportedContract: Bool
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: Key.self)
        url = try v.decodeIfPresent(String.self, forKey: Key(stringValue: "url")!)
        let keys = Set(v.allKeys.map(\.stringValue))
        isSupportedContract = keys == Set(["name", "title", "url"])
        for key in ["name", "title"] where keys.contains(key) {
            _ = try v.decode(String.self, forKey: Key(stringValue: key)!)
        }
    }
}

/// Fixed reviewed source, never a fixture/status feed. The original explicit
/// GMT schedule, actual advertised ID and catalog/meta must all corroborate.
actor StreamVixSportsAddonClient {
    static let shared = StreamVixSportsAddonClient()
    static let providerCode = "streamvix"
    static let manifestURL = URL(string: "https://streamvix.hayd.uk/manifest.json")!
    static let originalScheduleURL = URL(string: "https://raw.githubusercontent.com/qwertyuiop8899/logo/main/daddyliveSchedule.json")!
    static let catalogID = "streamvix_eventi"

    struct Manifest: Decodable, Sendable {
        struct Resource: Decodable, Sendable {
            let name: String
            let types: [String]?
            init(from decoder: Decoder) throws {
                if let s = try? decoder.singleValueContainer().decode(String.self) { name = s; types = nil }
                else {
                    let v = try decoder.container(keyedBy: CodingKeys.self)
                    name = try v.decode(String.self, forKey: .name)
                    types = try v.decodeIfPresent([String].self, forKey: .types)
                }
            }
            private enum CodingKeys: String, CodingKey { case name, types }
        }
        struct Catalog: Decodable, Sendable {
            struct Extra: Decodable, Sendable { let name: String; let isRequired: Bool?; let options: [String]? }
            let id: String; let type: String; let extra: [Extra]?
        }
        struct Hints: Decodable, Sendable { let configurationRequired: Bool? }
        let id: String; let version: String; let types: [String]; let resources: [Resource]
        let catalogs: [Catalog]; let behaviorHints: Hints?
    }
    private struct CatalogDocument: Decodable {
        let metas: [StreamVixCatalogEntry]
        private enum CodingKeys: String, CodingKey { case metas }
        init(from decoder: Decoder) throws {
            let v = try decoder.container(keyedBy: CodingKeys.self)
            var rows = try v.nestedUnkeyedContainer(forKey: .metas)
            var values: [StreamVixCatalogEntry] = []
            while !rows.isAtEnd {
                guard values.count < 200 else { throw CommunitySportsAddonError.invalidResponse }
                // A malformed identifiable sibling must not disappear.
                values.append(try StreamVixCatalogEntry(from: rows.superDecoder()))
            }
            metas = values
        }
    }
    private struct MetaDocument: Decodable { let meta: StreamVixCatalogEntry }
    private struct StreamDocument: Decodable {
        let streams: [StreamVixStreamEntry]
        let count: Int
        private enum CodingKeys: String, CodingKey { case streams }
        init(from decoder: Decoder) throws {
            let v = try decoder.container(keyedBy: CodingKeys.self)
            var rows = try v.nestedUnkeyedContainer(forKey: .streams)
            var values: [StreamVixStreamEntry] = []; var scanned = 0
            while !rows.isAtEnd, scanned < 100 {
                let row = try rows.superDecoder(); scanned += 1
                if let entry = try? StreamVixStreamEntry(from: row) { values.append(entry) }
            }
            streams = values; count = scanned
        }
    }
    private struct Snapshot<Value> { let value: Value; let fetchedAt: Date }
    private let transport: FottyBoundedHTTPClient
    private let manifestTTL: TimeInterval
    private let catalogTTL: TimeInterval
    private var manifestSnapshot: Snapshot<Manifest>?
    private var manifestGeneration: UUID?
    private var originalsSnapshot: Snapshot<[StreamVixOriginalFixture]>?
    private var originalsGeneration: UUID?
    private var catalogs: [String: Snapshot<[StreamVixCatalogEntry]>] = [:]
    private var catalogGenerations: [String: UUID] = [:]

    init(session: URLSession? = nil, manifestTTL: TimeInterval = 1800, catalogTTL: TimeInterval = 120) {
        transport = FottyBoundedHTTPClient(configuration: session?.configuration ?? Self.makeConfiguration())
        self.manifestTTL = manifestTTL; self.catalogTTL = catalogTTL
    }

    /// Reuse each reviewed PL/UCL catalog and original dated schedule once for
    /// the batch. Exact per-event meta and stream retrieval remain Watch-only.
    func catalogMatches(for requests: [StreamPlaybackRequest], now: Date = Date()) async throws -> [FixtureSourceCatalogMatch] {
        try Task.checkCancellation()
        guard requests.count <= 256 else { throw CommunitySportsAddonError.invalidResponse }
        let supported: (StreamPlaybackRequest) -> Bool = { request in
            Self.supports(category: request.category)
                && request.preferredEvent?.hasCatalogIdentityConflict != true
                && (request.preferredEvent.map { Self.supports(event: $0) } ?? true)
                && ReviewedSportsFixtureMatcher.requestIdentity(for: request) != nil
        }
        var originals: [StreamVixOriginalFixture] = [], entries: [String: [StreamVixCatalogEntry]] = [:]
        var failures: [String: StreamFailureCategory] = [:]
        if requests.contains(where: supported) {
            _ = try await loadManifest(now: now)
            originals = try await loadOriginals(now: now)
            var categories = Set<String>()
            for request in requests where supported(request) {
                if case .matched(let index) = Self.selectOriginal(for: request, from: originals) {
                    categories.insert(originals[index].category)
                }
            }
            for category in categories.sorted() {
                do { entries[category] = try await loadCatalog(category: category, now: now) }
                catch {
                    try Task.checkCancellation()
                    guard !CommunitySportsAddonClient.isFatalCatalogBatchError(error) else { throw error }
                    failures[category] = CommunitySportsAddonClient.catalogBatchFailureCategory(error)
                }
            }
        }
        try Task.checkCancellation()
        return try requests.map { request in
            try Task.checkCancellation()
            if request.preferredEvent?.hasCatalogIdentityConflict == true {
                return .init(matchID: request.matchID, outcome: .conflicting)
            }
            guard supported(request) else { return .init(matchID: request.matchID, outcome: .unsupported) }
            let original: StreamVixOriginalFixture
            switch Self.selectOriginal(for: request, from: originals) {
            case .matched(let index): original = originals[index]
            case .missing: return .init(matchID: request.matchID, outcome: .notListed)
            case .conflicting: return .init(matchID: request.matchID, outcome: .conflicting)
            }
            if let category = failures[original.category] {
                return .init(matchID: request.matchID, outcome: .failed(category))
            }
            switch Self.selectMatch(for: request, from: entries[original.category] ?? [], originals: originals) {
            case .matched(let entry): return .init(matchID: request.matchID, outcome: .listed, providerEventID: entry.id)
            case .missing: return .init(matchID: request.matchID, outcome: .notListed)
            case .conflicting: return .init(matchID: request.matchID, outcome: .conflicting)
            }
        }
    }

    func resolve(for request: StreamPlaybackRequest, now: Date = Date(),
                 forceRefresh: Bool = false) async throws -> [StreamSession] {
        let clock = ContinuousClock(); let startedAt = clock.now
        try Task.checkCancellation()
        guard Self.supports(category: request.category), request.preferredEvent?.hasCatalogIdentityConflict != true,
              ReviewedSportsFixtureMatcher.requestIdentity(for: request) != nil else {
            throw CommunitySportsAddonError.matchNotFound
        }
        let manifest = try await loadManifest(now: now, forceRefresh: forceRefresh)
        let originals = try await loadOriginals(now: now, forceRefresh: forceRefresh)
        let original: StreamVixOriginalFixture
        switch Self.selectOriginal(for: request, from: originals) {
        case .matched(let index): original = originals[index]
        case .missing: throw CommunitySportsAddonError.matchNotFound
        case .conflicting: throw CommunitySportsAddonError.conflictingMatch
        }
        let entries = try await loadCatalog(category: original.category, now: now, forceRefresh: forceRefresh)
        let selected: StreamVixCatalogEntry
        switch Self.selectMatch(for: request, from: entries, originals: originals) {
        case .matched(let entry): selected = entry
        case .missing: throw CommunitySportsAddonError.matchNotFound
        case .conflicting: throw CommunitySportsAddonError.conflictingMatch
        }
        let meta: MetaDocument = try await fetchJSON(MetaDocument.self,
            from: Self.route(["meta", "tv", selected.id + ".json"]), stage: .metadata)
        guard meta.meta.id == selected.id, Self.sameFacts(meta.meta, selected),
              case .matched = Self.selectMatch(for: request, from: entries + [meta.meta], originals: originals) else {
            throw CommunitySportsAddonError.conflictingMatch
        }
        let document: StreamDocument = try await fetchJSON(StreamDocument.self,
            from: Self.route(["stream", "tv", selected.id + ".json"]), stage: .streams)
        guard document.count > 0 else { throw CommunitySportsAddonError.streamEntriesEmpty }
        let elapsed = startedAt.duration(to: clock.now).components
        let admissionTime = now.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        guard let binding = StreamEventBinding(request: request, providerCode: Self.providerCode,
            providerEventID: selected.id, streamID: selected.id, manifestRevision: manifest.version,
            verifiedAt: admissionTime, expiresAt: admissionTime.addingTimeInterval(StreamEventBinding.metadataLifetime),
            at: admissionTime) else { throw CommunitySportsAddonError.conflictingMatch }
        let sessions = Self.makeSessions(from: document.streams, request: request, addOnVersion: manifest.version,
            now: admissionTime, eventBinding: binding)
        guard !sessions.isEmpty else { throw CommunitySportsAddonError.streamAdmissionRejected(entryCount: document.count) }
        try Task.checkCancellation()
        return sessions
    }

    private func loadManifest(now: Date, forceRefresh: Bool = false) async throws -> Manifest {
        if !forceRefresh, let s = manifestSnapshot, Self.fresh(s.fetchedAt, now, manifestTTL) { return s.value }
        let generation = UUID(); manifestGeneration = generation
        let manifest = try Self.validateManifest(data: await fetchData(from: Self.manifestURL, stage: .manifest))
        try Task.checkCancellation()
        if manifestGeneration == generation { manifestSnapshot = .init(value: manifest, fetchedAt: now) }
        return manifest
    }
    private func loadOriginals(now: Date, forceRefresh: Bool = false) async throws -> [StreamVixOriginalFixture] {
        if !forceRefresh, let s = originalsSnapshot, Self.fresh(s.fetchedAt, now, s.value.isEmpty ? 15 : catalogTTL) { return s.value }
        let generation = UUID(); originalsGeneration = generation
        let rows = try Self.originalFixtures(data: await fetchData(from: Self.originalScheduleURL, stage: .catalog))
        try Task.checkCancellation()
        if originalsGeneration == generation { originalsSnapshot = .init(value: rows, fetchedAt: now) }
        return rows
    }
    private func loadCatalog(category: String, now: Date, forceRefresh: Bool = false) async throws -> [StreamVixCatalogEntry] {
        if !forceRefresh, let s = catalogs[category], Self.fresh(s.fetchedAt, now, s.value.isEmpty ? 15 : catalogTTL) { return s.value }
        let generation = UUID(); catalogGenerations[category] = generation
        let genre = category == "premierleague" ? "Premier League" : "Coppe"
        let document: CatalogDocument = try await fetchJSON(CatalogDocument.self,
            from: Self.route(["catalog", "tv", Self.catalogID, "genre=" + genre + ".json"]), stage: .catalog)
        try Task.checkCancellation()
        if catalogGenerations[category] == generation { catalogs[category] = .init(value: document.metas, fetchedAt: now) }
        return document.metas
    }
    private func fetchJSON<Value: Decodable>(_ type: Value.Type, from url: URL,
                                            stage: CommunitySportsRequestStage) async throws -> Value {
        let data = try await fetchData(from: url, stage: stage)
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw CommunitySportsAddonError.invalidJSON(stage: stage) }
    }
    private func fetchData(from url: URL, stage: CommunitySportsRequestStage) async throws -> Data {
        guard Self.isSafeMetadataURL(url) else { throw CommunitySportsAddonError.unsafeResponse }
        var request = URLRequest(url: url); request.timeoutInterval = stage.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Fotty/2.0 Stremio-Compatible", forHTTPHeaderField: "User-Agent")
        let limit = url == Self.originalScheduleURL ? 1024 * 1024 : stage == .manifest ? 128 * 1024 : 512 * 1024
        do {
            let result = try await transport.fetch(request, maximumBytes: limit, deadline: stage.transportDeadline,
                redirectPolicy: { from, to in Self.isSafeMetadataURL(from) && Self.isSafeMetadataURL(to)
                    && from.host == to.host && from.path == to.path })
            try Task.checkCancellation()
            guard let final = result.http.url, final.host == url.host, final.path == url.path,
                  Self.isSafeMetadataURL(final) else { throw CommunitySportsAddonError.unsafeResponse }
            return result.data
        } catch let failure as FottyBoundedHTTPClient.Failure {
            try Task.checkCancellation()
            if failure == .unsafeRedirect { throw CommunitySportsAddonError.unsafeResponse }
            if case .httpStatus(let code) = failure { throw CommunitySportsAddonError.httpFailure(statusCode: code, stage: stage) }
            throw CommunitySportsAddonError.invalidResponse
        } catch let error as URLError {
            try Task.checkCancellation()
            if error.code == .cancelled { throw error }
            throw CommunitySportsAddonError.transportFailure(code: error.errorCode, stage: stage)
        }
    }

    nonisolated static func validateManifest(data: Data) throws -> Manifest {
        let m: Manifest
        do { m = try JSONDecoder().decode(Manifest.self, from: data) }
        catch { throw CommunitySportsAddonError.invalidJSON(stage: .manifest) }
        guard m.id == "org.prisonmike.streamvix", safeVersion(m.version) != "unknown", m.types.contains("tv"),
              m.behaviorHints?.configurationRequired != true, m.catalogs.count <= 64,
              ["catalog", "meta", "stream"].allSatisfy({ name in
                  m.resources.contains { $0.name == name && ($0.types?.contains("tv") ?? true) }
              }),
              m.catalogs.filter({ $0.id == catalogID && $0.type == "tv" }).count == 1,
              let extras = m.catalogs.first(where: { $0.id == catalogID && $0.type == "tv" })?.extra,
              extras.contains(where: { $0.name == "genre" && $0.isRequired == true
                  && Set($0.options ?? []).isSuperset(of: ["Premier League", "Coppe"]) }) else {
            throw CommunitySportsAddonError.invalidManifest
        }
        return m
    }

    nonisolated static func originalFixtures(data: Data) throws -> [StreamVixOriginalFixture] {
        guard data.count <= 1024 * 1024,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root.count <= 8 else {
            throw CommunitySportsAddonError.invalidResponse
        }
        var result: [StreamVixOriginalFixture] = []
        for day in root.keys.sorted() {
            // The publisher adds unrelated sports categories independently.
            // Read only the reviewed football key; payload/day/football-row
            // bounds below already constrain parsing without a taxonomy cap.
            guard let groups = root[day] as? [String: Any] else {
                throw CommunitySportsAddonError.invalidResponse
            }
            guard let value = groups["All Soccer Events ⚽"] else { continue }
            guard let rows = value as? [Any], rows.count <= 600 else { throw CommunitySportsAddonError.invalidResponse }
            for value in rows {
                guard let row = value as? [String: Any], let event = row["event"] as? String,
                      event.utf8.count <= 1024 else { throw CommunitySportsAddonError.invalidResponse }
                for competition in ["England - Premier League", "UEFA Champions League"] {
                    let prefix = "⚽ " + competition + " : "
                    guard event.hasPrefix(prefix) else { continue }
                    guard StreamVixTimingPolicy.originalKickoff(dayHeader: day, clock: "00:00") != nil else {
                        throw CommunitySportsAddonError.conflictingMatch
                    }
                    let pair = String(event.dropFirst(prefix.count))
                    guard let clean = stripFlags(pair) else { throw CommunitySportsAddonError.conflictingMatch }
                    // This named programme covers several games; it is not a
                    // fixture and must not invalidate the adjacent fixtures.
                    if clean == "Simulcast" { continue }
                    guard ReviewedSportsFixtureMatcher.participantIdentity(
                        sport: "football", cast: [], title: clean) != nil else { throw CommunitySportsAddonError.conflictingMatch }
                    let clock = row["time"] as? String ?? ""
                    result.append(.init(dayHeader: day, clock: clock, pairTitle: pair, competition: competition,
                                        kickoff: StreamVixTimingPolicy.originalKickoff(dayHeader: day, clock: clock)))
                }
            }
        }
        return result
    }

    nonisolated private static func selectOriginal(for request: StreamPlaybackRequest,
                                                  from originals: [StreamVixOriginalFixture]) -> ReviewedSportsFixtureMatcher.Selection {
        let candidates = originals.map { row -> ReviewedSportsFixtureMatcher.Candidate in
            let title = stripFlags(row.pairTitle) ?? ""
            let participants = ReviewedSportsFixtureMatcher.participantIdentity(sport: "football", cast: [], title: title)
            let day = StreamVixTimingPolicy.originalKickoff(dayHeader: row.dayHeader, clock: "00:00")
                .map { String($0.timeIntervalSince1970) } ?? row.dayHeader
            let key = day + "\n" + row.competition + "\n" + (participants?.pair.joined(separator: "|") ?? title)
            let identity = ReviewedSportsFixtureMatcher.fixtureIdentity(sport: "football", cast: [], title: title,
                kickoff: row.kickoff, effectiveID: key, resourceType: "tv")
            return .init(metadataID: key, effectiveID: key, identity: identity)
        }
        // Original schedule keys are corroborating facts, not advertised
        // Stremio event IDs. Bind the final catalog selection below; keep this
        // first source-authority lookup on the unchanged canonical fixture.
        guard let canonical = ReviewedSportsFixtureMatcher.requestIdentity(for: request) else { return .missing }
        let selection = ReviewedSportsFixtureMatcher.select(for: canonical, from: candidates)
        if case .matched(let i) = selection, let competition = request.preferredEvent?.competitionID,
           !competition.isEmpty, competition != originals[i].competitionID { return .conflicting }
        return selection
    }

    nonisolated static func selectMatch(for request: StreamPlaybackRequest, from entries: [StreamVixCatalogEntry],
                                        originals: [StreamVixOriginalFixture]) -> StreamVixMatchSelection {
        let original: StreamVixOriginalFixture
        switch selectOriginal(for: request, from: originals) {
        case .matched(let i): original = originals[i]
        case .conflicting: return .conflicting
        case .missing: return .missing
        }
        let candidates = entries.map { entry -> ReviewedSportsFixtureMatcher.Candidate in
            // Equivalent published aliases can have different presentation
            // slugs. They may corroborate only the same canonical original
            // facts; none may conceal a different date/squad/competition.
            let pair = stripFlags(original.pairTitle).flatMap {
                ReviewedSportsFixtureMatcher.participantIdentity(sport: "football", cast: [], title: $0)
            }
            let equivalents = originals.filter { row in
                row.kickoff == original.kickoff && row.competition == original.competition
                    && stripFlags(row.pairTitle).flatMap {
                        ReviewedSportsFixtureMatcher.participantIdentity(sport: "football", cast: [], title: $0)
                    } == pair
            }
            let identity = equivalents.lazy.compactMap { corroborated(entry, original: $0, allOriginals: originals) }.first
            return .init(metadataID: entry.id, effectiveID: entry.id, identity: identity)
        }
        switch ReviewedSportsFixtureMatcher.select(for: request, from: candidates) {
        case .matched(let i): return .matched(entries[i])
        case .conflicting: return .conflicting
        case .missing: return .missing
        }
    }

    nonisolated private static func corroborated(_ entry: StreamVixCatalogEntry, original: StreamVixOriginalFixture,
        allOriginals: [StreamVixOriginalFixture]) -> ReviewedSportsFixtureMatcher.FixtureIdentity? {
        guard !entry.hasMalformedIdentity, safeID(entry.id), let rawStart = entry.eventStart,
              let derived = explicitUTC(rawStart), let originalDate = original.kickoff,
              let display = original.displayParts(derived: derived), let sourceTitle = original.publishedTitle(derived: derived),
              entry.category == original.category,
              StreamVixTimingPolicy.corroborates(derived: derived, original: originalDate),
              advertisedID(sourceTitle: sourceTitle, derived: derived) == entry.id,
              entry.originalName == nil || stripFlags(entry.originalName ?? "") == stripFlags(sourceTitle),
              let pair = stripFlags(original.pairTitle),
              stripFlags(entry.name) == "\(pair) ⏰ \(display.clock) - \(display.dayMonth)",
              stripFlags(entry.description ?? "") == "🔴 Inizio: \(display.clock) - \(pair) - \(original.shortLeague) - \(display.dayMonth)" else { return nil }
        // The source truncates slugs. An ID bridge cannot hide a different full
        // original fixture that happens to produce the same advertised target.
        for other in allOriginals where other != original {
            guard let date = other.kickoff else { continue }
            let possibleDates = [date, StreamVixTimingPolicy.legacyRomeInterpretation(of: date)].compactMap { $0 }
            if possibleDates.contains(where: { candidate in
                other.publishedTitle(derived: candidate).map { advertisedID(sourceTitle: $0, derived: candidate) == entry.id } ?? false
            }),
               other.kickoff != original.kickoff || other.competition != original.competition
                || stripFlags(other.pairTitle) != pair { return nil }
        }
        return ReviewedSportsFixtureMatcher.fixtureIdentity(sport: "football", cast: [], title: pair,
            kickoff: originalDate, effectiveID: entry.id, resourceType: "tv")
    }

    nonisolated static func advertisedID(sourceTitle: String, derived: Date) -> String {
        // Verification only: network requests always use a literal advertised ID.
        let ascii = sourceTitle.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyyMMdd"
        return "tv:" + String(ascii.prefix(60)) + "-" + f.string(from: derived)
    }
    nonisolated private static func sameFacts(_ a: StreamVixCatalogEntry, _ b: StreamVixCatalogEntry) -> Bool {
        !a.hasMalformedIdentity && !b.hasMalformedIdentity && a.type == b.type && a.eventStart == b.eventStart
            && a.category == b.category && stripFlags(a.name) == stripFlags(b.name)
            && stripFlags(a.description ?? "") == stripFlags(b.description ?? "")
    }
    nonisolated private static func explicitUTC(_ raw: String) -> Date? {
        guard raw.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:00Z$"#,
                        options: .regularExpression) != nil else { return nil }
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: raw), f.string(from: d) == raw else { return nil }; return d
    }
    nonisolated private static func stripFlags(_ raw: String) -> String? {
        let england = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
        let flags: Set<String> = [england, "🇬🇧", "🇫🇷", "🇪🇸", "🇮🇹", "🇩🇪", "🇵🇹", "🇳🇱", "🇧🇪", "🇹🇷", "🇨🇿",
            "🇦🇹", "🇨🇭", "🇩🇰", "🇸🇪", "🇳🇴", "🇺🇦", "🇦🇿", "🇮🇱", "🇷🇸", "🇬🇷", "🇭🇷", "🇨🇾", "🇵🇱", "🇭🇺"]
        guard raw.utf8.count <= 4096 else { return nil }
        let value = raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            .filter { !flags.contains($0) }.joined(separator: " ")
        guard !hasControls(value), !value.unicodeScalars.contains(where: { (0x1F1E6...0x1F1FF).contains($0.value) }) else { return nil }
        return value
    }
    nonisolated static func makeSessions(from streams: [StreamVixStreamEntry], request: StreamPlaybackRequest,
                                         addOnVersion: String, now: Date = Date(),
                                         eventBinding: StreamEventBinding? = nil) -> [StreamSession] {
        guard let definition = CuratedStreamSourceCatalog.definition(forProviderCode: providerCode) else { return [] }
        if let eventBinding, !eventBinding.matches(request: request, providerCode: providerCode, at: now) { return [] }
        var seen = Set<String>(); var sessions: [StreamSession] = []
        for entry in streams.prefix(100) {
            guard entry.isSupportedContract, let value = entry.url, let url = URL(string: value),
                  let expiry = reviewedDeliveryExpiry(url, now: now) else { continue }
            let key = sourceKey(url: url); guard seen.insert(key).inserted else { continue }
            guard let label = definition.sourceLabel(choice: sessions.count + 1) else { break }
            sessions.append(.init(matchID: request.matchID, playableURL: url, streamType: .hls,
                providerName: label, requiredHeaders: [:], qualityLabel: "Live video",
                expiryTime: expiry, canRefresh: false, validationStatus: .validated,
                diagnosticMetadata: ["source_family": providerCode, "source_key": key, "source_key_scope": "delivery",
                    "manifest_result": "exact_fixture_match", "delivery": "reviewed_direct_hls",
                    "addon_version": safeVersion(addOnVersion)], createdAt: now,
                requiresGuardedRelay: true, eventBinding: eventBinding))
            if sessions.count == 6 { break }
        }
        return sessions
    }
    nonisolated static func isAdmittedDelivery(_ url: URL, now: Date = Date()) -> Bool {
        reviewedDeliveryExpiry(url, now: now) != nil
    }

    nonisolated private static func reviewedDeliveryExpiry(_ url: URL, now: Date) -> Date? {
        guard safeOrigin(url, host: "p7.streamhostingcdn.top"), url.absoluteString.utf8.count <= 8192,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.percentEncodedPath.range(of: #"^/stream/[1-9][0-9]*/index\.m3u8$"#, options: .regularExpression) != nil,
              let query = c.queryItems, query.count == 2, Set(query.map(\.name)) == Set(["token", "exp"]),
              let token = query.first(where: { $0.name == "token" })?.value, !token.isEmpty,
              token.utf8.count <= 4096, !hasControls(token), token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let expiry = query.first(where: { $0.name == "exp" })?.value,
              expiry.range(of: #"^[0-9]{10}$"#, options: .regularExpression) != nil,
              let seconds = TimeInterval(expiry), now.timeIntervalSince1970.isFinite,
              seconds > now.timeIntervalSince1970 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
    nonisolated static func sourceKey(url: URL) -> String {
        "sv_" + SHA256.hash(data: Data((url.absoluteString + "\nheaders:{}").utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
    nonisolated static func supports(category: String) -> Bool { ReviewedSportsFixtureMatcher.sportKey(category) == "football" }
    nonisolated static func supports(event: EventReference) -> Bool {
        supports(category: event.category ?? "") && ["premier-league", "champions-league"].contains(event.competitionID ?? "")
    }
    nonisolated static func isSafeMetadataURL(_ url: URL) -> Bool {
        guard url.query == nil, url.absoluteString.utf8.count <= 1024 else { return false }
        if url == originalScheduleURL { return true }
        guard safeOrigin(url, host: "streamvix.hayd.uk"), let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        if c.percentEncodedPath == "/manifest.json" { return true }
        if ["/catalog/tv/streamvix_eventi/genre=Premier%20League.json", "/catalog/tv/streamvix_eventi/genre=Coppe.json"].contains(c.percentEncodedPath) { return true }
        let path = url.path
        let pieces = path.split(separator: "/").map(String.init)
        guard pieces.count == 3, ["meta", "stream"].contains(pieces[0]), pieces[1] == "tv", pieces[2].hasSuffix(".json"),
              safeID(String(pieces[2].dropLast(5))) else { return false }
        return c.percentEncodedPath == path || c.percentEncodedPath == path.replacingOccurrences(of: ":", with: "%3A")
    }
    nonisolated private static func safeID(_ id: String) -> Bool {
        id.utf8.count <= 128 && id.range(of: #"^tv:[a-z0-9][a-z0-9-]{0,59}-[0-9]{8}$"#, options: .regularExpression) != nil
    }
    nonisolated private static func safeOrigin(_ u: URL, host: String) -> Bool {
        u.scheme?.lowercased() == "https" && u.host?.lowercased() == host && (u.port == nil || u.port == 443)
            && u.user == nil && u.password == nil && u.fragment == nil
    }
    nonisolated private static func hasControls(_ raw: String) -> Bool {
        raw.unicodeScalars.contains {
            switch $0.properties.generalCategory { case .control, .format, .lineSeparator, .paragraphSeparator: return true; default: return false }
        }
    }
    nonisolated private static func route(_ parts: [String]) -> URL {
        parts.reduce(manifestURL.deletingLastPathComponent()) { $0.appendingPathComponent($1) }
    }
    nonisolated private static func safeVersion(_ value: String) -> String {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,23}$"#, options: .regularExpression) != nil ? value : "unknown"
    }
    nonisolated static func makeConfiguration() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 7; c.timeoutIntervalForResource = 12; c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData; c.httpCookieStorage = nil
        c.httpShouldSetCookies = false; c.urlCredentialStorage = nil; return c
    }
    nonisolated private static func fresh(_ date: Date, _ now: Date, _ ttl: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(date); return age >= 0 && age < ttl
    }
}
