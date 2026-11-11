import SwiftUI

// MARK: - Sport motion language

enum SportMotionStyle: String, CaseIterable {
    case multiSport
    case football
    case cricket
    case tennis
    case tableTennis
    case basketball
    case baseball
    case hockey
    case americanFootball
    case rugby
    case motorsport
    case combat
    case golf
    case darts
    case volleyball
    case handball
    case lacrosse
    case cycling
    case generic
}

struct SportMotionProfile {
    let style: SportMotionStyle
    let displayName: String
    let symbol: String
    let accent: Color
    var competition: FootballCompetitionID? = nil

    static func profile(for rawCategory: String, competition: FootballCompetitionID? = nil) -> SportMotionProfile {
        let key = rawCategory.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        if key == "all" || key == "all-sports" || key.isEmpty {
            return .init(style: .multiSport, displayName: "sports", symbol: "square.grid.2x2.fill", accent: FottyTheme.accent)
        }
        if key.contains("rugby") {
            return .init(style: .rugby, displayName: "rugby", symbol: SportIdentity.symbol(for: key), accent: SportIdentity.ink(for: key))
        }
        if key == "american-football" || key == "american football" || key == "nfl" || key == "afl" || key == "cfl" {
            return .init(style: .americanFootball, displayName: "American football", symbol: SportIdentity.symbol(for: key), accent: SportIdentity.ink(for: key))
        }
        if key.contains("football") || key.contains("soccer") {
            return .init(style: .football, displayName: "football", symbol: "soccerball",
                         accent: competition == .championsLeague ? .blue : FottyTheme.accent,
                         competition: competition == .championsLeague ? competition : nil)
        }
        if key.contains("cricket") {
            return .init(style: .cricket, displayName: "cricket", symbol: "cricket.ball.fill", accent: FottyTheme.error)
        }
        if key.contains("table-tennis") || key.contains("table tennis") || key.contains("ping-pong") || key.contains("ping pong") {
            return .init(style: .tableTennis, displayName: "table tennis", symbol: "figure.table.tennis", accent: SportIdentity.ink(for: "table-tennis"))
        }
        if key.contains("tennis") || key == "atp" || key == "wta" {
            return .init(style: .tennis, displayName: "tennis", symbol: "tennisball.fill", accent: FottyTheme.success)
        }
        if key.contains("basketball") || key == "nba" || key == "wnba" {
            return .init(style: .basketball, displayName: "basketball", symbol: "basketball.fill", accent: Color(red: 0.95, green: 0.48, blue: 0.12))
        }
        if key.contains("baseball") || key == "mlb" {
            return .init(style: .baseball, displayName: "baseball", symbol: "baseball.fill", accent: FottyTheme.error)
        }
        if key.contains("hockey") || key == "nhl" {
            return .init(style: .hockey, displayName: "hockey", symbol: "hockey.puck.fill", accent: Color(red: 0.25, green: 0.66, blue: 0.95))
        }
        if key.contains("f1") || key.contains("formula 1") || key.contains("formula-1") || key == "formula1" || key.contains("nascar") || key.contains("motor") || key.contains("racing") {
            return .init(style: .motorsport, displayName: "motorsport", symbol: "flag.checkered", accent: FottyTheme.accent)
        }
        if key.contains("fight") || key.contains("mma") || key.contains("boxing") || ["ufc", "pfl", "bellator", "one"].contains(key) {
            return .init(style: .combat, displayName: "combat sports", symbol: "figure.boxing", accent: FottyTheme.error)
        }
        if key.contains("golf") || key == "pga" {
            return .init(style: .golf, displayName: "golf", symbol: "figure.golf", accent: SportIdentity.ink(for: "golf"))
        }
        if key.contains("dart") {
            return .init(style: .darts, displayName: "darts", symbol: "scope", accent: SportIdentity.ink(for: "darts"))
        }
        if key.contains("volleyball") {
            return .init(style: .volleyball, displayName: "volleyball", symbol: "volleyball.fill", accent: SportIdentity.ink(for: "volleyball"))
        }
        if key.contains("handball") {
            return .init(style: .handball, displayName: "handball", symbol: "figure.handball", accent: SportIdentity.ink(for: "handball"))
        }
        if key.contains("lacrosse") {
            return .init(style: .lacrosse, displayName: "lacrosse", symbol: "figure.lacrosse", accent: SportIdentity.ink(for: "lacrosse"))
        }
        if key.contains("cycl") || key.contains("bicycle") {
            return .init(style: .cycling, displayName: "cycling", symbol: "bicycle", accent: SportIdentity.ink(for: "cycling"))
        }
        let displayName = key
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return .init(
            style: .generic,
            displayName: displayName.isEmpty ? "sport" : displayName,
            symbol: SportIdentity.symbol(for: key),
            accent: SportIdentity.ink(for: key)
        )
    }

    var selectionRotation: Double {
        switch style {
        case .football, .basketball, .baseball, .volleyball, .handball: return 16
        case .cricket, .tennis, .tableTennis: return -12
        case .americanFootball, .rugby: return -18
        case .hockey, .motorsport: return 8
        case .golf, .darts, .lacrosse, .cycling, .combat, .multiSport, .generic: return 0
        }
    }
}

enum FottyMotionPolicy {
    static func allowsContinuousMotion(
        reduceMotion: Bool,
        lowPowerMode: Bool,
        sceneIsActive: Bool
    ) -> Bool {
        !reduceMotion && !lowPowerMode && sceneIsActive
    }
}

/// A decorative treatment, not a new competition classifier. Official evidence
/// needs the exact reviewed team pair and a nearby kickoff; provider evidence
/// must explicitly identify UEFA, and may not be youth/women's/AFC metadata.
enum SportMotionContext {
    @MainActor
    static func competition(for event: EventReference?) -> FootballCompetitionID? {
        guard let event, event.normalizedCategory == "football", !event.hasCatalogIdentityConflict else { return nil }
        let official = LiveScoreService.shared.findMatch(
            home: event.homeName, away: event.awayName, near: event.kickoffDate,
            maximumKickoffDelta: CatalogPlaybackIdentity.kickoffTolerance
        )
        return competition(for: event, officialMatch: official)
    }

