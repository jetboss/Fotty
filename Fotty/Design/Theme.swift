import SwiftUI

enum FottyAppearance: String, CaseIterable, Identifiable {
    case dark, light, system
    static let storageKey = "fotty.appearance"
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self { case .dark: return .dark; case .light: return .light; case .system: return nil }
    }
    static func saved(_ value: String) -> Self { Self(rawValue: value) ?? .dark }
}

/// One scale on both the pitch and fixture table. Numerals and VoiceOver labels
/// carry the meaning too; colour is never the only difficulty indicator.
enum FottyFixtureDifficulty {
    static func background(_ value: Int) -> Color {
        switch value {
        case 1: return Color(red: 0.10, green: 0.32, blue: 0.20)
        case 2: return Color(red: 0.00, green: 0.80, blue: 0.40)
        case 3: return Color(red: 0.85, green: 0.85, blue: 0.87)
        case 4: return Color(red: 0.76, green: 0.12, blue: 0.20)
        case 5: return Color(red: 0.50, green: 0.03, blue: 0.18)
        default: return FottyTheme.surfaceElevated
        }
    }

    static func foreground(_ value: Int) -> Color {
        guard (1...5).contains(value) else { return FottyTheme.textPrimary }
        return [2, 3].contains(value) ? .black : .white
    }

    static func label(_ value: Int) -> String {
        (1...5).contains(value) ? "Difficulty \(value) of 5" : "Difficulty not rated"
    }
}

// MARK: - Fotty Design System
// Identity: Matchday Editorial

enum FottyTheme {

