import CryptoKit
import Foundation
import SwiftData
import UserNotifications

enum FottyPrivateBackupError: LocalizedError, Equatable {
    case passwordTooShort
    case passwordTooLong
    case fileTooLarge
    case unsupportedFormat
    case invalidPasswordOrDamagedFile
    case invalidBackup(String)

    var errorDescription: String? {
        switch self {
        case .passwordTooShort:
            return "Use a backup password with at least 12 characters."
        case .passwordTooLong:
            return "The backup password must be 256 characters or fewer."
        case .fileTooLarge:
            return "That backup is larger than Fotty's 10 MB safety limit."
        case .unsupportedFormat:
            return "That file is not a supported Fotty private backup."
        case .invalidPasswordOrDamagedFile:
            return "The password is incorrect or the backup is damaged."
        case .invalidBackup(let detail):
            return "Fotty did not change anything because the backup is invalid: \(detail)"
        }
    }
}

struct FottyPrivateBackupEnvelope: Codable, Sendable, Equatable {
    static let format = "com.jelani.fotty.private-backup"
    static let currentVersion = 1

    let format: String
    let version: Int
    let createdAt: Date
    let kdf: KDF
    let cipher: Cipher

    struct KDF: Codable, Sendable, Equatable {
        let algorithm: String
        let iterations: Int
        let salt: Data
    }

    struct Cipher: Codable, Sendable, Equatable {
        let algorithm: String
        let sealedData: Data
    }
}

struct FottyPrivateBackupPayload: Codable, Sendable, Equatable {
    static let currentVersion = 1

    let version: Int
    let createdAt: Date
    let appVersion: String
    let appBuild: String
    let preferences: Preferences
    let followedTeams: [FollowedTeam]
    let followedLeagues: [FollowedLeague]
    let savedMatches: [SavedMatch]
    let fpl: FPLState?

    struct Preferences: Codable, Sendable, Equatable {
        let appearance: String
        let preferredSport: String
        let favoriteTeams: [String]
        let kickoffUpdates: Bool
        let goalUpdates: Bool
        let fullTimeUpdates: Bool
        let spoilerProtection: Bool
        /// Optional so version-one backups created before personalized Home
        /// remain decodable and restore to the broad catalog default.
        let onlyShowSelectedHomeInterests: Bool?
        /// Missing in older backups: keep the optional Matchday hint off.
        let showKickoffClashes: Bool?
        /// Additive to version one; old backups contain no whole-sport choices.
        var followedSportIDs: [String]? = nil
    }

    struct FollowedTeam: Codable, Sendable, Equatable {
        let key: String
        let teamName: String
        let sportCategory: String
        let alertsEnabled: Bool
        let createdAt: Date
    }

    struct FollowedLeague: Codable, Sendable, Equatable {
        let id: String
        let leagueName: String
        let sportCategory: String
        let country: String?
        let createdAt: Date
    }

    /// Deliberately excludes poster, badge and provider/source URLs. A fresh
    /// catalog may enrich this identity after restore; the backup never carries
    /// stale playback routes to another device.
    struct SavedMatch: Codable, Sendable, Equatable {
        let id: String
        let title: String?
        let category: String?
        let date: Int64?
        let popular: Bool?
        let homeName: String
        let awayName: String
        let savedAt: Date
    }

    struct FPLState: Codable, Sendable, Equatable {
        let managerID: Int
        let season: String
        let localDraft: FPLLocalSquadDraft?
        let showsPublishedSquad: Bool
        let scenarios: [FPLSavedScenario]
        let decisionJournal: [FPLDecisionJournalEntry]
        let reviews: [FPLGameweekReview]
        let coachProfile: FPLCoachProfile
    }
}

struct FottyPrivateBackupSummary: Sendable, Equatable {
    let createdAt: Date
    let appVersion: String
    let appBuild: String
    let followedTeams: Int
    let followedLeagues: Int
    let savedMatches: Int
    let managerID: Int?
    let season: String?
    let fplPlans: Int

    init(payload: FottyPrivateBackupPayload) {
        createdAt = payload.createdAt
        appVersion = payload.appVersion
        appBuild = payload.appBuild
        followedTeams = payload.followedTeams.count
        followedLeagues = payload.followedLeagues.count
        savedMatches = payload.savedMatches.count
        managerID = payload.fpl?.managerID
        season = payload.fpl?.season
        fplPlans = (payload.fpl?.scenarios.count ?? 0)
            + (payload.fpl?.decisionJournal.count ?? 0)
            + (payload.fpl?.reviews.count ?? 0)
            + (payload.fpl?.localDraft == nil ? 0 : 1)
    }
}

