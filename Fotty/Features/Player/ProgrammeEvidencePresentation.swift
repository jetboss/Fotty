import Foundation

/// Read-only presentation of the local provider-lookup and viewer evidence.
/// Counts and fixed phrases only: no provider titles, URLs, hosts or listing
/// identifiers reach the screen. Provider label comparisons are the provider's
/// own claims, never what was on screen, and never change playback or order.
struct ProgrammeEvidencePresentation: Equatable {
    /// The newest search one provider made for this fixture.
    struct Search: Equatable {
        let provider: EvidenceProvider
        let finishedAt: Date
        let found: Int
        let tryable: Int
        let listingsUnread: Int
        let isPartial: Bool
    }

    enum LabelComparison: Equatable { case agrees, namesOtherTeams, noTeamNames }

    let latestSearches: [Search]
    let labels: [UUID: LabelComparison]

    static let empty = Self(latestSearches: [], labels: [:])

    /// `fixtureID` is the playing request's match ID; it is matched by its
    /// device-keyed digest, exactly as the receipts store it.
    static func make(fixtureID: String, records: [FottyQualityRecord]) -> Self {
        guard let hex = ProgrammeEvidenceRecords.fixtureHex(fixtureID) else { return .empty }
        var newest: [EvidenceProvider: Search] = [:]
        for record in records where ProgrammeEvidenceRecords.isLookup(record)
            && record.details["evidence_fixture"] == hex {
            guard let provider = ProgrammeEvidenceRecords.provider(record),
                  let found = ProgrammeEvidenceRecords.count(record, "evidence_observed_entries"),
                  let tryable = ProgrammeEvidenceRecords.count(record, "admitted_count") else { continue }
            if let existing = newest[provider], existing.finishedAt >= record.timestamp { continue }
            newest[provider] = Search(provider: provider, finishedAt: record.timestamp, found: found,
                tryable: min(tryable, found),
                listingsUnread: ProgrammeEvidenceRecords.count(record, "evidence_unread_responses") ?? 0,
                // Sample retention also marks a receipt truncated; only the
                // search's own completion is shown as partial.
                isPartial: record.details["admission_completion"] != "complete")
        }
        let lookups = Set(records.filter { ProgrammeEvidenceRecords.isLookup($0) && $0.details["evidence_fixture"] == hex }
            .compactMap { $0.details["evidence_lookup_id"] })
        var labels: [UUID: (Date, LabelComparison)] = [:]
        for record in records where record.category == .playback && record.name == "provider_delivery"
            && record.details["evidence_fixture"] == hex {
            guard let lookup = record.details["evidence_lookup_id"], lookups.contains(lookup),
                  let raw = record.details["source_id"], let sourceID = UUID(uuidString: raw),
                  let comparison = record.details["evidence_comparison"].flatMap(MetadataComparison.init(rawValue:))
            else { continue }
            if let existing = labels[sourceID], existing.0 >= record.timestamp { continue }
            labels[sourceID] = (record.timestamp, LabelComparison(comparison))
        }
        return Self(latestSearches: newest.values.sorted { ProgrammeEvidenceRecords.name($0.provider) < ProgrammeEvidenceRecords.name($1.provider) },
                    labels: labels.mapValues(\.1))
    }

    /// One line per provider, e.g. "Highfly found 62 streams in its latest search · 18 can be tried".
    var searchLines: [String] {
        latestSearches.map { search in
            let found = search.found == 1 ? "1 stream" : "\(search.found) streams"
            var line = "\(ProgrammeEvidenceRecords.name(search.provider)) found \(found) in its latest search"
            if search.found > 0 {
                line += search.tryable == 0 ? " · none can be tried" : " · \(search.tryable) can be tried"
            }
            if search.listingsUnread > 0 {
                line += search.listingsUnread == 1 ? " · 1 listing unread" : " · \(search.listingsUnread) listings unread"
            }
            if search.isPartial { line += " · partial" }
            return line
        }
    }

    /// Shown under a source only when the provider's label says something.
    func labelNote(for sourceID: UUID) -> String? {
        switch labels[sourceID] {
        case .agrees: return "Provider label matches this game"
        case .namesOtherTeams: return "Provider label names other teams"
        case .noTeamNames, nil: return nil
        }
    }
}

private extension ProgrammeEvidencePresentation.LabelComparison {
    init(_ comparison: MetadataComparison) {
        switch comparison {
        case .agrees: self = .agrees
        case .contradicts: self = .namesOtherTeams
        case .noParseableTeams: self = .noTeamNames
        }
    }
}

/// One evidence read per Sources sheet opening. Sheet content can be
/// re-evaluated many times while open; the store is read only the first time,
/// and the snapshot is dropped when the sheet closes.
final class ProgrammeEvidenceSnapshot {
    private var stored: ProgrammeEvidencePresentation?
    private(set) var reads = 0

