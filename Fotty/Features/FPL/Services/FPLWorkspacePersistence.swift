import Foundation

struct FPLLocalSquadDraft: Codable, Sendable, Equatable {
    let picks: [FPLPick]
    let basedOnGameweek: Int?
    let targetGameweek: Int?
    let budgetLimit: Int?
}

/// Owns season/manager-scoped workspace persistence. Unknown-origin legacy
/// bytes stay untouched; a new confirmation cannot prove their owner or season.
/// Mutable UI state and network lifecycle remain in `FPLAdvisorViewModel`.
@MainActor
final class FPLWorkspacePersistence {
    private enum Key {
        static let legacyManagerID = "fotty.fpl.managerId"
        static let legacyDraft = "fotty.fpl.customDraftPicks"
        static let legacyCoachMessages = "fotty.fpl.coachMessages"
        static let smartCoachConsent = "fotty.fpl.smartCoachConsent"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func legacyManagerID(currentStoredID: Int) -> Int? {
        guard currentStoredID <= 0,
              let value = defaults.string(forKey: Key.legacyManagerID),
              let managerID = Int(value), managerID > 0 else { return nil }
        defaults.removeObject(forKey: Key.legacyManagerID)
        return managerID
    }

    func migrateLegacyWorkspace(managerID _: Int?) {
        // Unscoped old arrays contain neither owner nor season. Do not assign
        // them to reused current player/manager IDs or destroy recovery bytes.
        // Existing explicitly season/manager-scoped arrays remain loadable.
    }

    var hasUnverifiedLegacyWorkspace: Bool {
        defaults.data(forKey: Key.legacyDraft) != nil || defaults.data(forKey: Key.legacyCoachMessages) != nil
    }

    func loadDraft(managerID: Int?) -> FPLLocalSquadDraft? {
        guard let key = draftKey(managerID: managerID) else { return nil }
        let legacy = defaults.data(forKey: key).flatMap {
            try? JSONDecoder().decode([FPLPick].self, from: $0)
        }
        if let data = defaults.data(forKey: key + ".context"),
           let draft = try? JSONDecoder().decode(FPLLocalSquadDraft.self, from: data),
           legacy == nil || legacy == draft.picks {
            return draft
        }
        // Keep the build-43 array readable, including when returning to TestFlight.
        guard let picks = legacy, !picks.isEmpty else { return nil }
        return FPLLocalSquadDraft(
            picks: picks,
            basedOnGameweek: nil,
            targetGameweek: nil,
            budgetLimit: nil
        )
    }

    func saveDraft(_ draft: FPLLocalSquadDraft, managerID: Int?) throws {
        guard let key = draftKey(managerID: managerID) else {
            throw CocoaError(.fileNoSuchFile)
        }
        defaults.set(try JSONEncoder().encode(draft.picks), forKey: key)
        defaults.set(try JSONEncoder().encode(draft), forKey: key + ".context")
        defaults.set(false, forKey: key + ".showPublished")
    }

    func shouldShowPublishedSquad(managerID: Int?) -> Bool {
        guard let key = draftKey(managerID: managerID) else { return false }
        return defaults.bool(forKey: key + ".showPublished")
    }

    @discardableResult
    func setShowsPublishedSquad(_ showsPublished: Bool, managerID: Int?) -> Bool {
        guard let key = draftKey(managerID: managerID) else { return false }
        defaults.set(showsPublished, forKey: key + ".showPublished")
        return true
    }

    func loadCoachMessages(managerID: Int?) -> [AICoachMessage] {
        guard let key = coachMessagesKey(managerID: managerID),
              let data = defaults.data(forKey: key),
              let messages = try? JSONDecoder().decode([AICoachMessage].self, from: data) else {
            return []
        }
        return messages
    }

    func saveCoachMessages(_ messages: [AICoachMessage], managerID: Int?) {
        guard let key = coachMessagesKey(managerID: managerID),
              let data = try? JSONEncoder().encode(messages) else { return }
        defaults.set(data, forKey: key)
    }

    func clearCoachMessages(managerID: Int?) {
        guard let key = coachMessagesKey(managerID: managerID) else { return }
        defaults.removeObject(forKey: key)
    }

    var hasSmartCoachConsent: Bool {
        defaults.bool(forKey: Key.smartCoachConsent)
    }

    private func draftKey(managerID: Int?) -> String? {
        managerID.map {
            "fotty.fpl.\(FPLSeasonIdentifier.currentLabel()).manager.\($0).customDraftPicks"
        }
    }

    private func coachMessagesKey(managerID: Int?) -> String? {
        managerID.map {
            "fotty.fpl.\(FPLSeasonIdentifier.currentLabel()).manager.\($0).coachMessages"
        }
    }
}