enum FottyPrivateBackupCrypto {
    static let productionIterations = 120_000
    static let maximumFileBytes = 10 * 1_024 * 1_024
    private static let maximumPlaintextBytes = 5 * 1_024 * 1_024

    static func seal(
        _ payload: FottyPrivateBackupPayload,
        password: String,
        iterations: Int = productionIterations,
        salt suppliedSalt: Data? = nil,
        nonce suppliedNonce: AES.GCM.Nonce? = nil
    ) throws -> Data {
        try validatePassword(password)
        guard iterations > 0, iterations <= 500_000 else {
            throw FottyPrivateBackupError.unsupportedFormat
        }
        let plaintext = try JSONEncoder.fottyBackup.encode(payload)
        guard plaintext.count <= maximumPlaintextBytes else {
            throw FottyPrivateBackupError.fileTooLarge
        }
        let salt = suppliedSalt ?? randomData(count: 16)
        guard salt.count == 16 else { throw FottyPrivateBackupError.unsupportedFormat }
        let key = pbkdf2SHA256(password: password, salt: salt, iterations: iterations)
        let box = try AES.GCM.seal(plaintext, using: key, nonce: suppliedNonce)
        guard let combined = box.combined else { throw FottyPrivateBackupError.unsupportedFormat }
        let envelope = FottyPrivateBackupEnvelope(
            format: FottyPrivateBackupEnvelope.format,
            version: FottyPrivateBackupEnvelope.currentVersion,
            createdAt: payload.createdAt,
            kdf: .init(algorithm: "PBKDF2-HMAC-SHA256", iterations: iterations, salt: salt),
            cipher: .init(algorithm: "AES-256-GCM", sealedData: combined)
        )
        let encoded = try JSONEncoder.fottyBackup.encode(envelope)
        guard encoded.count <= maximumFileBytes else { throw FottyPrivateBackupError.fileTooLarge }
        return encoded
    }

    static func open(
        _ data: Data,
        password: String,
        minimumIterations: Int = 50_000
    ) throws -> FottyPrivateBackupPayload {
        try validatePassword(password)
        guard data.count <= maximumFileBytes else { throw FottyPrivateBackupError.fileTooLarge }
        guard let envelope = try? JSONDecoder.fottyBackup.decode(FottyPrivateBackupEnvelope.self, from: data),
              envelope.format == FottyPrivateBackupEnvelope.format,
              envelope.version == FottyPrivateBackupEnvelope.currentVersion,
              envelope.kdf.algorithm == "PBKDF2-HMAC-SHA256",
              envelope.cipher.algorithm == "AES-256-GCM",
              envelope.kdf.salt.count == 16,
              envelope.kdf.iterations >= minimumIterations,
              envelope.kdf.iterations <= 500_000 else {
            throw FottyPrivateBackupError.unsupportedFormat
        }

        do {
            let key = pbkdf2SHA256(
                password: password,
                salt: envelope.kdf.salt,
                iterations: envelope.kdf.iterations
            )
            let box = try AES.GCM.SealedBox(combined: envelope.cipher.sealedData)
            let plaintext = try AES.GCM.open(box, using: key)
            guard plaintext.count <= maximumPlaintextBytes else {
                throw FottyPrivateBackupError.fileTooLarge
            }
            let payload = try JSONDecoder.fottyBackup.decode(FottyPrivateBackupPayload.self, from: plaintext)
            try FottyPrivateBackupService.validate(payload)
            return payload
        } catch let error as FottyPrivateBackupError {
            throw error
        } catch {
            throw FottyPrivateBackupError.invalidPasswordOrDamagedFile
        }
    }

    private static func validatePassword(_ password: String) throws {
        guard password.count >= 12 else { throw FottyPrivateBackupError.passwordTooShort }
        guard password.count <= 256 else { throw FottyPrivateBackupError.passwordTooLong }
    }

