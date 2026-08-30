import Foundation

public enum FPLSquadValidator {
    public static func validate(
        picks: [FPLPick],
        players: [FPLPlayer],
        elementTypes: [FPLElementType] = [],
        gameSettings: FPLGameSettings? = nil,
        budgetLimit: Int? = nil
    ) -> FPLSquadValidationReport {
        let playerByID = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
        var issues = [FPLSquadValidationIssue]()
        let expectedSquadSize = gameSettings?.squadSize ?? 15
        let teamLimit = gameSettings?.squadTeamLimit ?? 3

        if picks.count != expectedSquadSize {
            issues.append(error("squad-size", "A squad must contain exactly \(expectedSquadSize) players; this draft contains \(picks.count)."))
        }

        let duplicateIDs = Dictionary(grouping: picks, by: \.element)
            .filter { $0.value.count > 1 }
            .keys
        if !duplicateIDs.isEmpty {
            issues.append(error("duplicate-player", "A player can only appear once in the squad."))
        }

        let missingPlayers = picks.filter { playerByID[$0.element] == nil }
        if !missingPlayers.isEmpty {
            issues.append(error("unknown-player", "\(missingPlayers.count) squad player(s) are missing from the current FPL catalog."))
        }

        let positions = picks.map(\.position)
        if Set(positions).count != positions.count || positions.contains(where: { $0 < 1 || $0 > expectedSquadSize }) {
            issues.append(error("pick-order", "Squad positions must be unique and run from 1 to \(expectedSquadSize)."))
        }

        let expectedPositionCounts: [Int: Int] = {
            let decoded = Dictionary(uniqueKeysWithValues: elementTypes.compactMap { type in
                type.squadSelect.map { (type.id, $0) }
            })
            return decoded.isEmpty ? [1: 2, 2: 5, 3: 5, 4: 3] : decoded
        }()
        let actualPositionCounts = Dictionary(grouping: picks.compactMap { playerByID[$0.element]?.elementType }, by: { $0 })
            .mapValues(\.count)
        for (position, expected) in expectedPositionCounts.sorted(by: { $0.key < $1.key }) {
            let actual = actualPositionCounts[position, default: 0]
            if actual != expected {
                issues.append(error("position-\(position)", "Position \(position) requires \(expected) players; this draft has \(actual)."))
            }
        }

        let clubCounts = Dictionary(grouping: picks.compactMap { playerByID[$0.element]?.team }, by: { $0 })
            .mapValues(\.count)
        if let excess = clubCounts.first(where: { $0.value > teamLimit }) {
            issues.append(error("club-limit", "A maximum of \(teamLimit) players may come from one club; one club has \(excess.value)."))
        }

        let captains = picks.filter(\.isCaptain)
        let viceCaptains = picks.filter(\.isViceCaptain)
        if captains.count != 1 {
            issues.append(error("captain", "Select exactly one captain."))
        }
        if viceCaptains.count != 1 {
            issues.append(error("vice-captain", "Select exactly one vice-captain."))
        }
        if let captain = captains.first, let vice = viceCaptains.first, captain.element == vice.element {
            issues.append(error("captain-vice", "Captain and vice-captain must be different players."))
        }

        let starters = picks.filter { $0.position <= (gameSettings?.squadPlay ?? 11) }
        let starterTypes = starters.compactMap { playerByID[$0.element]?.elementType }
        let starterCounts = Dictionary(grouping: starterTypes, by: { $0 }).mapValues(\.count)
        let formation: String? = starterTypes.count == 11
            ? "\(starterCounts[2, default: 0])-\(starterCounts[3, default: 0])-\(starterCounts[4, default: 0])"
            : nil

        if starterTypes.count == 11 {
            if starterCounts[1, default: 0] != 1 {
                issues.append(error("starting-goalkeeper", "The starting XI must contain exactly one goalkeeper."))
            }
            for position in 2...4 {
                let decodedType = elementTypes.first(where: { $0.id == position })
                let minimum = decodedType?.squadMinPlay ?? defaultMinimum[position, default: 0]
                let maximum = decodedType?.squadMaxPlay ?? defaultMaximum[position, default: 5]
                let count = starterCounts[position, default: 0]
                if count < minimum || count > maximum {
                    let label = decodedType?.pluralName.lowercased() ?? defaultPositionNames[position, default: "players"]
                    issues.append(error("formation-\(position)", "The starting formation has an invalid number of \(label)."))
                }
            }
        } else if picks.count == expectedSquadSize {
            issues.append(error("starting-xi", "Exactly 11 players must be in the starting lineup."))
        }

        let benchGoalkeepers = picks
            .filter { $0.position > (gameSettings?.squadPlay ?? 11) }
            .compactMap { playerByID[$0.element] }
            .filter { $0.elementType == 1 }
        if picks.count == expectedSquadSize, benchGoalkeepers.count != 1 {
            issues.append(error("bench-goalkeeper", "The bench must contain exactly one goalkeeper."))
        }

        let totalCost = picks.reduce(into: 0) { total, pick in
            total += pick.sellingPrice ?? playerByID[pick.element]?.nowCost ?? 0
        }
        if let budgetLimit, totalCost > budgetLimit {
            issues.append(error("budget", "This draft costs £\(money(totalCost))m, exceeding the available £\(money(budgetLimit))m."))
        }

        if picks.contains(where: { playerByID[$0.element]?.removed == true || playerByID[$0.element]?.canSelect == false }) {
            issues.append(error("unselectable", "At least one player can no longer be selected in official FPL."))
        }

        return FPLSquadValidationReport(
            issues: issues,
            totalCost: totalCost,
            budgetLimit: budgetLimit,
            formation: formation
        )
    }

    private static let defaultMinimum = [2: 3, 3: 2, 4: 1]
    private static let defaultMaximum = [2: 5, 3: 5, 4: 3]
    private static let defaultPositionNames = [2: "defenders", 3: "midfielders", 4: "forwards"]

    private static func error(_ code: String, _ message: String) -> FPLSquadValidationIssue {
        FPLSquadValidationIssue(code: code, message: message, severity: .error)
    }

    private static func money(_ tenths: Int) -> String {
        String(format: "%.1f", Double(tenths) / 10)
    }
}
