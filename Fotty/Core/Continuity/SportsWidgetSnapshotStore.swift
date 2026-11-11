import Foundation
import WidgetKit

@MainActor
enum SportsWidgetSnapshotStore {
    static let widgetKind = "FottySportsPlanWidget"

    /// Shared storage must be signed with this exact capability. Never fall
    /// back to a normal defaults suite and report that the extension received it.
    @discardableResult
    static func write(snapshot: SportsWidgetSnapshot) -> Bool {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SportsWidgetSnapshot.appGroup) != nil,
              let defaults = UserDefaults(suiteName: SportsWidgetSnapshot.appGroup),
              let data = snapshot.validatedData() else { return false }
        if defaults.data(forKey: SportsWidgetSnapshot.storageKey) == data { return true }
        defaults.set(data, forKey: SportsWidgetSnapshot.storageKey)
        guard defaults.data(forKey: SportsWidgetSnapshot.storageKey) == data else { return false }
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        return true
    }
}
