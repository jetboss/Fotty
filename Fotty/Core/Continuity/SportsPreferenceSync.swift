import CryptoKit
import Foundation
import Observation
import Security

/// A minimal sports configuration, not a backup, account, viewing history or
/// notification consent. iCloud key-value storage is not an encrypted vault.
struct SportsPlannedMatchIdentity: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let category: String
    let homeName: String
    let awayName: String
    let kickoff: Date?
    let competitionID: String?
    let squadQualifiers: [String]

    @MainActor
    init(event: EventReference) {
        id = event.id; title = event.displayTitle; category = event.normalizedCategory
        homeName = event.homeName; awayName = event.awayName; kickoff = event.kickoffDate
        competitionID = event.competitionID ?? event.cricketFixture?.competitionID
        squadQualifiers = SportsHandoffIdentity.qualifiers(for: event)
    }

    init(id: String, title: String, category: String, homeName: String, awayName: String,
         kickoff: Date?, competitionID: String?, squadQualifiers: [String] = []) {
        self.id = id; self.title = title; self.category = category; self.homeName = homeName
        self.awayName = awayName; self.kickoff = kickoff; self.competitionID = competitionID
        self.squadQualifiers = squadQualifiers
    }

    func isValid() -> Bool {
        SportsSyncValidation.text(id, maximum: 200) && SportsSyncValidation.text(title, maximum: 300)
            && SportsHandoffIdentity.supportedSports.contains(category)
            && SportsSyncValidation.text(homeName, maximum: 160)
            && SportsSyncValidation.text(awayName, maximum: 160, permitsEmpty: true)
            && (competitionID.map { SportsSyncValidation.text($0, maximum: 120) } ?? true)
            && (kickoff.map { $0.timeIntervalSince1970.isFinite && $0.timeIntervalSince1970 > 0 } ?? true)
            && squadQualifiers.count <= 12 && Set(squadQualifiers).count == squadQualifiers.count
            && squadQualifiers.allSatisfy { SportsSyncValidation.text($0, maximum: 40) }
    }
}

struct SportsPreferenceSyncIntent: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable { case preference, followedTeam, followedCompetition, plannedMatch, followedSport }
    enum Preference: String, Codable, Sendable { case onlySelectedInterests, viewingWindow }

    let kind: Kind
    let key: String
    let category: String?
    let name: String?
    let flag: Bool?
    let number: Int?
    let match: SportsPlannedMatchIdentity?
    var id: String { "\(kind.rawValue)|\(category ?? "")|\(key)" }

    static func onlySelectedInterests(_ enabled: Bool) -> Self {
        .init(kind: .preference, key: Preference.onlySelectedInterests.rawValue,
              category: nil, name: nil, flag: enabled, number: nil, match: nil)
    }
    static func viewingWindow(_ rawValue: String) -> Self {
        .init(kind: .preference, key: Preference.viewingWindow.rawValue,
              category: nil, name: rawValue, flag: nil, number: nil, match: nil)
    }
    static func followedTeam(key: String, name: String, category: String) -> Self {
        .init(kind: .followedTeam, key: key, category: category, name: name, flag: nil, number: nil, match: nil)
    }
    static func followedCompetition(id: String, name: String, category: String) -> Self {
        .init(kind: .followedCompetition, key: id, category: category, name: name, flag: nil, number: nil, match: nil)
    }
    static func followedSport(_ category: String) -> Self {
        .init(kind: .followedSport, key: category, category: category, name: nil, flag: nil, number: nil, match: nil)
    }
    static func plannedMatch(_ match: SportsPlannedMatchIdentity) -> Self {
        .init(kind: .plannedMatch, key: match.id, category: match.category, name: nil, flag: nil, number: nil, match: match)
    }

    func isValid() -> Bool {
        guard SportsSyncValidation.text(key, maximum: 240) else { return false }
        switch kind {
        case .preference:
            guard category == nil, match == nil, let preference = Preference(rawValue: key) else { return false }
            switch preference {
            case .onlySelectedInterests: return name == nil && flag != nil && number == nil
            case .viewingWindow: return flag == nil && number == nil && name.map { ["90-minutes", "2-hours", "evening"].contains($0) } == true
            }
        case .followedTeam, .followedCompetition:
            return category.map { SportsHandoffIdentity.supportedSports.contains($0) } == true
                && name.map { SportsSyncValidation.text($0, maximum: 160) } == true
                && flag == nil && number == nil && match == nil
        case .followedSport:
            return category == key && SportsSyncValidation.supportedWholeSportIDs.contains(key)
                && name == nil && flag == nil && number == nil && match == nil
        case .plannedMatch:
            return name == nil && flag == nil && number == nil
                && match.map { $0.isValid() && $0.id == key && $0.category == category } == true
        }
    }
}

