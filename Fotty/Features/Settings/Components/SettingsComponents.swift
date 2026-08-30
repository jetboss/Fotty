import SwiftUI

// MARK: - Settings Section
struct SettingsSection<Content: View>: View {
    let title: String?
    let content: Content
    
    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: FottyTheme.spacingSM) {
            if let title = title {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(FottyTheme.textSecondary)
                    .padding(.horizontal, FottyTheme.spacingSM)
            }
            
            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: FottyTheme.radiusLG)
                    .fill(FottyTheme.surface)
            )
            .cornerRadius(FottyTheme.radiusLG)
            .overlay(
                RoundedRectangle(cornerRadius: FottyTheme.radiusLG)
                    .strokeBorder(FottyTheme.border.opacity(0.5), lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Settings Icon
struct SettingsIcon: View {
    let icon: String
    let color: Color
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.12))
                .frame(width: 32, height: 32)
            
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Settings Row
struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var showChevron: Bool = true
    var action: (() -> Void)? = nil
    
    var body: some View {
        Group {
            if let action = action {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(SettingsRowButtonStyle())
            } else {
                rowContent
                    .contentShape(Rectangle())
            }
        }
    }
    
    private var rowContent: some View {
        HStack(spacing: FottyTheme.spacingMD) {
            SettingsIcon(icon: icon, color: iconColor)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(FottyTheme.textPrimary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(FottyTheme.textSecondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                if let value = value {
                    Text(value)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FottyTheme.accentText)
                }
                
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FottyTheme.textTertiary)
                }
            }
        }
        .padding(.horizontal, FottyTheme.spacingMD)
        .padding(.vertical, 14)
    }
}

struct SettingsRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(configuration.isPressed ? FottyTheme.surfaceElevated.opacity(0.4) : Color.clear)
            .contentShape(Rectangle())
    }
}

// MARK: - Settings Toggle Row
struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: FottyTheme.spacingMD) {
            SettingsIcon(icon: icon, color: iconColor)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(FottyTheme.textPrimary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(FottyTheme.textSecondary)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(FottyTheme.accentText)
                .accessibilityLabel(title)
                .accessibilityHint(subtitle ?? "")
        }
        .padding(.horizontal, FottyTheme.spacingMD)
        .padding(.vertical, 12)
    }
}

// MARK: - Settings Profile Header
struct SettingsProfileHeader: View {
    let displayName: String
    let username: String
    let accountEmail: String?
    let avatarSymbol: String?
    let avatarImageData: Data?
    let favoriteTeamBadge: URL?
    let statusBadge: String?
    let onEdit: () -> Void
    
    var body: some View {
        VStack(spacing: FottyTheme.spacingMD) {
            HStack(spacing: FottyTheme.spacingLG) {
                // Avatar with Badge
                ZStack(alignment: .bottomTrailing) {
                    if let data = avatarImageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(FottyTheme.surfaceElevated)
                            .frame(width: 64, height: 64)
                            .overlay(
                                Image(systemName: avatarSymbol ?? "person.fill")
                                    .font(.fottyScaled(size: 26))
                                    .foregroundStyle(FottyTheme.textSecondary)
                            )
                    }
                    
                    if let teamBadge = favoriteTeamBadge {
                        AsyncImage(url: teamBadge) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Circle().fill(FottyTheme.surfaceElevated)
                        }
                        .frame(width: 30, height: 30)
                        .padding(4)
                        .background(Circle().fill(FottyTheme.background))
                        .overlay(Circle().stroke(FottyTheme.border, lineWidth: 1))
                        .offset(x: 4, y: 4)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(displayName)
                            .font(.fottyScaled(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(FottyTheme.textPrimary)
                        
                        if let status = statusBadge {
                            Text(status)
                                .font(.system(size: 10, weight: .black))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(FottyTheme.accentGradient)
                                .foregroundStyle(FottyTheme.textOnAccent)
                                .clipShape(Capsule())
                        }
                    }
                    
                    if let accountEmail, !accountEmail.isEmpty {
                        Text(accountEmail)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FottyTheme.accentText)
                    }

                    Text("@\(username)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FottyTheme.textSecondary)

                    Button(action: onEdit) {
                        HStack(spacing: 4) {
                            Text("Edit Profile")
                            Image(systemName: "pencil")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FottyTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(FottyTheme.surfaceElevated.opacity(0.5))
                        .clipShape(Capsule())
                        .padding(.top, 6)
                    }
                }
                
                Spacer()
            }
            .padding(FottyTheme.spacingMD)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: FottyTheme.radiusXL)
                        .fill(FottyTheme.surface.opacity(0.6))
                        .background(.ultraThinMaterial)
                    
                }
            )
            .cornerRadius(FottyTheme.radiusXL)
            .overlay(
                RoundedRectangle(cornerRadius: FottyTheme.radiusXL)
                    .strokeBorder(FottyTheme.border.opacity(0.5), lineWidth: 1)
            )
        }
    }
}

// MARK: - Settings Danger Zone
struct SettingsDangerZone: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    let action: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: FottyTheme.spacingSM) {
            Text("DANGER ZONE")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(FottyTheme.error)
                .padding(.horizontal, FottyTheme.spacingSM)
            
            VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(FottyTheme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(FottyTheme.textSecondary)
                }
                
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(FottyTheme.textOnError)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(FottyTheme.error)
                        .cornerRadius(12)
                }
            }
            .padding(FottyTheme.spacingMD)
            .background(FottyTheme.error.opacity(0.05))
            .cornerRadius(FottyTheme.radiusLG)
            .overlay(
                RoundedRectangle(cornerRadius: FottyTheme.radiusLG)
                    .strokeBorder(FottyTheme.error.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

// MARK: - Divider
struct SettingsDivider: View {
    var body: some View {
        Divider()
            .background(FottyTheme.border)
            .padding(.leading, 60) // Align with text, skipping icons
    }
}
