import Foundation

/// Official bootstrap allocations own the season windows. Supplementary rules
/// checked 2026-09-04: https://www.premierleague.com/en/news/4679879 and
/// https://www.premierleague.com/en/news/2174900 . No private activation is inferred.
public enum FPLChipAvailabilityPolicy {
    public enum Status: String, Sendable {
        case eligible = "WITHIN WINDOW"
        case used = "USED"
        case upcoming = "LATER WINDOW"
        case expired = "EXPIRED"
        case blocked = "NOT ELIGIBLE"
        case deadlinePassed = "DEADLINE PASSED"
        case unknown = "CHECK IN FPL"
    }

    public struct Availability: Equatable, Sendable {
        public let status: Status
        public let explanation: String
    }

    public static func availability(
        chip: FPLChipDefinition, targetGameweek: Int?, events: [FPLGameweek],
        usages: [FPLChipUsage]?, managerStartedEvent: Int?, now: Date = Date()
    ) -> Availability {
        guard !events.isEmpty, events.contains(where: { $0.deadlineDate != nil }),
              FPLSeasonIdentifier.label(from: events) == FPLSeasonIdentifier.currentLabel(at: now) else {
            return .init(status: .unknown, explanation: "Current-season chip evidence is unavailable. Refresh FPL before planning this chip.")
        }
        guard let targetGameweek, let event = events.first(where: { $0.id == targetGameweek }),
              chip.startEvent > 0, chip.stopEvent >= chip.startEvent, chip.number > 0,
              events.contains(where: { $0.id == chip.startEvent }), events.contains(where: { $0.id == chip.stopEvent }) else {
            return .init(status: .unknown, explanation: "No valid target gameweek or official allocation is available.")
        }
        let name = normalized(chip.name)
        guard ["wildcard", "freehit", "bboost", "3xc"].contains(name) else {
            return .init(status: .unknown, explanation: "Fotty has not verified the extra rules for this chip. Check official FPL.")
        }
        let matchingUsages = usages?.filter {
            normalized($0.name) == name && (chip.startEvent...chip.stopEvent).contains($0.event)
        } ?? []
        if Set(matchingUsages.map(\.event)).count >= chip.number {
            return .init(status: .used, explanation: "This allocation is recorded as used in public manager history.")
        }
        if targetGameweek > chip.stopEvent {
            return .init(status: .expired, explanation: "This allocation ended at the GW\(chip.stopEvent) deadline; it cannot carry into GW\(targetGameweek).")
        }
        if targetGameweek < chip.startEvent {
            return .init(status: .upcoming, explanation: "This allocation starts in GW\(chip.startEvent), not GW\(targetGameweek).")
        }
        guard let deadline = event.deadlineDate else {
            return .init(status: .unknown, explanation: "The target deadline is unavailable.")
        }
        guard now < deadline else {
            return .init(status: .deadlinePassed, explanation: "The GW\(targetGameweek) deadline has passed. A local plan cannot activate an official chip.")
        }
        guard ["2025-26", "2026-27"].contains(FPLSeasonIdentifier.label(from: events)) else {
            return .init(status: .unknown, explanation: "The allocation window is published, but this season's additional chip rules need verification.")
        }
        if name == "wildcard" || name == "freehit" {
            guard let managerStartedEvent, events.contains(where: { $0.id == managerStartedEvent }) else {
                return .init(status: .unknown, explanation: "Your opening gameweek is unknown; Wildcard and Free Hit are unavailable for that first gameweek.")
            }
            if targetGameweek <= managerStartedEvent {
                return .init(status: .blocked, explanation: "Wildcard and Free Hit cannot be used in your opening gameweek, when transfers are unlimited.")
            }
        }
        guard let usages else {
            return .init(status: .unknown, explanation: "The target is inside the official window, but your chip usage history is unavailable.")
        }
        if usages.contains(where: { $0.event == targetGameweek }) {
            return .init(status: .blocked, explanation: "Public history records another chip in GW\(targetGameweek). Only one chip may be played per gameweek.")
        }
        if name == "freehit", usages.contains(where: { normalized($0.name) == name && abs($0.event - targetGameweek) == 1 }) {
            return .init(status: .blocked, explanation: "Free Hit cannot be played in consecutive gameweeks, including GW19 followed by GW20.")
        }
        return .init(status: .eligible, explanation: "GW\(targetGameweek) is inside this unused public allocation. Confirm pending chip choices and availability in official FPL.")
    }

    public static func normalized(_ value: String) -> String {
        value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }
}