struct SportsPreferenceSyncRecord: Codable, Equatable, Sendable {
    let version: Int
    let intent: SportsPreferenceSyncIntent
    let revision: Int64
    let origin: String
    let removed: Bool
    let modifiedAt: Date

    /// Logical clocks avoid wall-clock skew. At equal clocks removal wins,
    /// then a device-local opaque UUID breaks ties identically on every device.
    func wins(over other: Self) -> Bool {
        if revision != other.revision { return revision > other.revision }
        if removed != other.removed { return removed }
        return origin > other.origin
    }
    func isValid() -> Bool {
        version == 1 && intent.isValid() && revision > 0 && revision < Int64.max
            && UUID(uuidString: origin) != nil && modifiedAt.timeIntervalSince1970.isFinite
    }
}

enum SportsSyncValidation {
    static let maximumRecords = 256
    static let maximumRecordBytes = 4 * 1024
    static let maximumJournalBytes = 512 * 1024
    /// Versioned whole-sport wire scope. Expanding local interests must not send
    /// records that an existing reader rejects as an invalid remote batch.
    static let supportedWholeSportIDs: Set<String> = [
        "football", "cricket", "basketball", "baseball", "tennis", "hockey",
        "fight", "american-football", "motorsport", "golf", "rugby", "volleyball"
    ]
    /// Legacy shared-by-intent keys remain read-only inputs.
    static let cloudPrefix = "fotty.sports.intent.v1."
    static let cloudSlotPrefix = "fotty.sports.intent.v2."
    /// Older clients ignore this namespace instead of rejecting their entire
    /// existing team/competition reconciliation on an unknown intent kind.
    static let sportCloudSlotPrefix = "fotty.sport.intent.v1."

