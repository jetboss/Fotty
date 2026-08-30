import Foundation
import Combine

/// Manages local user preferences, followed teams, and FPL Manager ID.
/// Decoupled from the retired homelab PocketBase server.
@MainActor
public final class UserProfileStore: ObservableObject {
    public static let shared = UserProfileStore()
    
    private let defaults: UserDefaults
    private let fplManagerIdKey = "fotty.user.fplManagerId"
    private let favoriteTeamsKey = "fotty.user.favoriteTeams"
    private let preferredSportKey = "fotty.user.preferredSport"
    
    @Published public var fplManagerId: Int? {
        didSet {
            if let id = fplManagerId {
                defaults.set(id, forKey: fplManagerIdKey)
            } else {
                defaults.removeObject(forKey: fplManagerIdKey)
            }
        }
    }
    
    @Published public var favoriteTeams: Set<String> {
        didSet {
            let array = Array(favoriteTeams)
            defaults.set(array, forKey: favoriteTeamsKey)
        }
    }
    
    @Published public var preferredSport: String {
        didSet {
            defaults.set(preferredSport, forKey: preferredSportKey)
        }
    }
    
    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        let storedId = defaults.integer(forKey: fplManagerIdKey)
        self.fplManagerId = storedId > 0 ? storedId : nil
        
        if let storedTeams = defaults.stringArray(forKey: favoriteTeamsKey) {
            self.favoriteTeams = Set(storedTeams)
        } else {
            self.favoriteTeams = []
        }
        
        self.preferredSport = defaults.string(forKey: preferredSportKey) ?? "football"
    }
    
    public func toggleFavoriteTeam(_ teamName: String) {
        let trimmed = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if favoriteTeams.contains(trimmed) {
            favoriteTeams.remove(trimmed)
        } else {
            favoriteTeams.insert(trimmed)
        }
    }
    
    public func isFavorite(team teamName: String) -> Bool {
        favoriteTeams.contains(teamName.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
