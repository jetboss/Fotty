import SwiftUI

struct SocialDiscoveryRow: View {
    let entry: SocialDiscoveryEntry
    let isFollowing: Bool
    
    let onFollow: () -> Void
    let onMute: () -> Void
    let onBlock: () -> Void
    let onReport: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.avatarSymbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(FottyTheme.accentText)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FottyTheme.textPrimary)

                    if entry.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(FottyTheme.success)
                    }
                }

                Text("@\(entry.username)")
                    .font(.system(size: 12))
                    .foregroundStyle(FottyTheme.textSecondary)

                if let category = entry.favoriteCategory, !category.isEmpty {
                    Text(category.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(FottyTheme.textTertiary)
                }
            }

            Spacer()

            Button(isFollowing ? "Following" : "Follow") {
                onFollow()
            }
            .pillButtonStyle(accent: !isFollowing)

            Menu {
                Button("Mute") { onMute() }
                Button("Block", role: .destructive) { onBlock() }
                Button("Report") { onReport() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(FottyTheme.surfaceElevated))
            }
            .buttonStyle(.plain)
        }
        .padding(FottyTheme.spacingMD)
        .cardStyle()
    }
}