    static func text(_ value: String, maximum: Int, permitsEmpty: Bool = false) -> Bool {
        value.count <= maximum && value.utf8.count <= maximum * 4
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.contains("://")
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
            && (permitsEmpty || !value.isEmpty)
    }
    static func cloudKey(for id: String) -> String {
        cloudPrefix + SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func cloudSlotKey(for record: SportsPreferenceSyncRecord) -> String {
        (record.intent.kind == .followedSport ? sportCloudSlotPrefix : cloudSlotPrefix) + record.origin + "."
            + SHA256.hash(data: Data(record.intent.id.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func acceptsCloudKey(_ key: String, record: SportsPreferenceSyncRecord) -> Bool {
        (record.intent.kind != .followedSport && key == cloudKey(for: record.intent.id)) || key == cloudSlotKey(for: record)
    }
    static func encode(_ record: SportsPreferenceSyncRecord) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard record.isValid(), let data = try? encoder.encode(record), data.count <= maximumRecordBytes else { return nil }
        return data
    }
    static func decode(_ data: Data) -> SportsPreferenceSyncRecord? {
        guard data.count <= maximumRecordBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["version", "intent", "revision", "origin", "removed", "modifiedAt"]),
              let intent = object["intent"] as? [String: Any],
              Set(intent.keys).isSubset(of: ["kind", "key", "category", "name", "flag", "number", "match"])
        else { return nil }
        if let match = intent["match"] as? [String: Any],
           !Set(match.keys).isSubset(of: ["id", "title", "category", "homeName", "awayName", "kickoff", "competitionID", "squadQualifiers"]) { return nil }
        guard let record = try? JSONDecoder().decode(SportsPreferenceSyncRecord.self, from: data), record.isValid() else { return nil }
        return record
    }
}

@MainActor
protocol SportsPreferenceCloudClient {
    var values: [String: Data] { get }
    /// Account token stays on this device. nil suspends rather than queuing
    /// sports configuration for a future, unidentified signed-in account.
    var accountIdentity: Data? { get }
    func set(_ data: Data, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

@MainActor
private final class SystemSportsPreferenceCloudClient: SportsPreferenceCloudClient {
    private let store = NSUbiquitousKeyValueStore.default
    var values: [String: Data] {
        store.dictionaryRepresentation.reduce(into: [:]) { result, entry in
            if (entry.key.hasPrefix(SportsSyncValidation.cloudPrefix)
                || entry.key.hasPrefix(SportsSyncValidation.cloudSlotPrefix)
                || entry.key.hasPrefix(SportsSyncValidation.sportCloudSlotPrefix)), let data = entry.value as? Data {
                result[entry.key] = data
            }
        }
    }
    var accountIdentity: Data? {
        guard let token = FileManager.default.ubiquityIdentityToken else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
    }
    func set(_ data: Data, forKey key: String) { store.set(data, forKey: key) }
    func synchronize() -> Bool { store.synchronize() }
}

/// Opaque installation writer identity, not a hardware ID or synced secret.
/// Injection keeps all tests away from the actual Keychain.
@MainActor
protocol SportsSyncWriterOriginStore {
    func load() throws -> String?
    func save(_ origin: String) throws
}

@MainActor
private final class KeychainSportsSyncWriterOriginStore: SportsSyncWriterOriginStore {
    private enum Failure: Error { case unavailable, malformed }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.jelani.Fotty.sports-sync.writer.v2",
         kSecAttrAccount as String: "writer",
         kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true]
    }

    func load() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.unavailable }
        guard let data = result as? Data, data.count <= 128,
              let text = String(data: data, encoding: .utf8),
              let uuid = UUID(uuidString: text), text == uuid.uuidString else { throw Failure.malformed }
        return text
    }

    func save(_ origin: String) throws {
        guard UUID(uuidString: origin)?.uuidString == origin else { throw Failure.malformed }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(origin.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let addition = query.merging(attributes, uniquingKeysWith: { _, value in value })
            guard SecItemAdd(addition as CFDictionary, nil) == errSecSuccess else { throw Failure.unavailable }
        } else if status != errSecSuccess { throw Failure.unavailable }
        guard try load() == origin else { throw Failure.unavailable }
    }
}