    /// RFC 8018 PBKDF2 with HMAC-SHA256. A single 32-byte block is enough for
    /// the AES-256 key. Production backups use 120,000 iterations.
    private static func pbkdf2SHA256(password: String, salt: Data, iterations: Int) -> SymmetricKey {
        let passwordKey = SymmetricKey(data: Data(password.utf8))
        var blockSalt = salt
        var blockIndex = UInt32(1).bigEndian
        withUnsafeBytes(of: &blockIndex) { blockSalt.append(contentsOf: $0) }

        var previous = Data(HMAC<SHA256>.authenticationCode(for: blockSalt, using: passwordKey))
        var derived = [UInt8](previous)
        if iterations > 1 {
            for _ in 1..<iterations {
                previous = Data(HMAC<SHA256>.authenticationCode(for: previous, using: passwordKey))
                for index in derived.indices { derived[index] ^= previous[index] }
            }
        }
        return SymmetricKey(data: Data(derived))
    }

    private static func randomData(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}

@MainActor
enum FottyPrivateBackupService {
    static let restoredNotification = Notification.Name("fotty.privateBackupRestored")

    static func capture(
        modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        matchday suppliedMatchday: MyMatchdayStore? = nil,
        now: Date = Date(),
        bundle: Bundle = .main
    ) throws -> FottyPrivateBackupPayload {
        let matchday = suppliedMatchday ?? .shared
        let teams = try modelContext.fetch(FetchDescriptor<FollowedTeamItem>())
            .sorted { $0.createdAt < $1.createdAt }
            .map {
                FottyPrivateBackupPayload.FollowedTeam(
                    key: $0.key,
                    teamName: $0.teamName,
                    sportCategory: $0.sportCategory,
                    alertsEnabled: $0.alertsEnabled ?? true,
                    createdAt: $0.createdAt
                )
            }
        let leagues = try modelContext.fetch(FetchDescriptor<FollowedLeagueItem>())
            .sorted { $0.createdAt < $1.createdAt }
            .map {
                FottyPrivateBackupPayload.FollowedLeague(
                    id: $0.id,
                    leagueName: $0.leagueName,
                    sportCategory: $0.sportCategory,
                    country: $0.country,
                    createdAt: $0.createdAt
                )
            }
        let saved = matchday.savedMatches.map {
            FottyPrivateBackupPayload.SavedMatch(
                id: $0.id,
                title: $0.title,
                category: $0.category,
                date: $0.date,
                popular: $0.popular,
                homeName: $0.homeName,
                awayName: $0.awayName,
                savedAt: $0.savedAt
            )
        }

        let managerID = defaults.integer(forKey: "fotty.user.fplManagerId")
        let fpl = managerID > 0 ? captureFPL(managerID: managerID, defaults: defaults) : nil
        var preferences = FottyPrivateBackupPayload.Preferences(
            appearance: FottyAppearance.saved(defaults.string(forKey: FottyAppearance.storageKey) ?? "dark").rawValue,
            preferredSport: defaults.string(forKey: "fotty.user.preferredSport") ?? "football",
            favoriteTeams: (defaults.stringArray(forKey: "fotty.user.favoriteTeams") ?? []).sorted(),
            kickoffUpdates: bool(defaults, key: "settings.notif.kickoff", fallback: true),
            goalUpdates: bool(defaults, key: "settings.notif.goals", fallback: true),
            fullTimeUpdates: bool(defaults, key: "settings.notif.fulltime", fallback: true),
            spoilerProtection: bool(defaults, key: "settings.spoiler.protection", fallback: false),
            onlyShowSelectedHomeInterests: bool(
                defaults,
                key: HomeInterestPreferences.onlyShowSelectedKey,
                fallback: false
            ),
            showKickoffClashes: MatchdayPreferences.showsKickoffClashes(in: defaults)
        )
        preferences.followedSportIDs = try SportsInterestPreferences.validatedIDs(in: defaults).sorted()
        let payload = FottyPrivateBackupPayload(
            version: FottyPrivateBackupPayload.currentVersion,
            createdAt: now,
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
            appBuild: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown",
            preferences: preferences,
            followedTeams: teams,
            followedLeagues: leagues,
            savedMatches: saved,
            fpl: fpl
        )
        try validate(payload)
        return payload
    }

    @discardableResult
    static func restore(
        _ payload: FottyPrivateBackupPayload,
        modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) throws -> FottyPrivateBackupSummary {
        try restore(
            payload,
            modelContext: modelContext,
            defaults: defaults,
            matchday: .shared,
            reminderStore: .shared,
            now: now
        )
    }

