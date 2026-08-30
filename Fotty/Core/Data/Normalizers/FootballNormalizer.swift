import Foundation

// MARK: - Normalization Helpers
// Central logic for converting messy API strings/codes into Fotty's strict enums.

public struct FootballNormalizer {
    
    public static func normalizeStatus(_ raw: String) -> FottyMatchStatus {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch code {
        case "NS", "SCHEDULED": return .scheduled
        case "TBD": return .scheduled
        case "1H", "2H", "LIVE", "IN_PLAY": return .live
        case "HT", "PAUSED": return .halfTime
        case "FT", "FINISHED": return .fullTime
        case "AET": return .extraTime
        case "PEN": return .penalties
        case "PST", "POSTPONED": return .postponed
        case "CANC", "CANCELLED": return .cancelled
        case "ABD", "ABANDONED": return .abandoned
        default: return .unknown
        }
    }
    
    public static func normalizeEventType(_ raw: String, detail: String? = nil) -> FottyEventType {
        let type = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let det = detail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        
        switch type {
        case "goal":
            if det.contains("penalty") { return .penalty }
            if det.contains("own goal") { return .ownGoal }
            return .goal
        case "card":
            if det.contains("red") { return .redCard }
            return .yellowCard
        case "subst": return .substitution
        case "var": return .varDecision
        default: return .unknown
        }
    }
    
    /// Returns `nil` for malformed provider dates. Treating an invalid date as
    /// `Date()` makes corrupt fixtures look like real live/upcoming matches.
    public static func parseISO8601Date(_ string: String) -> Date? {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
