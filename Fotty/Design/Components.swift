import SwiftUI
import UIKit

// MARK: - Image Caching

final class FottyImageCache: @unchecked Sendable {
    static let shared = FottyImageCache()
    private let memoryCache = NSCache<NSURL, UIImage>()

    private init() {
        memoryCache.countLimit = 600
        memoryCache.totalCostLimit = 60 * 1024 * 1024 // 60 MB
    }

    func image(for url: URL) -> UIImage? {
        memoryCache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4)
        memoryCache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var uiImage: UIImage?

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = uiImage ?? (url.flatMap { FottyImageCache.shared.image(for: $0) }) {
                content(Image(uiImage: image))
            } else {
                placeholder()
                    .task(id: url) {
                        guard let url else { return }
                        if let cached = FottyImageCache.shared.image(for: url) {
                            self.uiImage = cached
                            return
                        }
                        do {
                            let (data, response) = try await URLSession.shared.data(from: url)
                            guard let httpResponse = response as? HTTPURLResponse,
                                  (200...299).contains(httpResponse.statusCode),
                                  let decoded = UIImage(data: data) else {
                                return
                            }
                            FottyImageCache.shared.insert(decoded, for: url)
                            if !Task.isCancelled {
                                self.uiImage = decoded
                            }
                        } catch {
                            // Keep placeholder on error
                        }
                    }
            }
        }
    }
}

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
    @State private var phase: CGFloat = 0
    
    var body: some View {
        LinearGradient(
            colors: [
                FottyTheme.surface,
                FottyTheme.accent.opacity(0.1),
                FottyTheme.surface
            ],
            startPoint: .init(x: phase - 1, y: 0.5),
            endPoint: .init(x: phase, y: 0.5)
        )
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 2
            }
        }
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

// MARK: - Team Badge with Initials Fallback

struct TeamBadgeView: View {
    let badgeURL: URL?
    let teamName: String
    var size: CGFloat = 32
    
    private var initials: String {
        let words = teamName.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(teamName.prefix(2)).uppercased()
    }
    
    var body: some View {
        ZStack {
            if let url = badgeURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure, .empty:
                        initialsView
                    @unknown default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(teamName) badge")
    }
    
    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(FottyTheme.surfaceElevated)
                .overlay {
                    Circle()
                        .strokeBorder(FottyTheme.borderStrong, lineWidth: 1)
                }
            
            Text(initials)
                // Initials are badge artwork; the whole badge scales as a unit
                // and exposes the full team name through VoiceOver.
                .font(.system(size: size * 0.35, weight: .bold, design: .rounded))
                .foregroundStyle(FottyTheme.textSecondary)
                .accessibilityHidden(true)
        }
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
    static func symbol(for category: String) -> String {
        let key = category.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch key {
        case "all", "all-sports": return "square.grid.2x2.fill"
        case "american-football", "nfl", "afl", "rugby": return "american.football.fill"
        case _ where key.contains("football") || key.contains("soccer"): return "soccerball"
        case _ where key.contains("basketball") || key == "nba" || key == "wnba": return "basketball.fill"
        case _ where key.contains("baseball") || key == "mlb": return "baseball.fill"
        case _ where key.contains("cricket"): return "cricket.ball.fill"
        case _ where key.contains("tennis"): return "tennisball.fill"
        case _ where key.contains("hockey") || key == "nhl": return "hockey.puck.fill"
        case _ where key.contains("fight") || key.contains("mma") || key.contains("boxing"): return "figure.boxing"
        case _ where key.contains("f1") || key.contains("nascar") || key.contains("motor"): return "flag.checkered"
        default: return "sportscourt.fill"
        }
    }

    static func ink(for category: String) -> Color {
        switch symbol(for: category) {
        case "basketball.fill", "american.football.fill":
            return FottyTheme.adaptive(light: UIColor(red: 0.57, green: 0.24, blue: 0.04, alpha: 1), dark: UIColor(red: 1, green: 0.62, blue: 0.27, alpha: 1))
        case "baseball.fill", "cricket.ball.fill": return FottyTheme.error
        case "tennisball.fill": return FottyTheme.success
        default: return FottyTheme.textPrimary
        }
    }
}

struct SportEmblem: View {
    let category: String
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: SportIdentity.symbol(for: category))
            .font(.system(size: size, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(SportIdentity.ink(for: category))
            .frame(width: size + 2, height: size + 2)
            .accessibilityHidden(true)
    }
}

struct FlagSquircleBadge: View {
    let name: String
    let badgeURL: URL?
    var size: CGFloat = 64
    /// Soft neon glow — off for cinema hero / dense rows.
    var glowEnabled: Bool = true
    @ObservedObject private var brandService = TeamBrandService.shared

    // Mapping of country names to 2-letter codes for flagcdn, matching web's COUNTRY_CODES
    private static let countryCodes: [String: String] = [
        "argentina": "ar", "egypt": "eg", "switzerland": "ch", "colombia": "co",
        "france": "fr", "morocco": "ma", "mexico": "mx", "south africa": "za",
        "south korea": "kr", "korea": "kr", "czech": "cz", "czechia": "cz",
        "canada": "ca", "bosnia": "ba", "usa": "us", "united states": "us",
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
        "venezuela": "ve", "bolivia": "bo", "honduras": "hn"
    ]
    
    private var resolvedURL: URL? {
        if let badgeURL { return badgeURL }
        
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let key = Self.countryCodes.keys.first(where: { lower.contains($0) }),
           let code = Self.countryCodes[key] {
            return URL(string: "https://flagcdn.com/w160/\(code).png")
        }
        
        return brandService.badgeURL(for: name, triggerSearch: false)
    }
    
    private var initials: String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(3)).uppercased()
    }
    
    var body: some View {
        let color = TeamColorResolver.resolve(teamName: name) ?? Color(hex: "#3f3f46")
        
        return ZStack {
            if let url = resolvedURL {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: max(1, size - 4), height: max(1, size - 4))
                        .frame(width: size, height: size)
                        .accessibilityLabel("\(name) badge")
                        .accessibilityHidden(true)
                } placeholder: {
                    initialsFallbackView(color: color)
                }
            } else {
                initialsFallbackView(color: color)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(Color(hex: "#0a0a0d"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .stroke(color.opacity(glowEnabled ? 0.8 : 0.35), lineWidth: glowEnabled ? 2.5 : 1)
        )
        .if(glowEnabled) { view in
            view
                .shadow(color: color.opacity(0.6), radius: 10, x: 0, y: 0)
                .shadow(color: color.opacity(0.3), radius: 3, x: 0, y: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) badge")
    }
    
    private func initialsFallbackView(color: Color) -> some View {
        ZStack {
            LinearGradient(
                colors: [color.opacity(0.18), Color(hex: "#050506")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Text(initials)
                // Initials are badge artwork; the whole badge scales as a unit
                // and exposes the full team name through VoiceOver.
                .font(.system(size: max(size * 0.36, 10), weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .accessibilityHidden(true)
        }
        .frame(width: size, height: size)
    }
}