    /// Resolve per view/window trait, never from a cached global screen style.
    static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in traits.userInterfaceStyle == .light ? light : dark })
    }

    // MARK: - Brand

    static let identityName = "Matchday Editorial"

    // MARK: - Colors

    /// Primary accent — cinema gold / amber (#F5A020)
    static let accent = Color(red: 0.96, green: 0.63, blue: 0.13)

    /// Amber ink is darker on paper; filled gold buttons retain the brand gold.
    static let accentText = adaptive(
        light: UIColor(red: 0.46, green: 0.25, blue: 0.015, alpha: 1),
        dark: UIColor(red: 0.96, green: 0.63, blue: 0.13, alpha: 1)
    )

    /// Live / attention accent — same family, slightly brighter
    static let liveAccent = Color(red: 1.00, green: 0.70, blue: 0.15)

    /// Success / positive state
    static let success = adaptive(light: UIColor(red: 0.06, green: 0.40, blue: 0.23, alpha: 1), dark: UIColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 1))

    /// Error state
    static let error = adaptive(light: UIColor(red: 0.68, green: 0.12, blue: 0.10, alpha: 1), dark: UIColor(red: 0.96, green: 0.34, blue: 0.29, alpha: 1))

    /// Momentum kept for legacy call sites; prefer accent on product surfaces.
    static let momentum = Color(red: 1.00, green: 0.75, blue: 0.25)

    // MARK: - Surfaces

    /// Warm paper in light appearance; cinema black in dark appearance.
    static let background = adaptive(light: UIColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1), dark: UIColor(white: 0.031, alpha: 1))

    /// Elevated module surface
    static let surface = adaptive(light: .white, dark: UIColor(red: 0.09, green: 0.095, blue: 0.11, alpha: 1))

    /// Quiet grouping surface used behind lists and secondary controls.
    static let surfaceSubtle = adaptive(light: UIColor(red: 0.925, green: 0.917, blue: 0.898, alpha: 1), dark: UIColor(red: 0.065, green: 0.068, blue: 0.078, alpha: 1))

    /// Sheets / floating chrome underlay
    static let surfaceElevated = adaptive(light: .white, dark: UIColor(red: 0.12, green: 0.125, blue: 0.145, alpha: 1))

    /// Restrained glass tint (chrome only)
    static let glass = adaptive(light: UIColor(white: 0, alpha: 0.035), dark: UIColor(white: 1, alpha: 0.05))

    /// Subtle divider / border
    static let border = adaptive(light: UIColor(white: 0, alpha: 0.10), dark: UIColor(white: 1, alpha: 0.08))

    /// Visible focus border for selected and actionable surfaces.
    static let borderStrong = adaptive(light: UIColor(white: 0, alpha: 0.24), dark: UIColor(white: 1, alpha: 0.16))

    /// Neomorphism Highlights
    static let neomorphHighlight = adaptive(light: UIColor(white: 1, alpha: 0.85), dark: UIColor(white: 1, alpha: 0.05))
    static let neomorphShadow = adaptive(light: UIColor(white: 0, alpha: 0.08), dark: UIColor(white: 0, alpha: 0.4))

    // MARK: - Text

    /// Primary ink (dark on paper, near-white in cinema).
    static let textPrimary = adaptive(light: UIColor(red: 0.10, green: 0.12, blue: 0.14, alpha: 1), dark: UIColor(white: 0.97, alpha: 1))

    /// Secondary text — muted
    static let textSecondary = adaptive(light: UIColor(red: 0.27, green: 0.30, blue: 0.34, alpha: 1), dark: UIColor(white: 0.72, alpha: 1))

    /// Tertiary / placeholder
    static let textTertiary = adaptive(light: UIColor(red: 0.35, green: 0.38, blue: 0.42, alpha: 1), dark: UIColor(white: 0.64, alpha: 1))

    /// Text on gold buttons / badges
    static let textOnAccent = Color.black
    static let textOnError = adaptive(light: .white, dark: .black)

    static let typeScreenTitle = Font.fottyScaled(size: 30, weight: .black)
    static let typeSectionTitle = Font.fottyScaled(size: 18, weight: .bold)
    static let typeModuleTitle = Font.fottyScaled(size: 15, weight: .bold)
    static let typeBody = Font.fottyScaled(size: 15, weight: .medium)
    static let typeAction = Font.fottyScaled(size: 14, weight: .bold)
    static let typeMeta = Font.fottyScaled(size: 12, weight: .semibold)
    static let typeCaption = Font.fottyScaled(size: 11, weight: .bold)

    /// Home outer inset / module gap (tight — avoid void bands)
    static let bentoInset: CGFloat = 16
    static let bentoGap: CGFloat = 10

    // MARK: - Gradients

    /// Hero overlay gradient (bottom fade for text readability over images)
    static let heroGradient = LinearGradient(
        colors: [
            .clear,
            background.opacity(0.7),
            background
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Accent gradient for buttons and highlights — cinema gold
    static let accentGradient = LinearGradient(
        colors: [
            Color(red: 0.96, green: 0.63, blue: 0.13),
            Color(red: 0.75, green: 0.45, blue: 0.05)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Live pulse gradient — intense stadium orange-red
    static let liveGradient = LinearGradient(
        colors: [
            Color(red: 1.00, green: 0.35, blue: 0.25),
            Color(red: 0.85, green: 0.15, blue: 0.10)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Momentum pulse (2026 Trend)
    static let momentumGradient = LinearGradient(
        colors: [
            momentum,
            Color(red: 0.00, green: 0.60, blue: 0.75)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Spacing

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 24
    static let spacingXL: CGFloat = 32
    static let spacingXXL: CGFloat = 48

    // MARK: - Corner Radius (Harmonized)

    /// Extra small - buttons, tags
    static let radiusXS: CGFloat = 6
    /// Small - inline elements
    static let radiusSM: CGFloat = 8
    /// Medium - cards, inputs (primary)
    static let radiusMD: CGFloat = 12
    /// Large - sheets, modals
    static let radiusLG: CGFloat = 16
    /// Extra large - hero elements
    static let radiusXL: CGFloat = 24
    /// Full circle
    static let radiusFull: CGFloat = 9999

    // MARK: - Animation

    static let springSnappy = Animation.spring(response: 0.35, dampingFraction: 0.75)
    static let springSmooth = Animation.spring(response: 0.5, dampingFraction: 0.85)
    static let easeOut = Animation.easeOut(duration: 0.25)
    static let easeInOut = Animation.easeInOut(duration: 0.3)

    // MARK: - Shadows

    static func cardShadow() -> some View {
        neomorphShadow
    }
}

extension Font {
    /// Maps the existing cinema type scale onto semantic Dynamic Type styles.
    /// Call sites retain their visual hierarchy while UIFontMetrics can scale
    /// every readable label for the user's accessibility preference.
    static func fottyScaled(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        let style: Font.TextStyle
        switch size {
        case ..<10.5: style = .caption2
        case ..<12.5: style = .caption
        case ..<15: style = .subheadline
        case ..<18: style = .body
        case ..<20: style = .headline
        case ..<23: style = .title3
        case ..<29: style = .title2
        case ..<34: style = .title
        default: style = .largeTitle
        }
        return .system(style, design: design, weight: weight)
    }
}

// MARK: - View Modifiers

struct TactileGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = FottyTheme.radiusLG
    var isHighlighted: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Deep material blur
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)

                    // Base color layer
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(FottyTheme.surface.opacity(0.4))

                    // Internal highlights (Neomorphism)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.15),
                                    .clear,
                                    .black.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )

                    if isHighlighted {
                        // High-energy glow for favorite teams/active games
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(FottyTheme.accentGradient.opacity(0.4), lineWidth: 2)
                            .blur(radius: 4)
                    }
                }
            )
            .shadow(color: FottyTheme.neomorphShadow, radius: 15, x: 0, y: 10)
            .overlay(
                // Spatial Rim Highlight
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.2),
                                .clear,
                                .white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
    }
}

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = FottyTheme.radiusMD

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.08),
                                    .white.opacity(0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.15),
                                    .white.opacity(0.02),
                                    .white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
            )
            .shadow(color: FottyTheme.neomorphShadow, radius: 10, x: 0, y: 5)
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: FottyTheme.radiusMD)
                    .fill(FottyTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: FottyTheme.radiusMD)
                            .strokeBorder(FottyTheme.border, lineWidth: 0.5)
                    )
            )
    }
}