    @MainActor
    static func competition(for event: EventReference, officialMatch: FootballMatch?) -> FootballCompetitionID? {
        guard event.normalizedCategory == "football", !event.hasCatalogIdentityConflict else { return nil }
        func teamKey(_ name: String) -> String {
            FootballCompetitionCatalog.canonicalClubID(for: name) ?? SportsTeamIdentity.normalized(name)
        }
        let official = officialMatch.flatMap { match -> FootballMatch? in
            guard let kickoff = event.kickoffDate, let officialKickoff = match.matchDate,
                  abs(kickoff.timeIntervalSince(officialKickoff)) <= CatalogPlaybackIdentity.kickoffTolerance,
                  teamKey(event.homeName) == teamKey(match.homeTeam.displayName),
                  teamKey(event.awayName) == teamKey(match.awayTeam.displayName) else { return nil }
            return match
        }
        let evidence = SportsTeamIdentity.normalized(
            [event.id, event.title ?? "", event.homeName, event.awayName].joined(separator: " ")
        )
        let exclusions = #"\b(women|womens|ladies|youth|academy|reserves?|u\s?\d{1,2}|under\s?\d{1,2}|(?:afc|concacaf|caf)\s+champions)\b"#
        guard evidence.range(of: exclusions, options: .regularExpression) == nil else { return nil }
        let classification = AnalyticalDataEngine.footballLeagueClassification(for: event, officialMatch: official)
        guard classification.tab == .championsLeague else { return nil }
        if classification.evidence == .officialFixture { return .championsLeague }
        return evidence.range(of: #"\b(uefa champions league|ucl)\b"#, options: .regularExpression) != nil
            ? .championsLeague : nil
    }
}

/// Pure, bounded pose math: no timers, state mutation, sound or physics engine.
/// Each equipment family has a restrained rhythm. Contact and loop joins are
/// smooth; complete wheel turns wrap without an orientation jump.
struct SportMotionPose {
    static let duration: TimeInterval = 2.4
    let phase: Double
    let x: CGFloat
    let lift: CGFloat
    let rotation: Double
    let squash: CGFloat

    init(style: SportMotionStyle, elapsed: TimeInterval, animated: Bool) {
        let phase = elapsed.isFinite ? max(0, elapsed).truncatingRemainder(dividingBy: Self.duration) / Self.duration : 0
        self.phase = animated ? phase : 0
        guard animated else { x = 0; lift = 0; rotation = 0; squash = 0; return }
        let wave = CGFloat(sin(phase * .pi * 2))
        let bounce = CGFloat(abs(sin(phase * .pi * 2)))
        let height = bounce * bounce
        let arc = CGFloat((1 - cos(phase * .pi * 2)) / 2)
        switch style {
        case .football: x = wave * 10; lift = height * 2; rotation = Double(wave) * 24; squash = 0
        case .cricket:
            // Match the approved activity illustration's small sway and seam
            // rocking. Smooth contact keeps the loop gentle at either landing.
            let contact = 1 - height
            x = wave * 6
            lift = height * 16
            rotation = Double(wave) * 12
            squash = contact * contact * contact * contact * 0.04
            return
        case .basketball:
            x = wave * 2; lift = height * 20; rotation = Double(wave) * 10
            squash = pow(1 - height, 4) * 0.045
        case .tennis:
            x = wave * 14; lift = height * 17; rotation = Double(wave) * -22
            squash = pow(1 - height, 4) * 0.025
        case .tableTennis: x = wave * 14; lift = height * 12; rotation = Double(wave) * 18; squash = 0
        case .baseball: x = wave * 12; lift = 6 + wave * 5; rotation = Double(wave) * 22; squash = 0
        case .americanFootball: x = wave * 10; lift = arc * 10; rotation = Double(wave) * 14; squash = 0
        case .rugby: x = wave * 7; lift = height * 12; rotation = Double(wave) * 9; squash = 0
        case .hockey: x = wave * 18; lift = 0; rotation = 0; squash = 0
        case .motorsport: x = 0; lift = 0; rotation = phase * 360; squash = 0
        case .combat: x = arc * 7; lift = height * 2; rotation = Double(wave) * 4; squash = 0
        case .golf: x = wave * 12; lift = 0; rotation = Double(wave) * 26; squash = 0
        case .darts: x = wave * 6; lift = arc * 3; rotation = Double(wave) * 4; squash = 0
        case .volleyball: x = wave * 5; lift = arc * 18; rotation = Double(wave) * -18; squash = 0
        case .handball: x = wave * 8; lift = height * 10; rotation = Double(wave) * 16; squash = 0
        case .lacrosse: x = wave * 4; lift = height * 6; rotation = Double(wave) * 5; squash = 0
        case .cycling: x = 0; lift = height * 1.5; rotation = phase * 360; squash = 0
        case .multiSport: x = 0; lift = height * 4; rotation = Double(wave) * 12; squash = 0
        case .generic: x = 0; lift = arc * 3; rotation = 0; squash = 0
        }
    }
}

/// One tiny Canvas, at most 30 fps, only while the loading surface is visible.
/// The same artwork becomes still for reduced motion, low power and background.
struct SportLoadingView: View {
    let category: String
    var size: CGFloat = 40
    var label: String? = nil
    var competition: FootballCompetitionID? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var startedAt = Date()

    private var profile: SportMotionProfile { .profile(for: category, competition: competition) }
    private var allowsMotion: Bool {
        isVisible && FottyMotionPolicy.allowsContinuousMotion(
            reduceMotion: reduceMotion, lowPowerMode: lowPowerMode, sceneIsActive: scenePhase == .active
        )
    }
    private var resolvedLabel: String { label ?? "Loading \(profile.displayName)…" }

