import Foundation

enum TeamFollowKey {
    static func make(name: String, category: String) -> String {
        let sport = SportsTeamIdentity.sport(category) ?? category.lowercased()
        if let identity = SportsTeamIdentity.known(name: name, category: sport) {
            return identity.id
        }
        return "\(sport)|\(SportsTeamIdentity.slug(name))"
    }
}
