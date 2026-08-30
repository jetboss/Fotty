import SwiftUI
import Combine

@MainActor
final class NotificationBadgeManager: ObservableObject {
    static let shared = NotificationBadgeManager()
    
    @Published var unreadCount: Int = 0
    
    private let badgeKey = "fotty.notificationBadgeCount"
    
    private init() {
        loadBadgeCount()
    }
    
    func updateCount(_ count: Int) {
        unreadCount = count
        UserDefaults.standard.set(count, forKey: badgeKey)
    }
    
    func incrementBadge() {
        unreadCount += 1
        UserDefaults.standard.set(unreadCount, forKey: badgeKey)
    }
    
    func clearBadge() {
        unreadCount = 0
        UserDefaults.standard.set(0, forKey: badgeKey)
    }
    
    private func loadBadgeCount() {
        unreadCount = UserDefaults.standard.integer(forKey: badgeKey)
    }
}