    var body: some View {
        // Resolve identity outside the animation closure; frames draw only local geometry.
        let resolvedProfile = profile
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !allowsMotion)) { timeline in
                SportMotionArtwork(profile: resolvedProfile,
                                   elapsed: timeline.date.timeIntervalSince(startedAt), animated: allowsMotion)
            }
            .frame(width: size * 2.8, height: size * 2.1)
            .accessibilityHidden(true)
            .allowsHitTesting(false)

            if !resolvedLabel.isEmpty {
                Text(resolvedLabel)
                    .font(.fottyScaled(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(FottyTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(resolvedLabel.isEmpty ? "Loading \(profile.displayName)" : resolvedLabel)
        .onAppear {
            startedAt = Date()
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            isVisible = true
        }
        .onDisappear { isVisible = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}

/// Original vector equipment with stationary lighting, rotating markings and
/// contact shadows. Logical canvas is 160 x 120; no images, blur layers or downloads.
struct SportMotionArtwork: View {
    let profile: SportMotionProfile
    let elapsed: TimeInterval
    var animated = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 160, y: size.height / 120)
            draw(in: context)
        }
        .accessibilityHidden(true)
    }

    private var dark: Bool { colorScheme == .dark }
    private var ink: Color {
        dark ? Color.white.opacity(contrast == .increased ? 0.48 : 0.22)
            : Color.black.opacity(contrast == .increased ? 0.42 : 0.2)
    }
    private var edgeInk: Color {
        dark ? Color.white.opacity(contrast == .increased ? 0.7 : 0.35)
            : Color.black.opacity(contrast == .increased ? 0.65 : 0.28)
    }
    private var blue: Color { Color(red: 0.22, green: 0.51, blue: 0.98) }
    private var isChampionsLeague: Bool { profile.competition == .championsLeague }

    private func line(_ points: [CGPoint], in context: GraphicsContext, color: Color, width: CGFloat = 1) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func draw(in context: GraphicsContext) {
        let pose = SportMotionPose(style: profile.style, elapsed: elapsed, animated: animated)
        switch profile.style {
        case .motorsport: racing(in: context, pose: pose)
        case .combat: gloves(in: context, pose: pose)
        case .golf: golf(in: context, pose: pose)
        case .darts: darts(in: context, pose: pose)
        case .tableTennis: tableTennis(in: context, pose: pose)
        case .lacrosse: lacrosse(in: context, pose: pose)
        case .cycling: cycling(in: context, pose: pose)
        case .multiSport:
            ground(in: context, style: .multiSport)
            ball(in: context, style: .basketball, at: CGPoint(x: 111, y: 77 - pose.lift / 2), radius: 22, rotation: pose.rotation)
            ball(in: context, style: .cricket, at: CGPoint(x: 48, y: 77 - pose.lift / 2), radius: 22, rotation: -pose.rotation)
            ball(in: context, style: .football, at: CGPoint(x: 80, y: 62 - pose.lift), radius: 29, rotation: pose.rotation)
        case .generic:
            ground(in: context, style: .generic)
            var symbol = context.resolve(Image(systemName: profile.symbol))
            symbol.shading = .color(profile.accent)
            context.draw(symbol, in: CGRect(x: 54, y: 33 - pose.lift, width: 52, height: 52))
        default:
            ground(in: context, style: profile.style)
            if isChampionsLeague { stadium(in: context, phase: pose.phase) }
            let center = CGPoint(x: 80 + pose.x, y: 74 - pose.lift)
            let shadowWidth: CGFloat = 52 - pose.lift * 0.5
            context.fill(Path(ellipseIn: CGRect(x: center.x - shadowWidth / 2, y: 101, width: shadowWidth, height: 5)),
                         with: .color(.black.opacity(dark ? 0.5 : 0.14)))
            if profile.style == .hockey {
                puck(in: context, at: CGPoint(x: center.x, y: 80))
            } else if profile.style == .americanFootball || profile.style == .rugby {
                ovalBall(in: context, at: center, pose: pose)
            } else {
                var scaled = context
                scaled.translateBy(x: center.x, y: center.y + 29 * pose.squash)
                scaled.scaleBy(x: 1 + pose.squash, y: 1 - pose.squash)
                ball(in: scaled, style: profile.style, at: .zero, radius: 29, rotation: pose.rotation)
            }
        }
    }

    private func ground(in context: GraphicsContext, style: SportMotionStyle) {
        line([CGPoint(x: 22, y: 104), CGPoint(x: 138, y: 104)], in: context, color: ink)
        if [.football, .basketball, .tennis, .cricket, .volleyball, .handball].contains(style) {
            var marking = Path()
            if style == .cricket {
                marking.move(to: CGPoint(x: 40, y: 111)); marking.addLine(to: CGPoint(x: 54, y: 96))
                marking.addLine(to: CGPoint(x: 112, y: 96)); marking.addLine(to: CGPoint(x: 125, y: 111))
            } else if style == .basketball {
                marking.addRoundedRect(in: CGRect(x: 58, y: 96, width: 44, height: 16), cornerSize: CGSize(width: 3, height: 3))
                marking.move(to: CGPoint(x: 80, y: 96)); marking.addLine(to: CGPoint(x: 80, y: 112))
            } else if [.tennis, .volleyball, .handball].contains(style) {
                marking.move(to: CGPoint(x: 42, y: 113)); marking.addLine(to: CGPoint(x: 55, y: 96))
                marking.addLine(to: CGPoint(x: 105, y: 96)); marking.addLine(to: CGPoint(x: 118, y: 113))
                marking.move(to: CGPoint(x: 50, y: 104)); marking.addLine(to: CGPoint(x: 110, y: 104))
            } else {
                marking.addEllipse(in: CGRect(x: 55, y: 96, width: 50, height: 16))
                marking.move(to: CGPoint(x: 80, y: 95)); marking.addLine(to: CGPoint(x: 80, y: 114))
            }
            context.stroke(marking, with: .color(ink), lineWidth: 1.2)
        }
    }

    private func stadium(in context: GraphicsContext, phase: Double) {
        // An original night-stadium treatment, not the UEFA logo or starball.
        let halo = Path(ellipseIn: CGRect(x: 25, y: 13, width: 110, height: 90))
        context.fill(halo, with: .radialGradient(Gradient(colors: [blue.opacity(dark ? 0.25 : 0.12), .clear]),
                                               center: CGPoint(x: 80, y: 63), startRadius: 5, endRadius: 57))
        // Quiet stadium light, never a full-screen flash or competition logo.
        for index in 0..<5 {
            let x = CGFloat(28 + index * 26)
            let y: CGFloat = index.isMultiple(of: 2) ? 25 : 16
            let brightness = 0.5 + 0.08 * sin(phase * .pi * 2 + Double(index))
            line([CGPoint(x: x - 2, y: y), CGPoint(x: x + 2, y: y)], in: context, color: blue.opacity(brightness), width: 1.2)
            line([CGPoint(x: x, y: y - 2), CGPoint(x: x, y: y + 2)], in: context, color: blue.opacity(brightness), width: 1.2)
        }
    }

    private func ball(in context: GraphicsContext, style: SportMotionStyle, at center: CGPoint, radius: CGFloat, rotation: Double) {
        var local = context
        local.translateBy(x: center.x, y: center.y)
        local.scaleBy(x: radius / 25, y: radius / 25)
        let disc = Path(ellipseIn: CGRect(x: -25, y: -25, width: 50, height: 50))
        let base: Color
        switch style {
        case .cricket: base = Color(red: 0.72, green: 0.13, blue: 0.12)
        case .basketball: base = Color(red: 0.96, green: 0.39, blue: 0.065)
        case .tennis: base = Color(red: 0.72, green: 0.86, blue: 0.1)
        case .handball: base = Color(red: 0.16, green: 0.67, blue: 0.64)
        default: base = Color(red: 0.91, green: 0.94, blue: 0.98)
        }
        local.fill(disc, with: .color(base))
        var markings = local
        markings.clip(to: disc)
        markings.rotate(by: .degrees(rotation))
        switch style {
        case .football: footballPanels(in: markings)
        case .cricket: cricketSeam(in: markings)
        case .basketball: basketballSeams(in: markings)
        case .baseball: baseballSeams(in: markings)
        case .volleyball: volleyballPanels(in: markings)
        case .handball: handballPanels(in: markings)
        case .tennis:
            for sign: CGFloat in [-1, 1] {
                var curve = Path()
                curve.move(to: CGPoint(x: -25, y: sign * 17))
                curve.addCurve(to: CGPoint(x: 25, y: sign * 17),
                               control1: CGPoint(x: -12, y: sign * 1.7), control2: CGPoint(x: 12, y: sign * 1.7))
                markings.stroke(curve, with: .color(.white.opacity(0.9)), lineWidth: 2)
            }
        default: break
        }
        // Lighting does not rotate with the seams: the ball keeps its volume.
        local.fill(disc, with: .radialGradient(
            Gradient(stops: [.init(color: .white.opacity(0.42), location: 0),
                             .init(color: .clear, location: 0.48),
                             .init(color: .black.opacity(0.48), location: 1)]),
            center: CGPoint(x: -10, y: -12), startRadius: 0, endRadius: 49))
        local.stroke(disc, with: .color(edgeInk), lineWidth: 1.2)
    }

    private func footballPanels(in context: GraphicsContext) {
        let panelInk = isChampionsLeague ? Color(red: 0.05, green: 0.16, blue: 0.35) : Color(red: 0.08, green: 0.11, blue: 0.14)
        func pentagon(_ center: CGPoint, radius: CGFloat, angle: Double) -> Path {
            Path { path in
                for vertex in 0..<5 {
                    let a = angle + Double(vertex) * .pi * 2 / 5
                    let point = CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
                    if vertex == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
            }
        }
        context.fill(pentagon(.zero, radius: 9.5, angle: -.pi / 2), with: .color(panelInk))
        for index in 0..<5 {
            let a = -.pi / 2 + Double(index) * .pi * 2 / 5
            let point = CGPoint(x: cos(a) * 24, y: sin(a) * 24)
            context.fill(pentagon(point, radius: 7.5, angle: a), with: .color(panelInk))
            line([CGPoint(x: cos(a) * 9, y: sin(a) * 9), point], in: context, color: panelInk.opacity(0.45), width: 0.8)
        }
    }

    private func cricketSeam(in context: GraphicsContext) {
        let thread = Color(red: 0.97, green: 0.87, blue: 0.72)
        for side: CGFloat in [-1, 1] {
            var seam = Path()
            seam.move(to: CGPoint(x: side * 2 - 8, y: -27))
            seam.addCurve(to: CGPoint(x: side * 2 + 8, y: 27),
                          control1: CGPoint(x: side * 2 + 11, y: -10),
                          control2: CGPoint(x: side * 2 - 11, y: 10))
            context.stroke(seam, with: .color(thread.opacity(0.9)), lineWidth: 0.8)
            for index in -7...7 {
                let y = CGFloat(index) * 3.1
                let x = 8 * pow(y / 27, 3) + side * 3.2
                line([CGPoint(x: x - 1.2, y: y - 0.55), CGPoint(x: x + 1.2, y: y + 0.55)],
                     in: context, color: thread, width: 0.75)
            }
        }
    }

    private func basketballSeams(in context: GraphicsContext) {
        let seam = Color(red: 0.23, green: 0.1, blue: 0.04)
        line([CGPoint(x: -26, y: 0), CGPoint(x: 26, y: 0)], in: context, color: seam, width: 1.6)
        line([CGPoint(x: 0, y: -26), CGPoint(x: 0, y: 26)], in: context, color: seam, width: 1.6)
        for side: CGFloat in [-1, 1] {
            var path = Path()
            path.move(to: CGPoint(x: side * 19, y: -26))
            path.addCurve(to: CGPoint(x: side * 19, y: 26),
                          control1: CGPoint(x: side * -9, y: -10), control2: CGPoint(x: side * -9, y: 10))
            context.stroke(path, with: .color(seam), lineWidth: 1.5)
        }
    }

    private func baseballSeams(in context: GraphicsContext) {
        for side: CGFloat in [-1, 1] {
            var curve = Path()
            curve.move(to: CGPoint(x: side * 20, y: -26))
            curve.addQuadCurve(to: CGPoint(x: side * 20, y: 26), control: CGPoint(x: side * -5, y: 0))
            context.stroke(curve, with: .color(.red.opacity(0.72)), lineWidth: 0.8)
            for index in -6...6 {
                let y = CGFloat(index) * 3.5
                let x = side * (7.5 + 12.5 * pow(y / 26, 2))
                line([CGPoint(x: x - 1.5, y: y - 1), CGPoint(x: x, y: y + 0.5),
                      CGPoint(x: x + 1.5, y: y - 1)], in: context, color: .red.opacity(0.85), width: 1)
            }
        }
    }

    private func volleyballPanels(in context: GraphicsContext) {
        // Curved alternating panels distinguish a volleyball at small sizes.
        for index in 0..<3 {
            var panel = context
            panel.rotate(by: .degrees(Double(index) * 120))
            var stripe = Path()
            stripe.move(to: CGPoint(x: -3, y: -27))
            stripe.addCurve(to: CGPoint(x: 24, y: 19), control1: CGPoint(x: 19, y: -19), control2: CGPoint(x: -7, y: 10))
            stripe.addLine(to: CGPoint(x: 30, y: 11))
            stripe.addCurve(to: CGPoint(x: 8, y: -27), control1: CGPoint(x: 5, y: 3), control2: CGPoint(x: 25, y: -13))
            stripe.closeSubpath()
            panel.fill(stripe, with: .color(index == 1 ? Color(red: 0.98, green: 0.72, blue: 0.15) : blue))
            panel.stroke(stripe, with: .color(Color.black.opacity(0.2)), lineWidth: 1)
        }
    }

    private func handballPanels(in context: GraphicsContext) {
        let seam = Color(red: 0.03, green: 0.28, blue: 0.3)
        for index in 0..<6 {
            var panel = context
            panel.rotate(by: .degrees(Double(index) * 60))
            var curve = Path()
            curve.move(to: CGPoint(x: 0, y: -26))
            curve.addQuadCurve(to: CGPoint(x: 0, y: 26), control: CGPoint(x: 14, y: 0))
            panel.stroke(curve, with: .color(seam), lineWidth: 1.7)
        }
        context.fill(Path(ellipseIn: CGRect(x: -6, y: -6, width: 12, height: 12)), with: .color(.white.opacity(0.85)))
    }

    private func tableTennis(in context: GraphicsContext, pose: SportMotionPose) {
        // A paddle, net and orange ball; not the lawn-tennis equipment family.
        line([CGPoint(x: 28, y: 101), CGPoint(x: 133, y: 101)], in: context, color: ink, width: 2)
        var net = Path()
        net.addRect(CGRect(x: 101, y: 76, width: 25, height: 24))
        for y in stride(from: 82, through: 94, by: 6) {
            net.move(to: CGPoint(x: 101, y: y)); net.addLine(to: CGPoint(x: 126, y: y))
        }
        for x in stride(from: 107, through: 119, by: 6) {
            net.move(to: CGPoint(x: x, y: 76)); net.addLine(to: CGPoint(x: x, y: 100))
        }
        context.stroke(net, with: .color(ink), lineWidth: 1.3)
        var paddle = context
        paddle.translateBy(x: 46, y: 66)
        paddle.rotate(by: .degrees(-24 + pose.rotation / 3))
        paddle.fill(Path(roundedRect: CGRect(x: -5, y: 15, width: 10, height: 24), cornerRadius: 3),
                    with: .color(Color(red: 0.68, green: 0.44, blue: 0.24)))
        let face = Path(ellipseIn: CGRect(x: -19, y: -23, width: 38, height: 43))
        paddle.fill(face, with: .linearGradient(Gradient(colors: [.red, Color(red: 0.6, green: 0.07, blue: 0.1)]),
                                               startPoint: CGPoint(x: -15, y: -20), endPoint: CGPoint(x: 19, y: 22)))
        paddle.stroke(face, with: .color(edgeInk), lineWidth: 2)
        let center = CGPoint(x: 84 + pose.x, y: 65 - pose.lift)
        let disc = Path(ellipseIn: CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24))
        context.fill(disc, with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.43), .orange]),
                                                center: CGPoint(x: center.x - 4, y: center.y - 4), startRadius: 0, endRadius: 24))
        context.stroke(disc, with: .color(edgeInk), lineWidth: 1.3)
    }

    private func golf(in context: GraphicsContext, pose: SportMotionPose) {
        let green = Path(ellipseIn: CGRect(x: 21, y: 82, width: 120, height: 27))
        context.fill(green, with: .color(Color.green.opacity(dark ? 0.18 : 0.13)))
        context.stroke(green, with: .color(ink), lineWidth: 1.2)
        context.fill(Path(ellipseIn: CGRect(x: 105, y: 88, width: 17, height: 6)), with: .color(Color.black.opacity(0.45)))
        line([CGPoint(x: 113, y: 89), CGPoint(x: 113, y: 26)], in: context, color: edgeInk, width: 2)
        var flag = Path()
        flag.move(to: CGPoint(x: 113, y: 26)); flag.addLine(to: CGPoint(x: 133, y: 33))
        flag.addLine(to: CGPoint(x: 113, y: 43)); flag.closeSubpath()
        context.fill(flag, with: .color(FottyTheme.error))
        let center = CGPoint(x: 69 + pose.x, y: 82)
        let disc = Path(ellipseIn: CGRect(x: center.x - 16, y: center.y - 16, width: 32, height: 32))
        context.fill(disc, with: .radialGradient(Gradient(colors: [.white, Color(white: 0.68)]),
                                                center: CGPoint(x: center.x - 5, y: center.y - 6), startRadius: 0, endRadius: 31))
        var details = context
        details.clip(to: disc)
        details.translateBy(x: center.x, y: center.y)
        details.rotate(by: .degrees(pose.rotation))
        for row in -2...2 {
            for column in -2...2 {
                let x = CGFloat(column * 6 + (row.isMultiple(of: 2) ? 0 : 3))
                details.fill(Path(ellipseIn: CGRect(x: x - 1, y: CGFloat(row * 6) - 1, width: 2, height: 2)),
                             with: .color(.black.opacity(0.18)))
            }
        }
        context.stroke(disc, with: .color(edgeInk), lineWidth: 1.4)
    }

    private func darts(in context: GraphicsContext, pose: SportMotionPose) {
        let center = CGPoint(x: 69, y: 64)
        let outer = Path(ellipseIn: CGRect(x: 33, y: 28, width: 72, height: 72))
        context.fill(outer, with: .color(Color(white: 0.16)))
        for index in 0..<12 {
            let start = Double(index) * .pi / 6
            let end = start + .pi / 6
            var wedge = Path()
            wedge.move(to: center)
            wedge.addArc(center: center, radius: 32, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
            wedge.closeSubpath()
            context.fill(wedge, with: .color(index.isMultiple(of: 2) ? Color(white: 0.88) : Color(white: 0.22)))
        }
        for radius: CGFloat in [19, 30] {
            context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                           with: .color(Color(red: 0.16, green: 0.58, blue: 0.41)), lineWidth: 3)
        }
        context.fill(Path(ellipseIn: CGRect(x: 65, y: 60, width: 8, height: 8)), with: .color(.red))
        context.stroke(outer, with: .color(edgeInk), lineWidth: 1.5)
        var dart = context
        dart.translateBy(x: 116 + pose.x, y: 39 - pose.lift)
        dart.rotate(by: .degrees(-32 + pose.rotation))
        line([CGPoint(x: -18, y: 0), CGPoint(x: 16, y: 0)], in: dart, color: dark ? .white : Color(white: 0.3), width: 2.2)
        var flight = Path()
        flight.move(to: CGPoint(x: 8, y: 0)); flight.addLine(to: CGPoint(x: 15, y: -9))
        flight.addLine(to: CGPoint(x: 25, y: -9)); flight.addLine(to: CGPoint(x: 18, y: 0))
        flight.addLine(to: CGPoint(x: 25, y: 9)); flight.addLine(to: CGPoint(x: 15, y: 9)); flight.closeSubpath()
        dart.fill(flight, with: .color(profile.accent))
        line([CGPoint(x: -9, y: -2), CGPoint(x: 5, y: -2)], in: dart, color: edgeInk, width: 2)
    }

    private func lacrosse(in context: GraphicsContext, pose: SportMotionPose) {
        ground(in: context, style: .lacrosse)
        var stick = context
        stick.translateBy(x: 82, y: 70)
        stick.rotate(by: .degrees(-34 + pose.rotation))
        line([CGPoint(x: 0, y: -9), CGPoint(x: 0, y: 39)], in: stick, color: dark ? .white : Color(white: 0.4), width: 5)
        var head = Path()
        head.move(to: CGPoint(x: -17, y: -33)); head.addQuadCurve(to: CGPoint(x: 17, y: -33), control: CGPoint(x: 0, y: -42))
        head.addQuadCurve(to: CGPoint(x: 0, y: -4), control: CGPoint(x: 16, y: -11))
        head.addQuadCurve(to: CGPoint(x: -17, y: -33), control: CGPoint(x: -16, y: -11)); head.closeSubpath()
        stick.stroke(head, with: .color(profile.accent), lineWidth: 3.2)
        var mesh = stick
        mesh.clip(to: head)
        for offset in stride(from: -30, through: 30, by: 7) {
            line([CGPoint(x: offset - 18, y: -42), CGPoint(x: offset + 18, y: 0)], in: mesh, color: ink, width: 1.4)
            line([CGPoint(x: offset + 18, y: -42), CGPoint(x: offset - 18, y: 0)], in: mesh, color: ink, width: 1.4)
        }
        let center = CGPoint(x: 107 + pose.x, y: 43 - pose.lift)
        let disc = Path(ellipseIn: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20))
        context.fill(disc, with: .radialGradient(Gradient(colors: [.white, Color(white: 0.7)]),
                                                center: CGPoint(x: center.x - 3, y: center.y - 3), startRadius: 0, endRadius: 21))
        context.stroke(disc, with: .color(edgeInk), lineWidth: 1.5)
    }

    private func cycling(in context: GraphicsContext, pose: SportMotionPose) {
        var bike = context
        bike.translateBy(x: 0, y: -pose.lift)
        for center in [CGPoint(x: 43, y: 83), CGPoint(x: 115, y: 83)] {
            let wheel = Path(ellipseIn: CGRect(x: center.x - 21, y: center.y - 21, width: 42, height: 42))
            bike.stroke(wheel, with: .color(edgeInk), lineWidth: 3.2)
            var spokes = bike
            spokes.translateBy(x: center.x, y: center.y)
            spokes.rotate(by: .degrees(pose.rotation))
            for index in 0..<3 {
                var pair = spokes
                pair.rotate(by: .degrees(Double(index) * 60))
                line([CGPoint(x: -19, y: 0), CGPoint(x: 19, y: 0)], in: pair, color: ink, width: 1.6)
            }
        }
        let frame = profile.accent
        line([CGPoint(x: 43, y: 83), CGPoint(x: 66, y: 51), CGPoint(x: 82, y: 83), CGPoint(x: 43, y: 83)], in: bike, color: frame, width: 3.6)
        line([CGPoint(x: 66, y: 51), CGPoint(x: 102, y: 51), CGPoint(x: 82, y: 83)], in: bike, color: frame, width: 3.6)
        line([CGPoint(x: 98, y: 43), CGPoint(x: 115, y: 83)], in: bike, color: frame, width: 3.2)
        line([CGPoint(x: 61, y: 40), CGPoint(x: 70, y: 60)], in: bike, color: frame, width: 3)
        line([CGPoint(x: 55, y: 40), CGPoint(x: 69, y: 40)], in: bike, color: edgeInk, width: 4)
        line([CGPoint(x: 98, y: 43), CGPoint(x: 105, y: 35), CGPoint(x: 117, y: 35)], in: bike, color: edgeInk, width: 3)
        var crank = bike
        crank.translateBy(x: 82, y: 83)
        crank.rotate(by: .degrees(-pose.rotation))
        line([CGPoint(x: -6, y: 0), CGPoint(x: 6, y: 0)], in: crank, color: edgeInk, width: 2)
        ground(in: context, style: .cycling)
    }

    private func ovalBall(in context: GraphicsContext, at center: CGPoint, pose: SportMotionPose) {
        var local = context
        local.translateBy(x: center.x, y: center.y)
        local.rotate(by: .degrees(pose.rotation - 20))
        let oval = Path(ellipseIn: CGRect(x: -33, y: -19, width: 66, height: 38))
        let rugby = profile.style == .rugby
        let base = rugby ? Color(red: 0.9, green: 0.94, blue: 0.96) : Color(red: 0.48, green: 0.22, blue: 0.09)
        local.fill(oval, with: .color(base))
        var details = local
        details.clip(to: oval)
        let spin = CGFloat(sin(pose.phase * .pi * 4))
        for side: CGFloat in [-1, 1] {
            let stripe = Path(CGRect(x: side * 23 - 3, y: -25, width: rugby ? 10 : 5, height: 50))
            details.fill(stripe, with: .color(rugby ? .teal : .white.opacity(0.85)))
        }
        if rugby {
            var panel = Path()
            panel.move(to: CGPoint(x: -34, y: 5 * spin))
            panel.addQuadCurve(to: CGPoint(x: 34, y: 5 * spin), control: CGPoint(x: 0, y: 21))
            details.stroke(panel, with: .color(.teal.opacity(0.8)), lineWidth: 3)
        } else {
            line([CGPoint(x: -11, y: spin * 6), CGPoint(x: 11, y: spin * 6)], in: details, color: .white.opacity(0.9), width: 1.7)
            for x in stride(from: -8, through: 8, by: 4) {
                line([CGPoint(x: CGFloat(x), y: spin * 6 - 3), CGPoint(x: CGFloat(x), y: spin * 6 + 3)],
                     in: details, color: .white, width: 1.4)
            }
        }
        local.fill(oval, with: .linearGradient(Gradient(colors: [.white.opacity(0.3), .clear, .black.opacity(0.5)]),
                                             startPoint: CGPoint(x: 0, y: -19), endPoint: CGPoint(x: 0, y: 19)))
        local.stroke(oval, with: .color(edgeInk), lineWidth: 1.3)
    }

    private func puck(in context: GraphicsContext, at center: CGPoint) {
        var local = context
        local.translateBy(x: center.x, y: center.y)
        let body = Path(roundedRect: CGRect(x: -28, y: -3, width: 56, height: 20), cornerRadius: 8)
        local.fill(body, with: .linearGradient(Gradient(colors: [.gray, .black]),
                                             startPoint: CGPoint(x: 0, y: -3), endPoint: CGPoint(x: 0, y: 17)))
        let top = Path(ellipseIn: CGRect(x: -28, y: -13, width: 56, height: 23))
        local.fill(top, with: .linearGradient(Gradient(colors: [Color(white: 0.34), Color(white: 0.1)]),
                                            startPoint: CGPoint(x: -15, y: -13), endPoint: CGPoint(x: 18, y: 10)))
        local.stroke(top, with: .color(edgeInk), lineWidth: 1.4)
        for y: CGFloat in [9, 12] {
            line([CGPoint(x: -19, y: y), CGPoint(x: 19, y: y)], in: local, color: .white.opacity(0.12), width: 0.6)
        }
        // Trail stays inside the logical canvas even at the left travel limit.
        line([CGPoint(x: -46, y: 12), CGPoint(x: -35, y: 12)], in: local, color: blue.opacity(0.4), width: 1.5)
    }

    private func racing(in context: GraphicsContext, pose: SportMotionPose) {
        let track = Path(ellipseIn: CGRect(x: 29, y: 32, width: 102, height: 58))
        context.stroke(track, with: .color(ink), lineWidth: 9)
        context.stroke(track, with: .color(edgeInk), style: StrokeStyle(lineWidth: 1.1, dash: [3, 5]))
        for row in 0..<3 {
            for col in 0..<2 {
                context.fill(Path(CGRect(x: 76 + col * 4, y: 86 + row * 4, width: 4, height: 4)),
                             with: .color((row + col).isMultiple(of: 2) ? .white : .black))
            }
        }
        let angle = pose.phase * .pi * 2 + 0.12 * sin(pose.phase * .pi * 2)
        var car = context
        car.translateBy(x: 80 + cos(angle) * 51, y: 61 + sin(angle) * 29)
        car.rotate(by: .radians(atan2(sin(angle) * 51, cos(angle) * 29) + .pi))
        for x: CGFloat in [-9, 6] {
            for y: CGFloat in [-9, 5] {
                car.fill(Path(roundedRect: CGRect(x: x, y: y, width: 4, height: 7), cornerRadius: 1),
                         with: .color(Color(white: 0.12)))
            }
        }
        car.fill(Path(roundedRect: CGRect(x: -4, y: -14, width: 8, height: 27), cornerRadius: 3),
                 with: .linearGradient(Gradient(colors: [.orange, .red]), startPoint: CGPoint(x: -4, y: 0), endPoint: CGPoint(x: 4, y: 0)))
        car.fill(Path(CGRect(x: -10, y: -12, width: 20, height: 3)), with: .color(.orange))
        car.fill(Path(CGRect(x: -9, y: 10, width: 18, height: 3)), with: .color(.red))
        line([CGPoint(x: 0, y: -12), CGPoint(x: 0, y: -5)], in: car, color: .white.opacity(0.85), width: 1.6)
        car.fill(Path(ellipseIn: CGRect(x: -2.5, y: -2, width: 5, height: 8)), with: .color(.black.opacity(0.8)))
    }

    private func gloves(in context: GraphicsContext, pose: SportMotionPose) {
        ground(in: context, style: .combat)
        for side: CGFloat in [-1, 1] {
            context.fill(Path(ellipseIn: CGRect(x: 80 + side * 34 - 19, y: 103, width: 38, height: 5)),
                         with: .color(.black.opacity(dark ? 0.4 : 0.13)))
            var glove = context
            glove.translateBy(x: 80 + side * (34 - pose.x), y: 71 - pose.lift)
            glove.scaleBy(x: -side, y: 1)
            glove.rotate(by: .degrees(-12 + Double(side) * pose.rotation))
            var shape = Path()
            shape.move(to: CGPoint(x: -18, y: 9))
            shape.addCurve(to: CGPoint(x: -17, y: -23), control1: CGPoint(x: -25, y: -8), control2: CGPoint(x: -24, y: -20))
            shape.addCurve(to: CGPoint(x: 14, y: -19), control1: CGPoint(x: -9, y: -29), control2: CGPoint(x: 12, y: -29))
            shape.addQuadCurve(to: CGPoint(x: 18, y: 1), control: CGPoint(x: 22, y: -11))
            shape.addQuadCurve(to: CGPoint(x: 8, y: 15), control: CGPoint(x: 24, y: 15))
            shape.addLine(to: CGPoint(x: 7, y: 26)); shape.addLine(to: CGPoint(x: -14, y: 26))
            shape.closeSubpath()
            glove.fill(shape, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.28, blue: 0.23), Color(red: 0.49, green: 0.035, blue: 0.08)]),
                                                    startPoint: CGPoint(x: -15, y: -22), endPoint: CGPoint(x: 20, y: 24)))
            glove.stroke(shape, with: .color(edgeInk), lineWidth: 1.2)
            glove.fill(Path(roundedRect: CGRect(x: -16, y: 16, width: 25, height: 10), cornerRadius: 2),
                       with: .color(Color(red: 0.14, green: 0.17, blue: 0.23)))
            line([CGPoint(x: -14, y: -15), CGPoint(x: 8, y: -15)], in: glove, color: .white.opacity(0.24), width: 2)
            line([CGPoint(x: -9, y: 22), CGPoint(x: 1, y: 22)], in: glove, color: .white.opacity(0.6), width: 1.8)
        }
    }
}