    @discardableResult
    static func restore(
        _ payload: FottyPrivateBackupPayload,
        modelContext: ModelContext,
        defaults: UserDefaults,
        matchday: MyMatchdayStore,
        reminderStore: MatchReminderStore?,
        now: Date = Date()
    ) throws -> FottyPrivateBackupSummary {
        try validate(payload)

        let previousMatches = matchday.savedMatches
        let restoredMatches = payload.savedMatches.map { value in
            SavedMatchRecord(
                id: value.id,
                title: value.title,
                category: value.category,
                date: value.date,
                poster: nil,
                popular: value.popular,
                homeName: value.homeName,
                awayName: value.awayName,
                homeBadge: nil,
                awayBadge: nil,
                savedAt: value.savedAt
            )
        }
        if let message = matchday.replaceForRestore(restoredMatches).errorMessage {
            throw FottyPrivateBackupError.invalidBackup("saved Matchday items could not be stored: \(message)")
        }

        do {
            let existingTeams = try modelContext.fetch(FetchDescriptor<FollowedTeamItem>())
            let teamsByKey = Dictionary(uniqueKeysWithValues: existingTeams.map { ($0.key, $0) })
            let restoredTeamKeys = Set(payload.followedTeams.map(\.key))
            for existing in existingTeams where !restoredTeamKeys.contains(existing.key) {
                modelContext.delete(existing)
            }
            for team in payload.followedTeams {
                if let existing = teamsByKey[team.key] {
                    existing.teamName = team.teamName
                    existing.sportCategory = team.sportCategory
                    existing.badgeURLString = nil
                    existing.alertsEnabled = team.alertsEnabled
                    existing.createdAt = team.createdAt
                } else {
                    modelContext.insert(FollowedTeamItem(
                        key: team.key,
                        teamName: team.teamName,
                        sportCategory: team.sportCategory,
                        badgeURLString: nil,
                        alertsEnabled: team.alertsEnabled,
                        createdAt: team.createdAt
                    ))
                }
            }

            let existingLeagues = try modelContext.fetch(FetchDescriptor<FollowedLeagueItem>())
            let leaguesByID = Dictionary(uniqueKeysWithValues: existingLeagues.map { ($0.id, $0) })
            let restoredLeagueIDs = Set(payload.followedLeagues.map(\.id))
            for existing in existingLeagues where !restoredLeagueIDs.contains(existing.id) {
                modelContext.delete(existing)
            }
            for league in payload.followedLeagues {
                if let existing = leaguesByID[league.id] {
                    existing.leagueName = league.leagueName
                    existing.sportCategory = league.sportCategory
                    existing.country = league.country
                    existing.createdAt = league.createdAt
                } else {
                    modelContext.insert(FollowedLeagueItem(
                        id: league.id,
                        leagueName: league.leagueName,
                        sportCategory: league.sportCategory,
                        country: league.country,
                        createdAt: league.createdAt
                    ))
                }
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            let rollback = matchday.replaceForRestore(previousMatches)
            if let message = rollback.errorMessage {
                throw FottyPrivateBackupError.invalidBackup(
                    "followed teams or leagues could not be restored, and Matchday rollback failed: \(message)"
                )
            }
            throw FottyPrivateBackupError.invalidBackup("followed teams or leagues could not be restored")
        }

        apply(payload.preferences, defaults: defaults)
        reminderStore?.cancelAllForRestore()
        if defaults === UserDefaults.standard {
            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.removeAllPendingNotificationRequests()
            notificationCenter.removeAllDeliveredNotifications()
        }
        applyFPL(payload.fpl, defaults: defaults)

        // Consent never transfers. The restored manager must opt in again.
        defaults.set(false, forKey: "fotty.fpl.smartCoachConsent")
        defaults.set(false, forKey: "fotty.insights.aiConsentAccepted")
        defaults.removeObject(forKey: "fotty.fpl.matchday-context")

        if defaults === UserDefaults.standard {
            UserProfileStore.shared.preferredSport = payload.preferences.preferredSport
            UserProfileStore.shared.favoriteTeams = Set(payload.preferences.favoriteTeams)
            UserProfileStore.shared.fplManagerId = payload.fpl?.managerID
        }
        NotificationCenter.default.post(name: restoredNotification, object: nil)
        return FottyPrivateBackupSummary(payload: payload)
    }

    nonisolated static func validate(_ payload: FottyPrivateBackupPayload) throws {
        guard payload.version == FottyPrivateBackupPayload.currentVersion else {
            throw FottyPrivateBackupError.unsupportedFormat
        }
        guard payload.followedTeams.count <= 100,
              payload.followedLeagues.count <= 100,
              payload.savedMatches.count <= 100 else {
            throw FottyPrivateBackupError.invalidBackup("too many saved items")
        }
        guard FottyAppearance(rawValue: payload.preferences.appearance) != nil,
              isSafe(payload.preferences.preferredSport, maximum: 80),
              payload.preferences.favoriteTeams.count <= 100,
              payload.preferences.favoriteTeams.allSatisfy({ isSafe($0, maximum: 120) }) else {
            throw FottyPrivateBackupError.invalidBackup("preferences are not valid")
        }
        guard unique(payload.followedTeams.map(\.key)),
              unique(payload.followedLeagues.map(\.id)),
              unique(payload.savedMatches.map(\.id)) else {
            throw FottyPrivateBackupError.invalidBackup("duplicate saved identities")
        }
        if let sports = payload.preferences.followedSportIDs {
            guard sports.count <= SportsInterestPreferences.supportedIDs.count,
                  unique(sports), Set(sports).isSubset(of: SportsInterestPreferences.supportedIDs) else {
                throw FottyPrivateBackupError.invalidBackup("whole-sport interests are not valid")
            }
        }
        for team in payload.followedTeams {
            guard isSafe(team.key, maximum: 240), isSafe(team.teamName, maximum: 120),
                  isSafe(team.sportCategory, maximum: 80) else {
                throw FottyPrivateBackupError.invalidBackup("a followed team is not valid")
            }
        }
        for league in payload.followedLeagues {
            guard isSafe(league.id, maximum: 200), isSafe(league.leagueName, maximum: 140),
                  isSafe(league.sportCategory, maximum: 80),
                  league.country.map({ isSafe($0, maximum: 100) }) ?? true else {
                throw FottyPrivateBackupError.invalidBackup("a followed league is not valid")
            }
        }
        for match in payload.savedMatches {
            guard isSafe(match.id, maximum: 300), isSafe(match.homeName, maximum: 160),
                  isSafe(match.awayName, maximum: 160),
                  match.title.map({ isSafe($0, maximum: 320) }) ?? true,
                  match.category.map({ isSafe($0, maximum: 120) }) ?? true else {
                throw FottyPrivateBackupError.invalidBackup("a saved match is not valid")
            }
        }
        if let fpl = payload.fpl {
            guard fpl.managerID > 0, isSafe(fpl.season, maximum: 24),
                  fpl.scenarios.count <= 12, fpl.decisionJournal.count <= 120,
                  fpl.reviews.count <= 100,
                  fpl.scenarios.allSatisfy({ $0.managerID == fpl.managerID }),
                  fpl.decisionJournal.allSatisfy({ $0.managerID == fpl.managerID }) else {
                throw FottyPrivateBackupError.invalidBackup("FPL data is not valid")
            }
        }
    }

    private static func captureFPL(managerID: Int, defaults: UserDefaults) -> FottyPrivateBackupPayload.FPLState {
        let season = FPLSeasonIdentifier.currentLabel()
        let draftKey = fplKey(season: season, managerID: managerID, suffix: "customDraftPicks")
        let draft: FPLLocalSquadDraft? = {
            if let data = defaults.data(forKey: draftKey + ".context"),
               let value = try? JSONDecoder().decode(FPLLocalSquadDraft.self, from: data) { return value }
            guard let data = defaults.data(forKey: draftKey),
                  let picks = try? JSONDecoder().decode([FPLPick].self, from: data), !picks.isEmpty else { return nil }
            return FPLLocalSquadDraft(picks: picks, basedOnGameweek: nil, targetGameweek: nil, budgetLimit: nil)
        }()
        let reviews = decode([FPLGameweekReview].self, defaults: defaults,
            key: fplKey(season: season, managerID: managerID, suffix: "reviews")) ?? []
        let profile = decode(FPLCoachProfile.self, defaults: defaults,
            key: fplKey(season: season, managerID: managerID, suffix: "coachProfile")) ?? .default
        return .init(
            managerID: managerID,
            season: season,
            localDraft: draft,
            showsPublishedSquad: defaults.bool(forKey: draftKey + ".showPublished"),
            scenarios: FPLScenarioStore.load(managerID: managerID, defaults: defaults),
            decisionJournal: FPLDecisionJournalStore.load(managerID: managerID, season: season, defaults: defaults),
            reviews: reviews.sorted { $0.gameweek > $1.gameweek },
            coachProfile: profile
        )
    }

    private static func apply(_ preferences: FottyPrivateBackupPayload.Preferences, defaults: UserDefaults) {
        defaults.set(SportsInterestPreferences.encodedValue(for: Set(preferences.followedSportIDs ?? []))
                     ?? SportsInterestPreferences.emptyValue, forKey: SportsInterestPreferences.storageKey)
        defaults.set(preferences.appearance, forKey: FottyAppearance.storageKey)
        defaults.set(preferences.preferredSport, forKey: "fotty.user.preferredSport")
        defaults.set(preferences.favoriteTeams, forKey: "fotty.user.favoriteTeams")
        defaults.set(preferences.kickoffUpdates, forKey: "settings.notif.kickoff")
        defaults.set(preferences.goalUpdates, forKey: "settings.notif.goals")
        defaults.set(preferences.fullTimeUpdates, forKey: "settings.notif.fulltime")
        defaults.set(preferences.spoilerProtection, forKey: "settings.spoiler.protection")
        defaults.set(
            preferences.onlyShowSelectedHomeInterests ?? false,
            forKey: HomeInterestPreferences.onlyShowSelectedKey
        )
        defaults.set(
            preferences.showKickoffClashes ?? MatchdayPreferences.defaultShowKickoffClashes,
            forKey: MatchdayPreferences.showKickoffClashesKey
        )
    }

    private static func applyFPL(_ fpl: FottyPrivateBackupPayload.FPLState?, defaults: UserDefaults) {
        // Unfinished transfer staging is not part of this reviewed backup.
        // Do not let a retained pre-restore staging record override the restore.
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix("fotty.fpl.") && key.hasSuffix(".transferStaging") {
            defaults.removeObject(forKey: key)
        }
        guard let fpl else {
            defaults.removeObject(forKey: "fotty.user.fplManagerId")
            return
        }
        defaults.set(fpl.managerID, forKey: "fotty.user.fplManagerId")
        let draftKey = fplKey(season: fpl.season, managerID: fpl.managerID, suffix: "customDraftPicks")
        setEncoded(fpl.localDraft?.picks, defaults: defaults, key: draftKey)
        setEncoded(fpl.localDraft, defaults: defaults, key: draftKey + ".context")
        defaults.set(fpl.showsPublishedSquad, forKey: draftKey + ".showPublished")
        setEncoded(fpl.scenarios, defaults: defaults,
            key: fplKey(season: fpl.season, managerID: fpl.managerID, suffix: "planning-scenarios"))
        setEncoded(fpl.decisionJournal, defaults: defaults,
            key: fplKey(season: fpl.season, managerID: fpl.managerID, suffix: "decisionJournal"))
        setEncoded(fpl.reviews, defaults: defaults,
            key: fplKey(season: fpl.season, managerID: fpl.managerID, suffix: "reviews"))
        setEncoded(fpl.coachProfile, defaults: defaults,
            key: fplKey(season: fpl.season, managerID: fpl.managerID, suffix: "coachProfile"))
        defaults.removeObject(forKey: fplKey(season: fpl.season, managerID: fpl.managerID, suffix: "coachMessages"))
    }

    private static func fplKey(season: String, managerID: Int, suffix: String) -> String {
        "fotty.fpl.\(season).manager.\(managerID).\(suffix)"
    }

    private static func setEncoded<T: Encodable>(_ value: T?, defaults: UserDefaults, key: String) {
        guard let value else { defaults.removeObject(forKey: key); return }
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func bool(_ defaults: UserDefaults, key: String, fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    nonisolated private static func unique(_ values: [String]) -> Bool { Set(values).count == values.count }

    nonisolated private static func isSafe(_ value: String, maximum: Int) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maximum && !trimmed.contains("\0")
    }
}

private extension JSONEncoder {
    static var fottyBackup: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var fottyBackup: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
