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
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FottyTheme.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, FottyTheme.spacingSM)
            }
            
            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(FottyTheme.surface)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(FottyTheme.border, lineWidth: 0.5)
                    .allowsHitTesting(false)
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
        .accessibilityHidden(true)
    }
}

// MARK: - Settings Row
enum SettingsRowValueRole: Equatable {
    case information
    case action
}

/// Account for the actual value width as well as text-size categories. This
/// preserves the setting's name when a narrow window has a long saved value.
enum SettingsAccessoryLayoutPolicy {
    static func stacks(availableWidth: CGFloat, labelIdealWidth: CGFloat,
                       accessoryIdealWidth: CGFloat, accessibilitySize: Bool,
                       hasStackableAccessory: Bool = true) -> Bool {
        guard accessoryIdealWidth > 0, hasStackableAccessory else { return false }
        if accessibilitySize { return true }
        let labelRoom = max(0, availableWidth - accessoryIdealWidth - 12)
        return labelRoom < min(labelIdealWidth, 180)
    }
}

private struct SettingsAccessoryLayout: Layout {
    let accessibilitySize: Bool
    let layoutDirection: LayoutDirection
    var hasStackableAccessory = true

    private func metrics(width: CGFloat, subviews: Subviews) -> (label: CGSize, accessory: CGSize, stacked: Bool) {
        guard subviews.count == 2 else { return (.zero, .zero, false) }
        let idealLabel = subviews[0].sizeThatFits(.unspecified)
        let accessory = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let stacked = SettingsAccessoryLayoutPolicy.stacks(availableWidth: width,
            labelIdealWidth: idealLabel.width, accessoryIdealWidth: accessory.width,
            accessibilitySize: accessibilitySize, hasStackableAccessory: hasStackableAccessory)
        let labelWidth = stacked ? width : max(0, width - accessory.width - (accessory.width > 0 ? 12 : 0))
        return (subviews[0].sizeThatFits(.init(width: labelWidth, height: nil)), accessory, stacked)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(0, proposal.width ?? 320)
        let sizes = metrics(width: width, subviews: subviews)
        return CGSize(width: width, height: sizes.stacked
            ? sizes.label.height + 10 + sizes.accessory.height
            : max(sizes.label.height, sizes.accessory.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let sizes = metrics(width: bounds.width, subviews: subviews)
        let labelX = layoutDirection == .rightToLeft ? bounds.maxX - sizes.label.width : bounds.minX
        let accessoryX = layoutDirection == .rightToLeft ? bounds.minX : bounds.maxX - sizes.accessory.width
        subviews[0].place(at: CGPoint(x: labelX, y: sizes.stacked ? bounds.minY : bounds.midY - sizes.label.height / 2),
                          proposal: .init(width: sizes.label.width, height: sizes.label.height))
        subviews[1].place(at: CGPoint(x: accessoryX,
                                     y: sizes.stacked ? bounds.minY + sizes.label.height + 10 : bounds.midY - sizes.accessory.height / 2),
                          proposal: .init(width: sizes.accessory.width, height: sizes.accessory.height))
    }
}

struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var valueRole: SettingsRowValueRole = .information
    var showChevron: Bool = true
    // Opt in at the Settings root; existing destination/FPL shortcut layouts
    // retain their current behavior. A real value still reflows below its name.
    var keepsDisclosureInline = false
    var action: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    
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
        SettingsAccessoryLayout(accessibilitySize: dynamicTypeSize.isAccessibilitySize,
                                layoutDirection: layoutDirection,
                                hasStackableAccessory: !keepsDisclosureInline || value?.isEmpty == false) {
            rowLabel
            rowAccessory
        }
        .padding(.horizontal, FottyTheme.spacingMD)
        .padding(.vertical, 12)
        .frame(minHeight: 52)
    }

    private var rowLabel: some View {
        HStack(alignment: subtitle == nil ? .center : .top, spacing: FottyTheme.spacingMD) {
            SettingsIcon(icon: icon, color: iconColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(FottyTheme.typeMeta)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private var rowAccessory: some View {
        HStack(spacing: 6) {
            if let value {
                Text(value)
                    .font(valueRole == .action ? FottyTheme.typeAction : FottyTheme.typeBody)
                    .foregroundStyle(valueRole == .action ? FottyTheme.accentText : FottyTheme.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textTertiary)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct SettingsRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(configuration.isPressed ? FottyTheme.surfaceSubtle : Color.clear)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    
    var body: some View {
        SettingsAccessoryLayout(accessibilitySize: dynamicTypeSize.isAccessibilitySize, layoutDirection: layoutDirection) {
            toggleLabel
                // The native toggle below owns the full spoken title/hint.
                // Do not announce its identical visible label a second time.
                .accessibilityHidden(true)
            toggle.fixedSize()
        }
        .padding(.horizontal, FottyTheme.spacingMD)
        .padding(.vertical, 12)
        .frame(minHeight: 52)
    }

    private var toggleLabel: some View {
        HStack(alignment: subtitle == nil ? .center : .top, spacing: FottyTheme.spacingMD) {
            SettingsIcon(icon: icon, color: iconColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(FottyTheme.typeMeta)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var toggle: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .tint(FottyTheme.accentText)
            .accessibilityLabel(title)
            .accessibilityHint(subtitle ?? "")
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
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.error)
                .padding(.horizontal, FottyTheme.spacingSM)
            
            VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(FottyTheme.typeModuleTitle)
                        .foregroundStyle(FottyTheme.textPrimary)
                    Text(subtitle)
                        .font(FottyTheme.typeBody)
                        .foregroundStyle(FottyTheme.textSecondary)
                }
                
                Button(action: action) {
                    Text(actionTitle)
                        .font(FottyTheme.typeAction)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Divider()
            .background(FottyTheme.border)
            .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 60)
    }
}

/// SwiftData can deliberately fall back to memory so the app still opens. Any
/// screen that edits SwiftData-backed follows must make that temporary state
/// visible before the user performs an action.
struct LocalPersistenceWarning: View {
    var detail = "Favorite teams and leagues can't be saved right now. Restart Fotty, then report the problem if it returns."

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Changes cannot be saved", systemImage: "externaldrive.badge.exclamationmark")
                .font(FottyTheme.typeModuleTitle)
                .foregroundStyle(FottyTheme.error)
            Text(detail)
                .font(FottyTheme.typeBody)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(FottyTheme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FottyTheme.error.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous)
                .strokeBorder(FottyTheme.error.opacity(0.45), lineWidth: 1)
        }
        .accessibilityIdentifier("settings-persistence-warning")
    }
}
