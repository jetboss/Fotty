import Foundation

struct SocialTeamSuggestion: Identifiable, Codable {
    let id: String
    let followKey: String
    let teamName: String
    let sportCategory: String
    let kickoff: Date?
    let leagueName: String?
    let badgeURL: URL?
}