/// Compatibility for football-only screens while callers migrate to the
/// sport-aware loader.
struct FootballLoadingView: View {
    var size: CGFloat = 40
    var label: String = "Loading football…"

    var body: some View {
        SportLoadingView(category: "football", size: size, label: label)
    }
}

// MARK: - Confirmed-event celebration

/// One-shot celebration. Callers must only present it for a verified scoring
/// event; timing estimates alone are never enough to imply a goal or wicket.
struct SportCelebrationView: View {
    let category: String
    @State private var startedAt = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var profile: SportMotionProfile { .profile(for: category) }

    var body: some View {
        if reduceMotion {
            Image(systemName: profile.symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(profile.accent)
                .accessibilityHidden(true)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let elapsed = max(0, min(1.4, timeline.date.timeIntervalSince(startedAt)))
                Canvas { context, canvasSize in
                    for index in 0..<28 {
                        let fraction = Double(index) / 28.0
                        let angle = fraction * .pi * 2
                        let speed = 42.0 + Double(index % 7) * 8.0
                        let distance = speed * elapsed
                        let x = canvasSize.width / 2 + CGFloat(cos(angle) * distance)
                        let y = canvasSize.height / 2 + CGFloat(sin(angle) * distance + elapsed * elapsed * 28)
                        context.opacity = max(0, 1 - elapsed / 1.4)
                        context.fill(
                            Path(ellipseIn: CGRect(x: x, y: y, width: 5, height: 5)),
                            with: .color(index.isMultiple(of: 3) ? profile.accent : FottyTheme.textPrimary)
                        )
                    }
                }
            }
            .onAppear { startedAt = Date() }
            .accessibilityHidden(true)
        }
    }
}

struct GoalCelebrationView: View {
    var body: some View { SportCelebrationView(category: "football") }
}

// MARK: - Pitch background pattern

struct PitchPattern: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                FottyTheme.background

                VStack(spacing: 0) {
                    ForEach(0..<10) { index in
                        Rectangle()
                            .fill(index.isMultiple(of: 2) ? FottyTheme.textPrimary.opacity(0.02) : Color.clear)
                            .frame(height: geo.size.height / 10)
                    }
                }

                Group {
                    Rectangle()
                        .fill(FottyTheme.textPrimary.opacity(0.03))
                        .frame(height: 1)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)

                    Circle()
                        .stroke(FottyTheme.textPrimary.opacity(0.03), lineWidth: 1)
                        .frame(width: geo.size.width * 0.3)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    func pitchBackground() -> some View {
        background(PitchPattern())
    }
}

#Preview {
    ZStack {
        PitchPattern()
        SportLoadingView(category: "cricket", size: 54)
    }
    .preferredColorScheme(.dark)
}
