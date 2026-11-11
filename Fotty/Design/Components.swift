import SwiftUI
import UIKit
import ImageIO

// MARK: - Haptic Feedback

enum HapticManager {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
    
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}

// MARK: - Shimmer Loading Effect

struct ShimmerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var allowsMotion: Bool {
        FottyMotionPolicy.allowsContinuousMotion(
            reduceMotion: reduceMotion,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            sceneIsActive: scenePhase == .active
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !allowsMotion)) { timeline in
            let phase = allowsMotion
                ? CGFloat(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5) / 1.5) * 3
                : 1
            LinearGradient(
                colors: [
                    FottyTheme.surface,
                    FottyTheme.accent.opacity(0.1),
                    FottyTheme.surface
                ],
                startPoint: .init(x: phase - 1, y: 0.5),
                endPoint: .init(x: phase, y: 0.5)
            )
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Skeleton Card for Loading States

struct SkeletonCard: View {
    var width: CGFloat = 140
    var height: CGFloat = 210
    
    var body: some View {
        VStack(alignment: .leading, spacing: FottyTheme.spacingSM) {
            ShimmerView()
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD))
            
            ShimmerView()
                .frame(width: width, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
            ShimmerView()
                .frame(width: width * 0.6, height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

// MARK: - Team identity

/// The single badge treatment used anywhere Fotty presents a real team.
/// Supplied artwork wins, then the shared brand cache, then a deliberate
/// monogram. A failed or missing network image never leaves an empty hole.
struct TeamBadgeWindow: View {
    let teamName: String
    var badgeURL: URL? = nil
    /// A projection-owned brand candidate. Supplying this avoids repeating a
    /// main-actor dictionary lookup every time a dense catalog row is rebuilt.
    /// When omitted, the shared safety-net lookup remains available to callers
    /// outside the catalog projection.
    var brandURL: URL? = nil
    /// Distinguishes a projection that found no brand from a caller that did
    /// not precompute one. This keeps nil a truthful fallback without falling
    /// back into repeated lookups while a catalog is being scrolled.
    var brandLookupResolved = false
    var size: CGFloat = 32
    var glowEnabled: Bool = false
    var triggerSearch: Bool = false
    var showsFrame: Bool = true

    private static let countryCodes: [String: String] = [
        "argentina": "ar", "egypt": "eg", "switzerland": "ch", "colombia": "co",
        "france": "fr", "morocco": "ma", "mexico": "mx", "south africa": "za",
        "south korea": "kr", "korea": "kr", "czech republic": "cz", "czechia": "cz",
        "canada": "ca", "bosnia and herzegovina": "ba", "usa": "us", "united states": "us",
        "netherlands": "nl", "belgium": "be", "brazil": "br", "germany": "de",
        "england": "gb-eng", "italy": "it", "spain": "es", "portugal": "pt",
        "croatia": "hr", "uruguay": "uy", "japan": "jp", "australia": "au",
        "senegal": "sn", "ghana": "gh", "cameroon": "cm", "nigeria": "ng",
        "ivory coast": "ci", "iran": "ir", "qatar": "qa", "saudi arabia": "sa",
        "ecuador": "ec", "poland": "pl", "denmark": "dk", "serbia": "rs",
        "wales": "gb-wls", "costa rica": "cr", "panama": "pa", "scotland": "gb-sct",
        "austria": "at", "sweden": "se", "norway": "no", "finland": "fi",
        "turkey": "tr", "romania": "ro", "hungary": "hu", "slovakia": "sk",
        "ukraine": "ua", "russia": "ru", "china": "cn", "india": "in",
        "new zealand": "nz", "paraguay": "py", "chile": "cl", "peru": "pe",
        "venezuela": "ve", "bolivia": "bo", "honduras": "hn",
        // Cricket nations. West Indies has no single national flag and keeps
        // its colour monogram.
        "pakistan": "pk", "sri lanka": "lk", "bangladesh": "bd", "afghanistan": "af",
        "zimbabwe": "zw", "ireland": "ie", "nepal": "np", "oman": "om", "namibia": "na",
        "united arab emirates": "ae", "uae": "ae", "hong kong": "hk", "kenya": "ke",
        "uganda": "ug", "papua new guinea": "pg"
    ]

    private var displayName: String {
        Self.displayName(for: teamName)
    }

    private var resolvedURLs: [URL] {
        Self.candidateURLs(
            explicit: badgeURL,
            country: Self.countryFlagURL(for: displayName),
            // Intentionally read the warm snapshot without observing the whole
            // service. A league refresh must not invalidate every visible row.
            brand: brandLookupResolved
                ? brandURL
                : (brandURL ?? TeamBrandService.shared.badgeURL(for: displayName, triggerSearch: triggerSearch))
        )
    }

    private var initials: String {
        Self.fallbackInitials(for: displayName)
    }

    static func displayName(for teamName: String) -> String {
        let trimmed = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Team" : trimmed
    }

    static func fallbackInitials(for teamName: String) -> String {
        let words = displayName(for: teamName).split(separator: " ")
        if words.count >= 2 {
            return String(words.prefix(2).compactMap(\.first)).uppercased()
        }
        return String(displayName(for: teamName).prefix(3)).uppercased()
    }

    static func countryFlagURL(for teamName: String) -> URL? {
        let lowered = displayName(for: teamName)
            .lowercased()
            .replacingOccurrences(of: " national team", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // A national side keeps its flag whatever the squad: "Uganda Women",
        // "India U19", "Pakistan A". Clubs never match a country name.
        let normalized = lowered.replacingOccurrences(
            of: #"\s+(?:women|women's|womens|w|ladies|u-?\d{2}|under[- ]\d{2}|a|xi)$"#,
            with: "", options: .regularExpression)
        guard let code = countryCodes[normalized] ?? countryCodes[lowered] else { return nil }
        return URL(string: "https://flagcdn.com/w160/\(code).png")
    }

    static func candidateURLs(explicit: URL?, country: URL?, brand: URL?) -> [URL] {
        var seen = Set<String>()
        return [explicit, country, brand].compactMap { candidate in
            guard let candidate, seen.insert(candidate.absoluteString).inserted else { return nil }
            return candidate
        }
    }

    var body: some View {
        let color = TeamColorResolver.resolve(teamName: displayName) ?? FottyTheme.textTertiary

        ZStack {
            if !resolvedURLs.isEmpty {
                CachedAsyncImage(urls: resolvedURLs) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(max(2, size * 0.08))
                        // Catalyst can expose the resolved bitmap even when
                        // the outer badge is a combined accessibility element.
                        // Give that underlying image the same truthful name.
                        .accessibilityLabel("\(displayName) badge")
                } placeholder: {
                    initialsFallback(color: color)
                }
            } else {
                initialsFallback(color: color)
            }
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(usesDarkPlate ? Self.darkPlate : FottyTheme.surfaceElevated)
        )
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .stroke(color.opacity(showsFrame ? (glowEnabled ? 0.8 : 0.35) : 0), lineWidth: glowEnabled ? 2 : 1)
        }
        .if(glowEnabled) { view in
            view.shadow(color: color.opacity(0.45), radius: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(displayName) badge")
    }

    /// Light-on-transparent crests (Abu Dhabi T10) need a dark plate on light
    /// rows; the same plate is used in dark mode so the badge looks identical.
    private var usesDarkPlate: Bool {
        resolvedURLs.contains { TeamBrandService.darkPlateBadgeURLs.contains($0) }
    }
    private static let darkPlate = Color(red: 0.10, green: 0.11, blue: 0.14)

    private func initialsFallback(color: Color) -> some View {
        ZStack {
            LinearGradient(
                colors: [color.opacity(0.2), FottyTheme.surfaceElevated],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(initials)
                .font(.system(size: max(size * 0.34, 8), weight: .black, design: .rounded))
                .foregroundStyle(FottyTheme.textPrimary)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier("team-badge-decorative-initials")
                .accessibilityHidden(true)
        }
    }
}

/// An atomic team-name presentation. Use this rather than a bare `Text` when
/// the label identifies a team (as opposed to mentioning one inside prose).
struct TeamIdentityLabel: View {
    let teamName: String
    var badgeURL: URL? = nil
    var badgeSize: CGFloat = 24
    var font: Font = FottyTheme.typeBody
    var foregroundColor: Color = FottyTheme.textPrimary
    var lineLimit: Int = 1
    var triggerSearch: Bool = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: max(5, badgeSize * 0.25)) {
            TeamBadgeWindow(
                teamName: teamName,
                badgeURL: badgeURL,
                size: badgeSize,
                triggerSearch: triggerSearch
            )
            Text(teamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Team" : teamName)
                .font(font)
                .foregroundStyle(foregroundColor)
                .lineLimit(typeSize.isAccessibilitySize ? nil : lineLimit)
                .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(teamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Team" : teamName)
    }
}

/// Compatibility wrapper for older call sites. The visual contract is now the
/// same badge window used by new surfaces.
struct TeamBadgeView: View {
    let badgeURL: URL?
    let teamName: String
    var size: CGFloat = 32

    var body: some View {
        TeamBadgeWindow(teamName: teamName, badgeURL: badgeURL, size: size)
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: FottyTheme.spacingMD) {
            ZStack {
                Circle()
                    .fill(FottyTheme.surface)
                    .frame(width: 80, height: 80)
                
                Image(systemName: icon)
                    .font(.fottyScaled(size: 32))
                    .foregroundStyle(FottyTheme.textTertiary)
            }
            
            Text(title)
                .font(.fottyScaled(size: 18, weight: .semibold))
                .foregroundStyle(FottyTheme.textPrimary)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(FottyTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, FottyTheme.spacingLG)
            
            if let actionTitle, let action {
                Button(action: {
                    HapticManager.impact(.light)
                    action()
                }) {
                    Text(actionTitle)
                        .font(.fottyScaled(size: 15, weight: .bold))
                        .foregroundStyle(FottyTheme.textOnAccent)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(
                            ZStack {
                                FottyTheme.accentGradient
                                
                                // Subtle highlight
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(
                                        LinearGradient(
                                            colors: [.white.opacity(0.2), .clear],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: FottyTheme.accent.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.top, FottyTheme.spacingSM)
            }
        }
        .padding(FottyTheme.spacingLG)
    }
}

// MARK: - Scroll Indicator Arrows

struct ScrollIndicatorArrows: ViewModifier {
    @State private var showLeftArrow = false
    @State private var showRightArrow = true
    
    func body(content: Content) -> some View {
        content
    }
}

struct LeadingScrollArrow: View {
    @Binding var isVisible: Bool
    
    var body: some View {
        if isVisible {
            Image(systemName: "chevron.left")
                .font(.fottyScaled(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(8)
                .background(Circle().fill(Color.black.opacity(0.4)))
        }
    }
}

struct TrailingScrollArrow: View {
    @Binding var isVisible: Bool
    
    var body: some View {
        if isVisible {
            Image(systemName: "chevron.right")
                .font(.fottyScaled(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(8)
                .background(Circle().fill(Color.black.opacity(0.4)))
        }
    }
}

// MARK: - Branded control feedback

/// For controls that already supply their own label, surface and hit region.
/// Keep feedback local to the button: no scaling, delayed animation, or gesture
/// layer that could compete with scrolling or playback controls.
struct FottyPressButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = FottyTheme.radiusSM

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(FottyPressFeedback(isPressed: configuration.isPressed, cornerRadius: cornerRadius))
    }
}

struct FottyPressFeedback: ViewModifier {
    let isPressed: Bool
    var cornerRadius: CGFloat = FottyTheme.radiusSM
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPressed && isEnabled {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.primary.opacity(0.10))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
    }
}

// MARK: - Inline action confirmation

/// One local, dismissible acknowledgement. The caller owns the accepted action
/// and one-use Undo receipt; this view never schedules or mutates anything itself.
struct FottyInlineFeedback: View {
    let title: String
    let detail: String?
    var symbol: String = "checkmark"
    var isWorking = false
    var onUndo: (() -> Void)? = nil
    let onDismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        MatchRowLayout(minimumInformationWidth: 140, forceStack: typeSize.isAccessibilitySize, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FottyTheme.success)
                    .frame(width: 24)
                    .frame(minHeight: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FottyTheme.textPrimary)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(FottyTheme.typeCaption)
                            .foregroundStyle(FottyTheme.textSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 0) {
                if isWorking {
                    ProgressView()
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Updating")
                } else if let onUndo {
                    Button("Undo", action: onUndo)
                        .font(FottyTheme.typeAction)
                        .foregroundStyle(FottyTheme.accentText)
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Undo \(title.lowercased())")
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FottyTheme.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss confirmation")
            }
            .buttonStyle(FottyPressButtonStyle())
        }
        .padding(8)
        .background(FottyTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: FottyTheme.radiusMD))
        .overlay {
            RoundedRectangle(cornerRadius: FottyTheme.radiusMD)
                .strokeBorder(FottyTheme.border, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Pill Button Style

struct PillButtonStyle: ButtonStyle {
    var accent: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.fottyScaled(size: 14, weight: .semibold))
            .foregroundStyle(accent ? FottyTheme.textOnAccent : FottyTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(backgroundFill)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
    
    @ViewBuilder
    private var backgroundFill: some View {
        if accent {
            FottyTheme.accentGradient
        } else {
            FottyTheme.surface
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static func pill(accent: Bool = false) -> PillButtonStyle {
        PillButtonStyle(accent: accent)
    }
}

// MARK: - Media Card (Poster)

struct MediaCard: View {
    let title: String
    let posterURL: URL?
    let rating: Double?
    let mediaType: String?
    var width: CGFloat = 140
    
    private var height: CGFloat { width * 1.5 }
    
    var body: some View {
        VStack(alignment: .leading, spacing: FottyTheme.spacingSM) {
            // Poster
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: posterURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        posterPlaceholder
                    case .empty:
                        ShimmerView()
                    @unknown default:
                        posterPlaceholder
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD))
                
                // Rating badge
                if let rating, rating > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.fottyScaled(size: 8))
                        Text(String(format: "%.1f", rating))
                            .font(.fottyScaled(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(.black.opacity(0.7))
                            .overlay(
                                Capsule()
                                    .strokeBorder(FottyTheme.accent.opacity(0.5), lineWidth: 0.5)
                            )
                    )
                    .padding(6)
                }
            }
            
            // Title
            Text(title)
                .font(.headline)
                .foregroundStyle(FottyTheme.textPrimary)
                .lineLimit(2)
                .frame(width: width, alignment: .leading)
            
            // Type badge
            if let mediaType {
                Text(mediaType.uppercased())
                    .font(.fottyScaled(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(FottyTheme.textTertiary)
                    .tracking(0.5)
            }
        }
    }
    
    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: FottyTheme.radiusMD)
            .fill(FottyTheme.surface)
            .overlay(
                Image(systemName: "film")
                    .font(.title)
                    .foregroundStyle(FottyTheme.textTertiary)
            )
    }
}

// MARK: - Hero Banner

struct HeroBanner: View {
    let title: String
    let overview: String
    let backdropURL: URL?
    let onPlay: () -> Void
    let onDetail: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
            Spacer()
            
            Text(title)
                .font(.fottyScaled(size: 28, weight: .bold))
                .foregroundStyle(FottyTheme.textPrimary)
            
            Text(overview)
                .font(.fottyScaled(size: 14))
                .foregroundStyle(FottyTheme.textSecondary)
                .lineLimit(2)
            
            HStack(spacing: FottyTheme.spacingMD) {
                Button {
                    HapticManager.impact(.medium)
                    onPlay()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.fottyScaled(size: 14))
                        Text("Watch Now")
                            .font(.headline)
                    }
                    .accessibilityLabel("Watch Now")
                    .accessibilityHint("Starts live stream for this match.")
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(FottyTheme.accentGradient)
                    .clipShape(Capsule())
                }
                
                Button(action: onDetail) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.fottyScaled(size: 14))
                        Text("Match Details")
                            .font(.fottyScaled(size: 15, weight: .medium))
                    }
                    .foregroundStyle(FottyTheme.textPrimary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassBackground(cornerRadius: 20)
                }
            }
        }
        .padding(FottyTheme.spacingLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 460)
        .background {
            ZStack {
                AsyncImage(url: backdropURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        Rectangle().fill(FottyTheme.surface)
                    @unknown default:
                        Rectangle().fill(FottyTheme.surface)
                    }
                }
                
                FottyTheme.heroGradient
            }
            .frame(height: 460)
            .clipped()
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.fottyScaled(size: 20, weight: .bold))
                    .foregroundStyle(FottyTheme.textPrimary)
                
                if let subtitle {
                    Text(subtitle)
                        .font(.fottyScaled(size: 13))
                        .foregroundStyle(FottyTheme.textTertiary)
                }
            }
            
            Spacer()
            
            if let action {
                Button(action: action) {
                    Text("See All")
                        .font(.fottyScaled(size: 13, weight: .semibold))
                        .foregroundStyle(FottyTheme.accentText)
                }
            }
        }
        .padding(.horizontal, FottyTheme.spacingMD)
    }
}

// MARK: - Live Pulse Indicator

struct LivePulse: View {
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(FottyTheme.liveAccent)
                .frame(width: 6, height: 6)
                .scaleEffect(isPulsing ? 1.4 : 1.0)
                .opacity(isPulsing ? 0.6 : 1.0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            
            Text("LIVE")
                .font(.fottyScaled(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(FottyTheme.accentText)
                .tracking(0.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            ZStack {
                Capsule()
                    .fill(FottyTheme.liveAccent.opacity(0.12))
                
                Capsule()
                    .strokeBorder(FottyTheme.liveAccent.opacity(0.3), lineWidth: 0.5)
            }
        )
        .onAppear { isPulsing = !reduceMotion }
        .onChange(of: reduceMotion) { _, value in isPulsing = !value }
        .onDisappear { isPulsing = false }
    }
}

// MARK: - Share Sheet Helper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let excludedActivityTypes: [UIActivity.ActivityType]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.excludedActivityTypes = excludedActivityTypes
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
extension View {
    func pillButtonStyle(accent: Bool) -> some View {
        self
            .font(.fottyScaled(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(accent ? FottyTheme.accent.opacity(0.20) : FottyTheme.surfaceElevated))
            .foregroundStyle(accent ? FottyTheme.accentText : FottyTheme.textSecondary)
    }
}

// MARK: - Flag Squircle Badge

/// Shared sport identity for Home tiles, filters and competition headings.
/// Equipment silhouettes stay recognisable without relying on colour alone.
enum SportIdentity {
    /// Full-colour Apple equipment artwork for discovery surfaces. Standard
    /// actions continue to use SF Symbols; this artwork is the recognizable
    /// sports identity the owner approved for Home.
    static func artwork(for category: String) -> String? {
        let key = normalizedKey(category)
        switch key {
        case "", "all", "all-sports": return nil
        case "american-football", "american football", "nfl", "afl", "cfl": return "🏈"
        case _ where key.contains("rugby"): return "🏉"
        case _ where key.contains("football") || key.contains("soccer"): return "⚽️"
        case _ where key.contains("basketball") || key == "nba" || key == "wnba": return "🏀"
        case _ where key.contains("baseball") || key == "mlb": return "⚾️"
        case _ where key.contains("cricket"): return "🏏"
        case _ where key.contains("table tennis") || key.contains("table-tennis") || key.contains("ping pong") || key.contains("ping-pong"): return "🏓"
        case _ where key.contains("tennis"): return "🎾"
        case _ where key.contains("hockey") || key == "nhl": return "🏒"
        case _ where key.contains("fight") || key.contains("mma") || key.contains("boxing"): return "🥊"
        case _ where key.contains("f1") || key.contains("formula 1") || key.contains("formula-1") || key == "formula1" || key.contains("nascar") || key.contains("motor") || key.contains("racing"): return "🏎️"
        case _ where key.contains("dart"): return "🎯"
        case _ where key.contains("golf"): return "⛳️"
        case _ where key.contains("volleyball"): return "🏐"
        case _ where key.contains("handball"): return "🤾"
        case _ where key.contains("lacrosse"): return "🥍"
        case _ where key.contains("cycl") || key.contains("bicycle"): return "🚴"
        default: return "🏟️"
        }
    }

    static func symbol(for category: String) -> String {
        let key = normalizedKey(category)
        switch key {
        case "", "all", "all-sports": return "square.grid.2x2.fill"
        case "american-football", "american football", "nfl", "afl", "cfl": return "american.football.fill"
        case _ where key.contains("rugby"): return "figure.rugby"
        case _ where key.contains("football") || key.contains("soccer"): return "soccerball"
        case _ where key.contains("basketball") || key == "nba" || key == "wnba": return "basketball.fill"
        case _ where key.contains("baseball") || key == "mlb": return "baseball.fill"
        case _ where key.contains("cricket"): return "cricket.ball.fill"
        case _ where key.contains("table tennis") || key.contains("table-tennis") || key.contains("ping pong") || key.contains("ping-pong"): return "figure.table.tennis"
        case _ where key.contains("tennis"): return "tennisball.fill"
        case _ where key.contains("hockey") || key == "nhl": return "hockey.puck.fill"
        case _ where key.contains("fight") || key.contains("mma") || key.contains("boxing"): return "figure.boxing"
        case _ where key.contains("f1") || key.contains("formula 1") || key.contains("formula-1") || key == "formula1" || key.contains("nascar") || key.contains("motor") || key.contains("racing"): return "flag.checkered"
        case _ where key.contains("dart"): return "scope"
        case _ where key.contains("golf"): return "figure.golf"
        case _ where key.contains("volleyball"): return "volleyball.fill"
        case _ where key.contains("handball"): return "figure.handball"
        case _ where key.contains("lacrosse"): return "figure.lacrosse"
        case _ where key.contains("cycl") || key.contains("bicycle"): return "bicycle"
        case _ where key.contains("college"): return "graduationcap.fill"
        default: return "sportscourt.fill"
        }
    }

    static func ink(for category: String) -> Color {
        switch symbol(for: category) {
        case "square.grid.2x2.fill": return FottyTheme.accentText
        case "soccerball", "tennisball.fill", "figure.golf": return FottyTheme.success
        case "basketball.fill", "american.football.fill":
            return FottyTheme.adaptive(light: UIColor(red: 0.57, green: 0.24, blue: 0.04, alpha: 1), dark: UIColor(red: 1, green: 0.62, blue: 0.27, alpha: 1))
        case "baseball.fill", "cricket.ball.fill", "figure.boxing": return FottyTheme.error
        case "hockey.puck.fill", "figure.table.tennis", "volleyball.fill":
            return FottyTheme.adaptive(light: UIColor(red: 0.07, green: 0.35, blue: 0.65, alpha: 1), dark: UIColor(red: 0.31, green: 0.68, blue: 0.98, alpha: 1))
        case "figure.rugby", "figure.handball", "figure.lacrosse", "bicycle":
            return FottyTheme.adaptive(light: UIColor(red: 0.02, green: 0.38, blue: 0.38, alpha: 1), dark: UIColor(red: 0.22, green: 0.82, blue: 0.78, alpha: 1))
        case "scope":
            return FottyTheme.adaptive(light: UIColor(red: 0.42, green: 0.24, blue: 0.64, alpha: 1), dark: UIColor(red: 0.72, green: 0.55, blue: 0.96, alpha: 1))
        case "graduationcap.fill": return FottyTheme.textSecondary
        case "flag.checkered": return FottyTheme.accentText
        default: return FottyTheme.textSecondary
        }
    }

    private static func normalizedKey(_ category: String) -> String {
        category
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
    }
}

struct SportEmblem: View {
    let category: String
    var size: CGFloat = 26
    var isActive: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ink: Color { SportIdentity.ink(for: category) }

    var body: some View {
        Group {
            if let artwork = SportIdentity.artwork(for: category) {
                Text(artwork)
                    .font(.system(size: size * 1.02))
                    .frame(width: size + 6, height: size + 6)
            } else {
                ZStack {
                    Circle()
                        .fill(ink.opacity(isActive ? 0.20 : 0.10))
                    Circle()
                        .strokeBorder(ink.opacity(isActive ? 0.65 : 0.20), lineWidth: isActive ? 1.5 : 1)
                    Image(systemName: SportIdentity.symbol(for: category))
                        .font(.system(size: size * 0.58, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(ink)
                }
                .frame(width: size + 4, height: size + 4)
            }
        }
        .scaleEffect(isActive && !reduceMotion ? 1.06 : 1)
        .animation(reduceMotion ? nil : FottyTheme.springSnappy, value: isActive)
        .accessibilityHidden(true)
    }
}

struct FlagSquircleBadge: View {
    let name: String
    let badgeURL: URL?
    var brandURL: URL? = nil
    var brandLookupResolved = false
    var size: CGFloat = 64
    /// Soft neon glow — off for cinema hero / dense rows.
    var glowEnabled: Bool = true
    var body: some View {
        TeamBadgeWindow(
            teamName: name,
            badgeURL: badgeURL,
            brandURL: brandURL,
            brandLookupResolved: brandLookupResolved,
            size: size,
            glowEnabled: glowEnabled
        )
    }
}