struct BentoModuleHeader: View {
    let title: String
    var meta: String? = nil
    var inset: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: FottyTheme.spacingSM) {
            Text(title)
                .font(FottyTheme.typeModuleTitle)
                .foregroundStyle(FottyTheme.textPrimary)
                .tracking(0.4)
            Spacer(minLength: 0)
            if let meta {
                Text(meta)
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textTertiary)
            }
        }
        .padding(.horizontal, inset ? FottyTheme.bentoInset : 0)
    }
}

struct BentoSurface: ViewModifier {
    var cornerRadius: CGFloat = FottyTheme.radiusLG

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(FottyTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(FottyTheme.border, lineWidth: 0.5)
            )
    }
}

struct FottyPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FottyTheme.typeAction)
            .foregroundStyle(FottyTheme.textOnAccent)
            .frame(minHeight: 46)
            .padding(.horizontal, FottyTheme.spacingMD)
            .background(configuration.isPressed ? FottyTheme.liveAccent : FottyTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous))
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

struct FottySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FottyTheme.typeAction)
            .foregroundStyle(FottyTheme.textPrimary)
            .frame(minHeight: 44)
            .padding(.horizontal, FottyTheme.spacingMD)
            .background(configuration.isPressed ? FottyTheme.surfaceElevated : FottyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous)
                    .strokeBorder(FottyTheme.borderStrong, lineWidth: 1)
            }
    }
}

struct FottySectionHeader: View {
    let title: String
    var count: Int? = nil
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: FottyTheme.spacingSM) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FottyTheme.typeSectionTitle)
                    .foregroundStyle(FottyTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(FottyTheme.typeMeta)
                        .foregroundStyle(FottyTheme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if let count {
                Text(count == 1 ? "1 match" : "\(count) matches")
                    .font(.fottyScaled(size: 14, weight: .bold))
                    .foregroundStyle(FottyTheme.textPrimary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func tactileGlass(cornerRadius: CGFloat = FottyTheme.radiusLG, isHighlighted: Bool = false) -> some View {
        modifier(TactileGlassModifier(cornerRadius: cornerRadius, isHighlighted: isHighlighted))
    }

    func glassBackground(cornerRadius: CGFloat = FottyTheme.radiusMD) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }

    func cardStyle() -> some View {
        modifier(CardStyle())
    }

    func bentoSurface(cornerRadius: CGFloat = FottyTheme.radiusLG) -> some View {
        modifier(BentoSurface(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
