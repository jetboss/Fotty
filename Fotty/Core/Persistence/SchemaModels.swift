import Foundation
import SwiftData

// MARK: - Core Sports Models

@Model
final class FollowedTeamItem {
    @Attribute(.unique) var key: String
    var teamName: String
    var sportCategory: String
    var badgeURLString: String?
    var alertsEnabled: Bool?
    var createdAt: Date
    
    init(key: String, teamName: String, sportCategory: String, badgeURLString: String? = nil, alertsEnabled: Bool = true, createdAt: Date = Date()) {
        self.key = key
        self.teamName = teamName
        self.sportCategory = sportCategory
        self.badgeURLString = badgeURLString
        self.alertsEnabled = alertsEnabled
        self.createdAt = createdAt
    }
}

@Model
final class FollowedLeagueItem {
    @Attribute(.unique) var id: String
    var leagueName: String
    var sportCategory: String
    var country: String?
    var createdAt: Date
    
    init(id: String, leagueName: String, sportCategory: String, country: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.leagueName = leagueName
        self.sportCategory = sportCategory
        self.country = country
        self.createdAt = createdAt
    }
}

// MARK: - User Profile Models

@Model
final class UserProfile {
    @Attribute(.unique) var id: String
    var displayName: String
    var username: String?
    var bio: String?
    var avatarSymbol: String?
    var avatarImageData: Data?
    var avatarImageUpdatedAt: Date?
    var isSignedIn: Bool
    var isPrivateAccount: Bool
    var allowFollowerRequests: Bool
    var shareTeamActivity: Bool
    var lastUpdatedAt: Date?
    var createdAt: Date
    
    init(
        id: String = "local-profile",
        displayName: String = "Guest",
        username: String? = nil,
        bio: String? = "Football matches and live scores.",
        avatarSymbol: String? = "person.fill",
        avatarImageData: Data? = nil,
        avatarImageUpdatedAt: Date? = nil,
        isSignedIn: Bool = false,
        isPrivateAccount: Bool = false,
        allowFollowerRequests: Bool = true,
        shareTeamActivity: Bool = true,
        lastUpdatedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.username = username
        self.bio = bio
        self.avatarSymbol = avatarSymbol
        self.avatarImageData = avatarImageData
        self.avatarImageUpdatedAt = avatarImageUpdatedAt
        self.isSignedIn = isSignedIn
        self.isPrivateAccount = isPrivateAccount
        self.allowFollowerRequests = allowFollowerRequests
        self.shareTeamActivity = shareTeamActivity
        self.lastUpdatedAt = lastUpdatedAt
        self.createdAt = createdAt
    }
}

// MARK: - Social Network Models

@Model
final class SocialAccount {
    @Attribute(.unique) var id: String
    var username: String
    var displayName: String
    var bio: String
    var avatarSymbol: String
    var favoriteCategory: String?
    var isVerified: Bool
    var createdAt: Date
    
    init(
        id: String,
        username: String,
        displayName: String,
        bio: String,
        avatarSymbol: String,
        favoriteCategory: String? = nil,
        isVerified: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.bio = bio
        self.avatarSymbol = avatarSymbol
        self.favoriteCategory = favoriteCategory
        self.isVerified = isVerified
        self.createdAt = createdAt
    }
}

@Model
final class SocialFollowRelationship {
    @Attribute(.unique) var id: String
    var followerProfileID: String
    var followedAccountID: String
    var createdAt: Date
    var key: String
    
    init(followerProfileID: String, followedAccountID: String, createdAt: Date = Date()) {
        self.id = UUID().uuidString
        self.followerProfileID = followerProfileID
        self.followedAccountID = followedAccountID
        self.createdAt = createdAt
        self.key = "\(followerProfileID):\(followedAccountID)"
    }
}

@Model
final class SocialNotificationItem {
    @Attribute(.unique) var id: String
    var type: String
    var title: String
    var body: String
    var actorAccountID: String?
    var isRead: Bool
    var createdAt: Date
    