/// A bounded per-intent journal. It never reads/writes the whole defaults domain,
/// SwiftData store, backup, alert opt-ins, FPL or diagnostics. Tombstones are not
/// silently pruned: an offline device must not resurrect a removed preference.
@MainActor @Observable
final class SportsPreferenceSyncStore {
    // Publish the singleton before Keychain/iCloud can pump the main run loop
    // and re-enter a scene task. Never do framework startup inside dispatch_once.
    static let shared = SportsPreferenceSyncStore(deferStartup: true)
    enum Status: Equatable {
        case off, waitingForICloud, updatesQueued, unavailable, accountChanged, deviceChanged, quotaExceeded, invalidRemoteData
        var message: String {
            switch self {
            case .off: return "Off"
            case .waitingForICloud: return "Waiting for iCloud"
            case .updatesQueued: return "iCloud updates queued"
            case .unavailable: return "iCloud unavailable"
            case .accountChanged: return "Apple account changed. Turn on sports sync again to use this account."
            case .deviceChanged: return "This device needs a new sports sync opt-in."
            case .quotaExceeded: return "Sports sync storage is full. Your local setup is unchanged."
            case .invalidRemoteData: return "An iCloud update could not be accepted. Your local setup is unchanged."
            }
        }
    }
    enum MutationResult: Equatable { case saved, unchanged, rejected, storageFull, applicationNeeded }
    /// Local failure stage only. Never an account token, writer UUID, fixture,
    /// telemetry event or cloud delivery receipt.
    enum FailureStage: String { case writerIdentity, accountIdentity, cloudAttachment, accountChanged }
    private(set) var failureStage: FailureStage?
    private enum MutationAuthority {
        case explicit
        case applied(SportsPreferenceSyncRecord?)
    }
    private(set) var enabled: Bool
    private(set) var status: Status = .off
    private(set) var records: [SportsPreferenceSyncRecord]
    var activeIntents: [SportsPreferenceSyncIntent] { records.filter { !$0.removed }.map(\.intent) }
    private let defaults: UserDefaults
    private let localKey: String
    private var storedClient: (any SportsPreferenceCloudClient)?
    private let observesSystemCloud: Bool
    private var client: any SportsPreferenceCloudClient {
        if let storedClient { return storedClient }
        let created = SystemSportsPreferenceCloudClient()
        storedClient = created
        return created
    }
    private var isStarting = false
    private var hasStarted = false
    private var origin: String
    private let originStore: any SportsSyncWriterOriginStore
    private let journalWriter: @MainActor (Data, String, UserDefaults) throws -> Void
    private var writerReady = false
    /// Local KVS attachment result only, never a download/delivery receipt.
    private var cloudAccessAvailable = false
    private var consentIdentity: Data?
    private var observer: NSObjectProtocol?
    private var identityObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard, localKey: String = "fotty.sports-sync.v1",
         client: (any SportsPreferenceCloudClient)? = nil,
         originStore: (any SportsSyncWriterOriginStore)? = nil,
         journalWriter: (@MainActor (Data, String, UserDefaults) throws -> Void)? = nil,
         deferStartup: Bool = false) {
        self.defaults = defaults; self.localKey = localKey
        storedClient = client
        observesSystemCloud = client == nil
        self.originStore = originStore ?? KeychainSportsSyncWriterOriginStore()
        self.journalWriter = journalWriter ?? { data, key, defaults in defaults.set(data, forKey: key) }
        origin = defaults.string(forKey: localKey + ".origin").flatMap { UUID(uuidString: $0)?.uuidString } ?? UUID().uuidString
        let stored = defaults.data(forKey: localKey)
        let decoded = stored.flatMap { $0.count <= SportsSyncValidation.maximumJournalBytes
            ? try? JSONDecoder().decode([SportsPreferenceSyncRecord].self, from: $0) : nil } ?? []
        var journal: [String: SportsPreferenceSyncRecord] = [:]
        for record in decoded.prefix(SportsSyncValidation.maximumRecords) where SportsSyncValidation.encode(record) != nil {
            if journal[record.intent.id].map({ record.wins(over: $0) }) ?? true { journal[record.intent.id] = record }
        }
        records = journal.values.sorted { $0.intent.id < $1.intent.id }
        consentIdentity = defaults.data(forKey: localKey + ".account")
        enabled = defaults.bool(forKey: localKey + ".enabled")
        if !deferStartup { _ = prepareForUse() }
    }

    /// A re-entrant scene callback must wait for the next normal refresh rather
    /// than touching a partially prepared writer or starting another cloud client.
    @discardableResult
    func prepareForUse() -> Bool {
        if hasStarted { return true }
        guard !isStarting else { return false }
        isStarting = true
        defer { hasStarted = true; isStarting = false }
        _ = prepareWriter()
        if enabled, writerReady {
            if let savedIdentity = consentIdentity, let currentIdentity = self.client.accountIdentity,
               Self.sameAccount(savedIdentity, currentIdentity) {
                status = .waitingForICloud
            } else {
                enabled = false; status = .accountChanged
                defaults.set(false, forKey: localKey + ".enabled")
            }
        }
        if observesSystemCloud {
            observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: NSUbiquitousKeyValueStore.default, queue: .main) { [weak self] notification in
                    let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
                    Task { @MainActor in self?.receiveExternalChange(reason: reason) }
                }
            identityObserver = NotificationCenter.default.addObserver(forName: .NSUbiquityIdentityDidChange,
                object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.handleAccountChange() }
                }
        }
        return true
    }

    /// Explicit owner choice. No cloud operation occurs before this opt-in.
    /// Disable leaves both local setup and already-uploaded iCloud copies intact.
    func setEnabled(_ value: Bool) {
        guard prepareForUse() else { return }
        if !value {
            enabled = false; cloudAccessAvailable = false; status = .off; failureStage = nil
            defaults.set(false, forKey: localKey + ".enabled")
            return
        }
        guard writerReady || prepareWriter() else { return }
        guard let identity = client.accountIdentity else { status = .unavailable; failureStage = .accountIdentity; return }
        consentIdentity = identity
        defaults.set(identity, forKey: localKey + ".account")
        enabled = true; status = .waitingForICloud; failureStage = nil
        cloudAccessAvailable = false
        defaults.set(true, forKey: localKey + ".enabled")
        // The available cache is not a download-complete/delivery receipt.
        // Disjoint writer slots can queue safely without that nonexistent ACK.
        guard client.synchronize() else { status = .unavailable; failureStage = .cloudAttachment; return }
        cloudAccessAvailable = true
        reconcileCloud()
    }

    @discardableResult
    func upsert(_ intent: SportsPreferenceSyncIntent, now: Date = .init()) -> MutationResult {
        mutate(intent, removed: false, authority: .explicit, now: now)
    }
    @discardableResult
    func remove(intentID: String, now: Date = .init()) -> MutationResult {
        remove(intentID: intentID, authority: .explicit, now: now)
    }

    /// Passive domain snapshots cannot turn an unapplied, newly arrived cloud
    /// row into a newer echo. nil means no application receipt, not a bypass.
    @discardableResult
    func upsertFromAppliedSnapshot(_ intent: SportsPreferenceSyncIntent,
                                  expected: SportsPreferenceSyncRecord?, now: Date = .init()) -> MutationResult {
        mutate(intent, removed: false, authority: .applied(expected), now: now)
    }
    @discardableResult
    func removeFromAppliedSnapshot(intentID: String, expected: SportsPreferenceSyncRecord?,
                                   now: Date = .init()) -> MutationResult {
        remove(intentID: intentID, authority: .applied(expected), now: now)
    }

    private func remove(intentID: String, authority: MutationAuthority, now: Date) -> MutationResult {
        if let result = prepareMutation(intentID: intentID, authority: authority, now: now) { return result }
        guard let old = records.first(where: { $0.intent.id == intentID }) else { return .unchanged }
        return mutatePrepared(old.intent, removed: true, now: now)
    }

    private func mutate(_ intent: SportsPreferenceSyncIntent, removed: Bool,
                        authority: MutationAuthority, now: Date) -> MutationResult {
        guard intent.isValid() else { return .rejected }
        if let result = prepareMutation(intentID: intent.id, authority: authority, now: now) { return result }
        return mutatePrepared(intent, removed: removed, now: now)
    }

    private func prepareMutation(intentID: String, authority: MutationAuthority, now: Date) -> MutationResult? {
        guard prepareForUse() else { return .rejected }
        guard now.timeIntervalSince1970.isFinite else { return .rejected }
        guard writerReady else { status = .unavailable; return .rejected }
        if enabled, cloudAccessAvailable { reconcileCloud(publish: false) }
        if case .applied(let expected) = authority,
           records.first(where: { $0.intent.id == intentID }) != expected { return .applicationNeeded }
        return nil
    }

    private func mutatePrepared(_ intent: SportsPreferenceSyncIntent, removed: Bool, now: Date) -> MutationResult {
        if let old = records.first(where: { $0.intent.id == intent.id }), old.intent == intent, old.removed == removed { return .unchanged }
        let clock = records.map(\.revision).max() ?? 0
        guard clock < Int64.max - 1 else { return .storageFull }
        let record = SportsPreferenceSyncRecord(version: 1, intent: intent, revision: clock + 1,
                                               origin: origin, removed: removed, modifiedAt: now)
        var next = records.filter { $0.intent.id != intent.id }; next.append(record)
        guard commitLocal(next) else { return .storageFull }
        // A newly arrived cached higher revision is merged again before writes.
        if enabled, cloudAccessAvailable { reconcileCloud() }
        return .saved
    }

    func refresh() {
        guard prepareForUse() else { return }
        guard enabled, writerReady, acceptsCurrentAccount() else { return }
        guard client.synchronize() else { cloudAccessAvailable = false; status = .unavailable; failureStage = .cloudAttachment; return }
        cloudAccessAvailable = true
        reconcileCloud()
    }

    func receiveExternalChange(reason: Int?) {
        guard prepareForUse() else { return }
        if reason == NSUbiquitousKeyValueStoreAccountChange { handleAccountChange(); return }
        guard enabled, acceptsCurrentAccount() else { return }
        if reason == NSUbiquitousKeyValueStoreQuotaViolationChange { status = .quotaExceeded; return }
        guard reason == NSUbiquitousKeyValueStoreServerChange || reason == NSUbiquitousKeyValueStoreInitialSyncChange else { return }
        reconcileCloud()
    }

    func handleAccountChange() {
        // Preserve local intent, but never silently upload the previous account's
        // configuration to a newly selected Apple account.
        let wasEnabled = enabled
        enabled = false; cloudAccessAvailable = false; consentIdentity = nil; status = wasEnabled ? .accountChanged : .off
        failureStage = wasEnabled ? .accountChanged : nil
        defaults.set(false, forKey: localKey + ".enabled")
        defaults.removeObject(forKey: localKey + ".account")
    }

    private func acceptsCurrentAccount() -> Bool {
        guard let consentIdentity, let current = client.accountIdentity,
              Self.sameAccount(consentIdentity, current) else { handleAccountChange(); return false }
        return true
    }

    private static func sameAccount(_ lhs: Data, _ rhs: Data) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty, lhs.count <= 8 * 1024, rhs.count <= 8 * 1024 else { return false }
        if lhs == rhs { return true }
        // The opaque local Apple token's serialization is not its identity.
        // Use NSObject equality after decoding our own locally archived token.
        guard let left = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSObject.self], from: lhs) as? NSObject,
              let right = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSObject.self], from: rhs) as? NSObject else { return false }
        return left.isEqual(right)
    }

    /// Re-home only identifiable previous local writers. Secure+defaults rollback
    /// together is not detectable; no cross-device rollback protection is claimed.
    @discardableResult
    private func prepareWriter() -> Bool {
        do {
            let secure = try originStore.load()
            guard secure.map({ UUID(uuidString: $0)?.uuidString == $0 }) ?? true else { throw CocoaError(.fileReadCorruptFile) }
            let marker = defaults.string(forKey: localKey + ".writer-v2").flatMap { UUID(uuidString: $0)?.uuidString }
            let legacy = defaults.string(forKey: localKey + ".origin").flatMap { UUID(uuidString: $0)?.uuidString }
            let bindingChanged = secure == nil || marker == nil || secure != marker
            let selected = bindingChanged ? UUID().uuidString : secure!
            if bindingChanged {
                let wasEnabled = enabled
                enabled = false; cloudAccessAvailable = false
                defaults.set(false, forKey: localKey + ".enabled")
                status = wasEnabled ? .deviceChanged : .off
                // Keychain survives uninstall; absent local marker means rotate,
                // never reuse the former install's possibly newer cloud slot.
                try originStore.save(selected)
                guard try originStore.load() == selected else { throw CocoaError(.fileWriteUnknown) }
            }
            let previousLocal = Set([marker ?? legacy, secure].compactMap { $0 })
            let migrated = records.map { record in
                guard previousLocal.contains(record.origin), record.origin != selected else { return record }
                return SportsPreferenceSyncRecord(version: record.version, intent: record.intent,
                    revision: record.revision, origin: selected, removed: record.removed, modifiedAt: record.modifiedAt)
            }
            if migrated != records, !commitLocal(migrated) { throw CocoaError(.fileWriteUnknown) }
            defaults.set(selected, forKey: localKey + ".writer-v2")
            guard defaults.string(forKey: localKey + ".writer-v2") == selected else { throw CocoaError(.fileWriteUnknown) }
            origin = selected
            writerReady = true
            return true
        } catch {
            writerReady = false; enabled = false; cloudAccessAvailable = false; status = .unavailable; failureStage = .writerIdentity
            defaults.set(false, forKey: localKey + ".enabled")
            return false
        }
    }

    private func reconcileCloud(publish: Bool = true) {
        guard enabled, writerReady, cloudAccessAvailable, acceptsCurrentAccount() else { return }
        let cloud = client.values
        guard cloud.count <= SportsSyncValidation.maximumRecords,
              cloud.values.reduce(0, { $0 + $1.count }) <= SportsSyncValidation.maximumJournalBytes else {
            status = .quotaExceeded; return
        }
        var next = Dictionary(uniqueKeysWithValues: records.map { ($0.intent.id, $0) })
        for (key, data) in cloud {
            guard let remote = SportsSyncValidation.decode(data), SportsSyncValidation.acceptsCloudKey(key, record: remote) else {
                status = .invalidRemoteData; return
            }
            if let old = next[remote.intent.id] {
                guard !(remote.revision == old.revision && remote.origin == old.origin && remote != old) else {
                    status = .invalidRemoteData; return
                }
                if remote.wins(over: old) { next[remote.intent.id] = remote }
            } else { next[remote.intent.id] = remote }
        }
        guard commitLocal(Array(next.values)) else { status = .quotaExceeded; return }
        if publish { publishCurrentJournal(cached: cloud) }
    }

    private func publishCurrentJournal(cached current: [String: Data]) {
        guard enabled, writerReady, cloudAccessAvailable, acceptsCurrentAccount() else { return }
        var proposed = current
        var writes: [(String, Data)] = []
        // Received and legacy values retain their original slots. This writer
        // never publishes into another writer's or a shared legacy v1 key.
        for record in records where record.origin == origin {
            guard let data = SportsSyncValidation.encode(record) else { status = .quotaExceeded; return }
            let key = SportsSyncValidation.cloudSlotKey(for: record)
            if current[key].flatMap(SportsSyncValidation.decode) != record {
                proposed[key] = data
                writes.append((key, data))
            }
        }
        guard proposed.count <= SportsSyncValidation.maximumRecords,
              proposed.values.reduce(0, { $0 + $1.count }) <= SportsSyncValidation.maximumJournalBytes else {
            status = .quotaExceeded; return
        }
        for (key, data) in writes { client.set(data, forKey: key) }
        status = .updatesQueued; failureStage = nil
    }

    @discardableResult
    private func commitLocal(_ next: [SportsPreferenceSyncRecord]) -> Bool {
        let sorted = next.sorted { $0.intent.id < $1.intent.id }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard sorted.count <= SportsSyncValidation.maximumRecords,
              sorted.allSatisfy({ SportsSyncValidation.encode($0) != nil }),
              let data = try? encoder.encode(sorted), data.count <= SportsSyncValidation.maximumJournalBytes else { return false }
        if defaults.data(forKey: localKey) != data {
            do { try journalWriter(data, localKey, defaults) }
            catch { return false }
        }
        guard defaults.data(forKey: localKey) == data else { return false }
        if records != sorted { records = sorted }
        return true
    }
}
