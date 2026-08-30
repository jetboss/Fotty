import Foundation

@MainActor
public enum FPLScenarioStore {
    private static let maximumScenarios = 12

    public static func load(
        managerID: Int,
        defaults: UserDefaults = .standard
    ) -> [FPLSavedScenario] {
        guard let data = defaults.data(forKey: key(managerID: managerID)),
              let decoded = try? JSONDecoder().decode([FPLSavedScenario].self, from: data) else {
            return []
        }
        return decoded
            .filter { $0.managerID == managerID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    public static func upsert(
        _ scenario: FPLSavedScenario,
        defaults: UserDefaults = .standard
    ) -> [FPLSavedScenario] {
        var values = load(managerID: scenario.managerID, defaults: defaults)
        values.removeAll { $0.id == scenario.id }
        values.insert(scenario, at: 0)
        values = Array(values.prefix(maximumScenarios))
        persist(values, managerID: scenario.managerID, defaults: defaults)
        return values
    }

    @discardableResult
    public static func remove(
        id: String,
        managerID: Int,
        defaults: UserDefaults = .standard
    ) -> [FPLSavedScenario] {
        let values = load(managerID: managerID, defaults: defaults).filter { $0.id != id }
        persist(values, managerID: managerID, defaults: defaults)
        return values
    }

    private static func persist(
        _ values: [FPLSavedScenario],
        managerID: Int,
        defaults: UserDefaults
    ) {
        if let encoded = try? JSONEncoder().encode(values) {
            defaults.set(encoded, forKey: key(managerID: managerID))
        }
    }

    private static func key(managerID: Int) -> String {
        "fotty.fpl.\(FPLSeasonIdentifier.currentLabel()).manager.\(managerID).planning-scenarios"
    }
}

@MainActor
public enum FPLDecisionJournalStore {
    public static func load(
        managerID: Int,
        season: String = FPLSeasonIdentifier.currentLabel(),
        defaults: UserDefaults = .standard
    ) -> [FPLDecisionJournalEntry] {
        guard let data = defaults.data(forKey: key(managerID: managerID, season: season)),
              let entries = try? JSONDecoder().decode([FPLDecisionJournalEntry].self, from: data) else {
            return []
        }
        return entries
            .filter { $0.managerID == managerID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    public static func upsert(
        _ entry: FPLDecisionJournalEntry,
        managerID: Int,
        season: String = FPLSeasonIdentifier.currentLabel(),
        defaults: UserDefaults = .standard
    ) -> [FPLDecisionJournalEntry] {
        guard entry.managerID == managerID else {
            return load(managerID: managerID, season: season, defaults: defaults)
        }
        var entries = load(managerID: managerID, season: season, defaults: defaults)
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        return persist(entries, managerID: managerID, season: season, defaults: defaults)
    }

    @discardableResult
    public static func remove(
        id: String,
        managerID: Int,
        season: String = FPLSeasonIdentifier.currentLabel(),
        defaults: UserDefaults = .standard
    ) -> [FPLDecisionJournalEntry] {
        let entries = load(managerID: managerID, season: season, defaults: defaults)
            .filter { $0.id != id }
        return persist(entries, managerID: managerID, season: season, defaults: defaults)
    }

    private static func persist(
        _ entries: [FPLDecisionJournalEntry],
        managerID: Int,
        season: String,
        defaults: UserDefaults
    ) -> [FPLDecisionJournalEntry] {
        let bounded = Array(entries.sorted { $0.updatedAt > $1.updatedAt }.prefix(120))
        if let data = try? JSONEncoder().encode(bounded) {
            defaults.set(data, forKey: key(managerID: managerID, season: season))
        }
        return bounded
    }

    private static func key(managerID: Int, season: String) -> String {
        "fotty.fpl.\(season).manager.\(managerID).decisionJournal"
    }
}
