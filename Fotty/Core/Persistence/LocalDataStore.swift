import Foundation
import SwiftData

/// The persistence engine for the Fotty Enterprise Ecosystem.
/// Implements 'Offline-First' resilience.
@MainActor
class LocalDataStore {
    static let shared = LocalDataStore()
    
    static let appSchema = Schema([
        FollowedTeamItem.self,
        FollowedLeagueItem.self,
        UserProfile.self,
        SocialAccount.self,
        SocialFollowRelationship.self,
        SocialNotificationItem.self,
        SocialActivityItem.self,
        SocialSafetyActionItem.self,
        SocialPendingActionItem.self,
        ArenaMessage.self,
        SocialConversation.self,
        DirectMessage.self,
        MatchCacheItem.self,
        CachedMatch.self,
        CachedStatistic.self
    ])

    let container: ModelContainer
    
    private init() {
        let defaultAppSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        let applicationSupportURL = defaultAppSupportURL ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )
        let storeURL = applicationSupportURL.appending(path: "fotty_enterprise_v4.store")
        let configuration = ModelConfiguration(
            schema: Self.appSchema,
            url: storeURL
        )
        
        do {
            container = try ModelContainer(
                for: Self.appSchema,
                configurations: configuration
            )
        } catch {
            print("[LocalDataStore] Failed to initialize persistent store at \(storeURL.path): \(error.localizedDescription)")
            let memoryConfiguration = ModelConfiguration(
                schema: Self.appSchema,
                isStoredInMemoryOnly: true
            )
            do {
                container = try ModelContainer(
                    for: Self.appSchema,
                    configurations: memoryConfiguration
                )
            } catch {
                fatalError("[LocalDataStore] Failed to initialize in-memory model container: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Persistence Models

@Model
final class CachedMatch {
    @Attribute(.unique) var id: Int
    var homeName: String
    var awayName: String
    var homeGoals: Int
    var awayGoals: Int
    var status: String
    var updatedAt: Date
    
    init(id: Int, homeName: String, awayName: String, homeGoals: Int, awayGoals: Int, status: String) {
        self.id = id
        self.homeName = homeName
        self.awayName = awayName
        self.homeGoals = homeGoals
        self.awayGoals = awayGoals
        self.status = status
        self.updatedAt = Date()
    }
}

@Model
final class CachedStatistic {
    @Attribute(.unique) var id: String // matchId + teamId + type
    var matchId: Int
    var teamId: Int
    var type: String
    var value: String
    
    init(matchId: Int, teamId: Int, type: String, value: String) {
        self.id = "\(matchId)-\(teamId)-\(type)"
        self.matchId = matchId
        self.teamId = teamId
        self.type = type
        self.value = value
    }
}
