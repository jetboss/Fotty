import Foundation
import SwiftData

@Model
final class MatchCacheItem {
    @Attribute(.unique) var id: String
    var title: String?
    var homeName: String
    var awayName: String
    /// Raw StreamEx / Nexus badge token or absolute URL (same field as `NexusATeam.badge`).
    var homeBadge: String?
    var awayBadge: String?
    var kickoffDate: Date?
    var category: String?
    var popular: Bool?
    var lastUpdated: Date
    
    init(
        id: String,
        title: String?,
        homeName: String,
        awayName: String,
        homeBadge: String? = nil,
        awayBadge: String? = nil,
        kickoffDate: Date?,
        category: String?,
        popular: Bool?
    ) {
        self.id = id
        self.title = title
        self.homeName = homeName
        self.awayName = awayName
        self.homeBadge = homeBadge
        self.awayBadge = awayBadge
        self.kickoffDate = kickoffDate
        self.category = category
        self.popular = popular
        self.lastUpdated = Date()
    }
}
