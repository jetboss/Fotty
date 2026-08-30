import Foundation

enum SocialSafetyAction: String {
    case block
    case mute
    case report
}

enum SocialDiscoveryScope: String, CaseIterable, Identifiable {
    case all
    case football
    case verified
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .all: return "All"
        case .football: return "Football"
        case .verified: return "Verified"
        }
    }
}

enum SocialDiscoverySort: String, CaseIterable, Identifiable {
    case relevance
    case alphabetical
    case verifiedFirst
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .relevance: return "Relevance"
        case .alphabetical: return "A-Z"
        case .verifiedFirst: return "Verified"
        }
    }
}

enum SocialHubTab: String, CaseIterable, Identifiable {
    case following
    case explore
    case teams
    case notifications
    case messages
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .following: return "Following"
        case .explore: return "Explore"
        case .teams: return "Teams"
        case .notifications: return "Notifications"
        case .messages: return "Messages"
        }
    }
    
    var icon: String {
        switch self {
        case .following: return "person.2.fill"
        case .explore: return "safari.fill"
        case .teams: return "sportscourt.fill"
        case .notifications: return "bell.fill"
        case .messages: return "message.fill"
        }
    }
}

struct SocialDiscoveryEntry: Identifiable {
    let id: String
    let username: String
    let displayName: String
    let bio: String
    let avatarSymbol: String
    let favoriteCategory: String?
    let isVerified: Bool
}

struct SocialReactionSummaryItem: Identifiable {
    let emoji: String
    let count: Int
    
    var id: String { emoji }
}
