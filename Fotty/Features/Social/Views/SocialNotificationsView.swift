import SwiftUI

struct SocialNotificationsView: View {
    let notifications: [SocialNotificationItem]
    let unreadCount: Int
    let localPersistenceError: String?
    
    let onMarkAsRead: (SocialNotificationItem) -> Void
    let onMarkAllRead: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
            SectionHeader(
                title: "In-App Notifications",
                subtitle: unreadCount > 0 ? "\(unreadCount) unread" : "All caught up"
            )

            if notifications.isEmpty {
                socialEmptyStateCard(text: "No notifications yet. Follows, reports, and social actions will appear here.")
                    .padding(.horizontal, FottyTheme.spacingMD)
            } else {
                VStack(spacing: FottyTheme.spacingSM) {
                    ForEach(notifications) { notification in
                        Button {
                            onMarkAsRead(notification)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(notification.isRead ? FottyTheme.textTertiary : FottyTheme.accent)
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 6)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(notification.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(FottyTheme.textPrimary)
                                    Text(notification.body)
                                        .font(.system(size: 12))
                                        .foregroundStyle(FottyTheme.textSecondary)
                                        .multilineTextAlignment(.leading)
                                    Text(notification.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 10))
                                        .foregroundStyle(FottyTheme.textTertiary)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(FottyTheme.spacingMD)
                            .cardStyle()
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Mark All Read") {
                        onMarkAllRead()
                    }
                    .pillButtonStyle(accent: false)
                }
                .padding(.horizontal, FottyTheme.spacingMD)
                
                if let error = localPersistenceError, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(FottyTheme.accentText)
                        .padding(.horizontal, FottyTheme.spacingLG)
                }
            }
        }
    }
    
    private func socialEmptyStateCard(text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.badge.slash.fill")
                .font(.system(size: 32))
                .foregroundStyle(FottyTheme.textTertiary)
            
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(FottyTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(FottyTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