    init(type: String, title: String, body: String, actorAccountID: String? = nil, isRead: Bool = false, createdAt: Date = Date()) {
        self.id = UUID().uuidString
        self.type = type
        self.title = title
        self.body = body
        self.actorAccountID = actorAccountID
        self.isRead = isRead
        self.createdAt = createdAt
    }
}

@Model
final class SocialActivityItem {
    @Attribute(.unique) var id: String
    var actorProfileID: String
    var actorDisplayName: String
    var actorUsername: String
    var category: String
    var content: String
    var createdAt: Date
    
    init(actorProfileID: String, actorDisplayName: String, actorUsername: String, category: String, content: String, createdAt: Date = Date()) {
        self.id = UUID().uuidString
        self.actorProfileID = actorProfileID
        self.actorDisplayName = actorDisplayName
        self.actorUsername = actorUsername
        self.category = category
        self.content = content
        self.createdAt = createdAt
    }
}

@Model
final class SocialSafetyActionItem {
    @Attribute(.unique) var id: String
    var action: String
    var targetAccountID: String
    var reason: String?
    var createdAt: Date
    
    init(action: String, targetAccountID: String, reason: String? = nil, createdAt: Date = Date()) {
        self.id = UUID().uuidString
        self.action = action
        self.targetAccountID = targetAccountID
        self.reason = reason
        self.createdAt = createdAt
    }
}

@Model
final class SocialPendingActionItem {
    @Attribute(.unique) var id: String
    var actionType: String
    var payload: String
    var status: String
    var retryCount: Int
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date?
    
    init(actionType: String, payload: String, status: String = "pending", retryCount: Int = 0, lastError: String? = nil, createdAt: Date = Date()) {
        self.id = UUID().uuidString
        self.actionType = actionType
        self.payload = payload
        self.status = status
        self.retryCount = retryCount
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

// MARK: - Messaging Models

@Model
final class ArenaMessage {
    @Attribute(.unique) var id: String
    var matchID: Int
    var senderID: String
    var senderDisplayName: String
    var senderUsername: String
    var senderAvatarSymbol: String
    var content: String
    var type: String
    var createdAt: Date
    
    init(
        id: String = UUID().uuidString,
        matchID: Int,
        senderID: String,
        senderDisplayName: String,
        senderUsername: String,
        senderAvatarSymbol: String,
        content: String,
        type: String = "text",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.matchID = matchID
        self.senderID = senderID
        self.senderDisplayName = senderDisplayName
        self.senderUsername = senderUsername
        self.senderAvatarSymbol = senderAvatarSymbol
        self.content = content
        self.type = type
        self.createdAt = createdAt
    }
}

@Model
final class SocialConversation {
    @Attribute(.unique) var id: String
    var participantIDs: [String]
    var participantNames: [String: String]
    var lastMessageContent: String
    var lastMessageTimestamp: Date
    var unreadCount: Int
    
    init(
        id: String,
        participantIDs: [String],
        participantNames: [String: String],
        lastMessageContent: String,
        lastMessageTimestamp: Date = Date(),
        unreadCount: Int = 0
    ) {
        self.id = id
        self.participantIDs = participantIDs
        self.participantNames = participantNames
        self.lastMessageContent = lastMessageContent
        self.lastMessageTimestamp = lastMessageTimestamp
        self.unreadCount = unreadCount
    }
}

@Model
final class DirectMessage {
    @Attribute(.unique) var id: String
    var conversationID: String
    var senderID: String
    var recipientID: String
    var content: String
    var isRead: Bool
    var createdAt: Date
    
    init(
        id: String = UUID().uuidString,
        conversationID: String,
        senderID: String,
        recipientID: String,
        content: String,
        isRead: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.conversationID = conversationID
        self.senderID = senderID
        self.recipientID = recipientID
        self.content = content
        self.isRead = isRead
        self.createdAt = createdAt
    }
}
