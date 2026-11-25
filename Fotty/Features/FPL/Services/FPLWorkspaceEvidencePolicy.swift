import Foundation

/// A numeric entry ID can belong to another team after a season rollover.
/// Only the explicit, previewed Connect action records a confirmation.
@MainActor
final class FPLManagerSeasonStore {
    private struct Confirmation: Codable { let managerID: Int; let season: String }
    private static let key = "fotty.fpl.managerConfirmation.v1"
    private let defaults: UserDefaults
    init(defaults: UserDefaults) { self.defaults = defaults }

    func needsConfirmation(managerID: Int, at date: Date) -> Bool {
        guard let data = defaults.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(Confirmation.self, from: data) else { return true }
        return value.managerID != managerID || value.season != FPLSeasonIdentifier.currentLabel(at: date)
    }

    func confirm(managerID: Int, at date: Date) {
        guard managerID > 0,
              let data = try? JSONEncoder().encode(Confirmation(managerID: managerID,
                season: FPLSeasonIdentifier.currentLabel(at: date))) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func clear() { defaults.removeObject(forKey: Self.key) }
}

enum FPLPlayerEvidencePolicy {
    static let maximumAge: TimeInterval = 300
    static func isCurrent(_ metadata: FPLResourceMetadata?, at date: Date) -> Bool {
        guard let metadata, metadata.source != .diskSnapshot else { return false }
        let age = date.timeIntervalSince(metadata.fetchedAt)
        return age >= -5 && age <= maximumAge
    }
}