    func value(_ make: () -> ProgrammeEvidencePresentation) -> ProgrammeEvidencePresentation {
        if let stored { return stored }
        let made = make()
        reads += 1
        stored = made
        return made
    }

    func reset() { stored = nil }
}

/// Owner Status totals for retained evidence on the current build.
struct ProgrammeEvidenceBuildSummary: Equatable {
    struct Row: Equatable, Identifiable {
        let id: EvidenceProvider
        var searches = 0
        var found = 0
        var tryable = 0
        var listingsRead = 0
        var listingsUnread = 0
        var listingsEmpty = 0
        var partialSearches = 0
        var labelsAgree = 0
        var labelsOtherTeams = 0
        var labelsNoTeams = 0

        var name: String { ProgrammeEvidenceRecords.name(id) }
        var sampledLabels: Int { labelsAgree + labelsOtherTeams + labelsNoTeams }
    }

    let rows: [Row]
    let viewerConfirmations: Int
    let viewerWrongMatches: Int

    var isEmpty: Bool { rows.isEmpty && viewerConfirmations == 0 && viewerWrongMatches == 0 }

    /// Retained records stamped with the installed build only.
    static func currentBuild(store: FottyQualityStore = .shared,
                             version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                             build: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown") -> Self {
        make(records: store.records().filter { $0.appVersion == version && $0.appBuild == build })
    }

    static func make(records: [FottyQualityRecord]) -> Self {
        var rows: [EvidenceProvider: Row] = [:]
        var seen = Set<String>()
        for record in records where ProgrammeEvidenceRecords.isLookup(record) {
            guard let provider = ProgrammeEvidenceRecords.provider(record),
                  let lookup = record.details["evidence_lookup_id"],
                  seen.insert(provider.rawValue + ":" + lookup).inserted else { continue }
            var row = rows[provider] ?? Row(id: provider)
            row.searches += 1
            row.found += ProgrammeEvidenceRecords.count(record, "evidence_observed_entries") ?? 0
            row.tryable += ProgrammeEvidenceRecords.count(record, "admitted_count") ?? 0
            row.listingsRead += ProgrammeEvidenceRecords.count(record, "evidence_read_responses") ?? 0
            row.listingsUnread += ProgrammeEvidenceRecords.count(record, "evidence_unread_responses") ?? 0
            row.listingsEmpty += ProgrammeEvidenceRecords.count(record, "evidence_empty_responses") ?? 0
            if record.details["admission_completion"] != "complete" { row.partialSearches += 1 }
            rows[provider] = row
        }
        for record in records where record.category == .playback && record.name == "provider_delivery" {
            guard let provider = ProgrammeEvidenceRecords.provider(record), var row = rows[provider],
                  let comparison = record.details["evidence_comparison"].flatMap(MetadataComparison.init(rawValue:))
            else { continue }
            switch comparison {
            case .agrees: row.labelsAgree += 1
            case .contradicts: row.labelsOtherTeams += 1
            case .noParseableTeams: row.labelsNoTeams += 1
            }
            rows[provider] = row
        }
        let observations = records.filter { $0.category == .playback && $0.name == "programme_observation" }
        return Self(
            rows: rows.values.sorted { $0.name < $1.name },
            viewerConfirmations: observations.filter {
                $0.details["programme_observation"] == SinglePlaybackProgrammeObservation.viewerConfirmedRight.rawValue
            }.count,
            viewerWrongMatches: observations.filter {
                $0.details["programme_observation"] == SinglePlaybackProgrammeObservation.viewerReportedWrong.rawValue
            }.count)
    }
}

enum ProgrammeEvidenceRecords {
    static func fixtureHex(_ fixtureID: String) -> String? {
        guard case .fixture(let digest)? = LiveSourceHealthStore.fixtureProgrammeScope(fixtureID: fixtureID) else { return nil }
        return digest.bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func isLookup(_ record: FottyQualityRecord) -> Bool {
        record.category == .playback && record.name == "provider_lookup"
    }

    static func provider(_ record: FottyQualityRecord) -> EvidenceProvider? {
        record.details["source_family"].flatMap(EvidenceProvider.init(rawValue:))
    }

    static func count(_ record: FottyQualityRecord, _ key: String) -> Int? {
        guard let value = record.details[key], let number = Int(value),
              StreamAdmissionLedger.validCount.contains(number) else { return nil }
        return number
    }

    static func name(_ provider: EvidenceProvider) -> String {
        switch provider {
        case .highfly: return "Highfly"
        case .penguPlay: return "PenguPlay"
        case .communitySports: return "CommunitySports"
        case .cncSports: return "CNC"
        case .plavioSports: return "Plavio"
        case .flixStreams: return "FlixStreams"
        case .reviewedTV: return "TV"
        case .score808: return "Score808"
        }
    }
}
