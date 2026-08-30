import SwiftUI

// MARK: - Official Premier League FPL Club Shirt Image Loader

public struct FPLOfficialShirtImageView: View {
    let teamCode: Int
    let isGoalkeeper: Bool
    let size: CGFloat
    
    public init(teamCode: Int, isGoalkeeper: Bool = false, size: CGFloat = 52) {
        self.teamCode = teamCode
        self.isGoalkeeper = isGoalkeeper
        self.size = size
    }
    
    private var officialShirtURL: URL? {
        let suffix = isGoalkeeper ? "_1-110.png" : "-110.png"
        return URL(string: "https://fantasy.premierleague.com/dist/img/shirts/standard/shirt_\(teamCode)\(suffix)")
    }
    
    public var body: some View {
        if usesUIFixture {
            fallbackShirt
                .frame(width: size, height: size * 1.1)
        } else {
        AsyncImage(url: officialShirtURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size * 1.1)
                    .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 2)
            case .failure:
                fallbackShirt
            case .empty:
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: size, height: size * 1.1)
            @unknown default:
                fallbackShirt
            }
        }
        .frame(width: size, height: size * 1.1)
        }
    }

    private var usesUIFixture: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["FOTTY_FPL_UI_TESTING"] == "1"
#else
        false
#endif
    }
    
    private var fallbackShirt: some View {
        Image(systemName: "tshirt.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size * 0.8, height: size * 0.8)
            .foregroundStyle(isGoalkeeper ? Color.green : FottyTheme.accentText)
            .shadow(color: .black.opacity(0.4), radius: 2)
    }
}

// MARK: - Main FPL Squad Pitch View

public struct FPLSquadPitchView: View {
    let initialPicks: [FPLPick]
    let scores: [PlayerScore]
    let teams: [FPLTeam]
    let fixtures: [FPLFixture]
    let projectionStartGameweek: Int
    let isCustomDraft: Bool
    let showsDraftBanner: Bool
    let onUpdateSquad: (([FPLPick]) -> Bool)?
    let draftError: (() -> String?)?
    let onResetTemplate: (() -> Void)?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @State private var currentPicks: [FPLPick]
    @State private var selectedPickID: Int? = nil
    @State private var playerForActionSheet: FPLPick? = nil
    @State private var activePickerContext: PlayerPickerContext? = nil
    @State private var playerForDetailSheet: PlayerScore? = nil
    
    public init(
        picks: [FPLPick],
        scores: [PlayerScore],
        teams: [FPLTeam],
        fixtures: [FPLFixture] = [],
        projectionStartGameweek: Int = 1,
        isCustomDraft: Bool = false,
        showsDraftBanner: Bool = true,
        onUpdateSquad: (([FPLPick]) -> Bool)? = nil,
        draftError: (() -> String?)? = nil,
        onResetTemplate: (() -> Void)? = nil
    ) {
        self.initialPicks = picks
        self.scores = scores
        self.teams = teams
        self.fixtures = fixtures
        self.projectionStartGameweek = projectionStartGameweek
        self.isCustomDraft = isCustomDraft
        self.showsDraftBanner = showsDraftBanner
        self.onUpdateSquad = onUpdateSquad
        self.draftError = draftError
        self.onResetTemplate = onResetTemplate
        _currentPicks = State(initialValue: picks)
    }
    
    private var startingPicks: [FPLPick] {
        currentPicks.filter { $0.position <= 11 }
    }
    
    private var benchPicks: [FPLPick] {
        currentPicks.filter { $0.position > 11 }.sorted(by: { $0.position < $1.position })
    }
    
    public enum PitchDisplayChipMode: String, CaseIterable, Identifiable, Sendable {
        case fixture = "Next fixture"
        case projection = "Modeled points"
        case minutes = "Expected minutes"
        case form = "Official form"
        case ownership = "Ownership"
        case price = "Price movement"
        case livePoints = "Live points"
        
        public var id: String { rawValue }

        var compactTitle: String {
            switch self {
            case .fixture: return "Fixture"
            case .projection: return "xPoints"
            case .minutes: return "Minutes"
            case .form: return "Form"
            case .ownership: return "Owned"
            case .price: return "Price"
            case .livePoints: return "Live"
            }
        }
    }
    
    @AppStorage("fotty.fpl.pitchDisplayChip") private var pitchDisplayChip: PitchDisplayChipMode = .fixture
    
    private var totalCostMillion: Double {
        let totalTenths = currentPicks.reduce(0) { sum, pick in
            sum + (getScore(for: pick.element)?.player.nowCost ?? 0)
        }
        return Double(totalTenths) / 10.0
    }
    
    private var remainingBankMillion: Double {
        max(0.0, 100.0 - totalCostMillion)
    }
    
    private var formationString: String {
        let defCount = filterStartingByPosition(2).count
        let midCount = filterStartingByPosition(3).count
        let fwdCount = filterStartingByPosition(4).count
        return "\(defCount)-\(midCount)-\(fwdCount)"
    }
    
    private var hasChanges: Bool {
        currentPicks != initialPicks
    }

    private var isCompactWidth: Bool { horizontalSizeClass == .compact }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var nameplateHeight: CGFloat = 30
    @ScaledMetric(relativeTo: .caption2) private var fixturePlateHeight: CGFloat = 32
    private var playerCardWidth: CGFloat { isCompactWidth ? 52 : 76 }
    private var playerNameplateWidth: CGFloat { playerCardWidth - 2 }
    private var playerShirtSize: CGFloat { isCompactWidth ? 34 : 52 }
    private var playerNameplateHeight: CGFloat { nameplateHeight }
    private var playerSubplateHeight: CGFloat { fixturePlateHeight }
    
    private func getScore(for element: Int) -> PlayerScore? {
        scores.first(where: { $0.player.id == element })
    }
    
    private func filterStartingByPosition(_ type: Int) -> [FPLPick] {
        startingPicks.filter { pick in
            getScore(for: pick.element)?.player.elementType == type
        }
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // Local draft status banner
            if isCustomDraft && showsDraftBanner {
                HStack(spacing: 10) {
                    Image(systemName: "pencil.and.ruler.fill")
                        .font(.fottyScaled(size: 14, weight: .bold))
                        .foregroundStyle(FottyTheme.accentText)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Local Draft Squad")
                            .font(.fottyScaled(size: 12, weight: .bold))
                            .foregroundStyle(FottyTheme.textPrimary)
                        
                        Text("Tap a player to see stats, replace them or choose your captain. Changes stay in Fotty.")
                            .font(.fottyScaled(size: 10, weight: .regular))
                            .foregroundStyle(FottyTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    if let onReset = onResetTemplate {
                        Button {
                            HapticManager.impact(.light)
                            onReset()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "wand.and.stars")
                                Text("Suggested Draft")
                            }
                            .font(.fottyScaled(size: 10, weight: .bold))
                            .foregroundStyle(FottyTheme.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(FottyTheme.surfaceElevated)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(FottyTheme.accent.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(FottyTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(FottyTheme.accent.opacity(0.3), lineWidth: 1)
                )
            }
            
            // A single compact toolbar preserves the useful pitch height on
            // narrow iPhones (including Display Zoom) without scaling the
            // whole interface or shrinking its tap targets.
            if isCompactWidth {
                squadCompactToolbar
                    .padding(.horizontal, 2)
            } else {
                HStack(spacing: 12) {
                    squadSummaryStrip
                    Spacer(minLength: 10)
                    squadActionStrip
                }
                .padding(.horizontal, 6)
            }
            
            if dynamicTypeSize >= .xxLarge {
                readableSquadList
            } else {
            // Broadcast Official FPL Pitch
            ZStack {
                // Pitch Grass Background with Alternating Lawn Stripes
                GeometryReader { geo in
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(red: 0.04, green: 0.28, blue: 0.14),
                                Color(red: 0.02, green: 0.20, blue: 0.09)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        
                        VStack(spacing: 0) {
                            ForEach(0..<9, id: \.self) { stripe in
                                Rectangle()
                                    .fill(stripe % 2 == 0 ? Color.white.opacity(0.03) : Color.black.opacity(0.05))
                                    .frame(height: geo.size.height / 9)
                            }
                        }
                        
                        RadialGradient(
                            colors: [Color.white.opacity(0.10), Color.clear],
                            center: .top,
                            startRadius: 20,
                            endRadius: geo.size.width * 0.8
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1.5)
                )
                
                // Field Chalk Markings
                VStack {
                    ZStack {
                        Rectangle()
                            .stroke(Color.white.opacity(0.20), lineWidth: 1.5)
                            .frame(width: 170, height: 48)
                        Circle()
                            .trim(from: 0.0, to: 0.5)
                            .stroke(Color.white.opacity(0.20), lineWidth: 1.5)
                            .frame(width: 60, height: 60)
                            .offset(y: 24)
                    }
                    
                    Spacer()
                    
                    ZStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.20))
                            .frame(height: 1.5)
                        
                        Circle()
                            .stroke(Color.white.opacity(0.20), lineWidth: 1.5)
                            .frame(width: 90, height: 90)
                        
                        Circle()
                            .fill(Color.white.opacity(0.30))
                            .frame(width: 6, height: 6)
                    }
                    
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .trim(from: 0.5, to: 1.0)
                            .stroke(Color.white.opacity(0.20), lineWidth: 1.5)
                            .frame(width: 60, height: 60)
                            .offset(y: -24)
                        Rectangle()
                            .stroke(Color.white.opacity(0.20), lineWidth: 1.5)
                            .frame(width: 170, height: 48)
                    }
                }
                .padding(.vertical, 8)
                
                // Formation Rows: GKP -> DEF -> MID -> FWD
                VStack(spacing: isCompactWidth ? 12 : 24) {
                    // Goalkeeper
                    HStack(spacing: isCompactWidth ? 4 : 16) {
                        ForEach(filterStartingByPosition(1)) { pick in
                            officialFPLPlayerCard(for: pick)
                        }
                    }
                    
                    // Defenders
                    HStack(spacing: isCompactWidth ? 3 : 14) {
                        ForEach(filterStartingByPosition(2)) { pick in
                            officialFPLPlayerCard(for: pick)
                        }
                    }
                    
                    // Midfielders
                    HStack(spacing: isCompactWidth ? 3 : 12) {
                        ForEach(filterStartingByPosition(3)) { pick in
                            officialFPLPlayerCard(for: pick)
                        }
                    }
                    
                    // Forwards
                    HStack(spacing: isCompactWidth ? 6 : 20) {
                        ForEach(filterStartingByPosition(4)) { pick in
                            officialFPLPlayerCard(for: pick)
                        }
                    }
                }
                .padding(.vertical, isCompactWidth ? 14 : 24)
                .padding(.horizontal, isCompactWidth ? 5 : 8)
            }
            .frame(minHeight: isCompactWidth ? 410 : 500)
            // Grass and shirt artwork is a dark island, not a forced-dark app/sheet.
            .environment(\.colorScheme, .dark)
            
            // Stadium Dugout / Bench Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "person.2.fill")
                        .font(.fottyScaled(size: 11, weight: .bold))
                        .foregroundStyle(FottyTheme.accentText)
                    
                    Text("Bench · substitution order")
                        .font(FottyTheme.typeCaption)
                        .foregroundStyle(FottyTheme.textSecondary)
                    
                    Spacer()
                    
                    Text(isCompactWidth ? "Tap to manage" : "Tap player to swap or replace")
                        .font(.fottyScaled(size: 10, weight: .medium))
                        .foregroundStyle(FottyTheme.textTertiary)
                }
                .padding(.horizontal, 4)
                
                HStack(spacing: isCompactWidth ? 8 : 16) {
                    ForEach(Array(benchPicks.enumerated()), id: \.element.id) { index, pick in
                        VStack(spacing: 4) {
                            Text(index == 0 ? "GK" : "Sub \(index)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(FottyTheme.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(FottyTheme.surfaceElevated)
                                .clipShape(Capsule())
                            
                            officialFPLPlayerCard(for: pick, isBench: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(14)
            .background(FottyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(FottyTheme.border, lineWidth: 1)
            )
            }
        }
        .onChange(of: initialPicks) { _, newPicks in
            currentPicks = newPicks
        }
        .confirmationDialog(
            "Player Actions",
            isPresented: Binding(
                get: { playerForActionSheet != nil },
                set: { if !$0 { playerForActionSheet = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pick = playerForActionSheet, let score = getScore(for: pick.element) {
                Button("View stats and fixtures") {
                    playerForDetailSheet = score
                    playerForActionSheet = nil
                }
                
                Button("🔍 Replace \(score.player.webName) (Search EPL)") {
                    activePickerContext = PlayerPickerContext(position: pick.position, elementType: score.player.elementType, currentElementId: pick.element)
                    playerForActionSheet = nil
                }
                
                if !pick.isCaptain {
                    Button("👑 Make Captain (C)") {
                        setCaptain(elementId: pick.element)
                        playerForActionSheet = nil
                    }
                }
                
                if !pick.isViceCaptain {
                    Button("⭐ Make Vice-Captain (V)") {
                        setViceCaptain(elementId: pick.element)
                        playerForActionSheet = nil
                    }
                }
                
                Button("⇄ Swap Slot with Another Player") {
                    selectedPickID = pick.element
                    playerForActionSheet = nil
                }
                
                Button("Cancel", role: .cancel) {
                    playerForActionSheet = nil
                }
            }
        } message: {
            if let pick = playerForActionSheet, let score = getScore(for: pick.element) {
                let rating = Int(score.compositeScore.rounded())
                Text("\(score.player.webName) • \(score.team.name) • \(score.player.formattedCost) (Fotty rating: \(rating)/100)")
            }
        }
        .sheet(item: $playerForDetailSheet) { score in
            FPLPlayerDetailSheet(
                score: score,
                onMakeCaptain: {
                    setCaptain(elementId: score.player.id)
                },
                onMakeViceCaptain: {
                    setViceCaptain(elementId: score.player.id)
                },
                onReplace: {
                    if let pick = currentPicks.first(where: { $0.element == score.player.id }) {
                        activePickerContext = PlayerPickerContext(position: pick.position, elementType: score.player.elementType, currentElementId: pick.element)
                    }
                }
            )
        }
        .sheet(item: $activePickerContext) { ctx in
            FPLPlayerPickerSheet(
                positionType: ctx.elementType,
                currentElementId: ctx.currentElementId,
                scores: scores,
                teams: teams
            ) { newScore in
                replacePlayerInSquad(oldElementId: ctx.currentElementId, newElementId: newScore.player.id)
                    ? nil : (draftError?() ?? "This change does not meet the squad rules. Choose another player.")
            }
        }
    }

    private var squadSummaryStrip: some View {
        HStack(spacing: 8) {
            Text("FORMATION")
                .font(.fottyScaled(size: 9, weight: .black))
                .foregroundStyle(FottyTheme.textTertiary)
            Text(formationString)
                .font(.fottyScaled(size: 12, weight: .black))
                .foregroundStyle(FottyTheme.accentText)
                .padding(.horizontal, 8)
                .frame(minHeight: 28)
                .background(FottyTheme.accent.opacity(0.18))
                .clipShape(Capsule())
            Spacer(minLength: 4)
            Text("Cost £\(String(format: "%.1f", totalCostMillion))m")
                .foregroundStyle(totalCostMillion <= 100 ? FottyTheme.success : FottyTheme.error)
            Text("•")
                .foregroundStyle(FottyTheme.textTertiary)
            Text("Bank £\(String(format: "%.1f", remainingBankMillion))m")
                .foregroundStyle(FottyTheme.accentText)
        }
        .font(.fottyScaled(size: 11, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private var squadCompactToolbar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Text(formationString)
                    .font(.fottyScaled(size: 10, weight: .black))
                    .foregroundStyle(FottyTheme.accentText)
                    .padding(.horizontal, 7)
                    .frame(minHeight: 38)
                    .background(FottyTheme.accent.opacity(0.18))
                    .clipShape(Capsule())

                Text("£\(String(format: "%.1f", totalCostMillion))m")
                    .foregroundStyle(totalCostMillion <= 100 ? FottyTheme.success : FottyTheme.error)
                Text("•")
                    .foregroundStyle(FottyTheme.textTertiary)
                Text("£\(String(format: "%.1f", remainingBankMillion))m bank")
                    .foregroundStyle(FottyTheme.accentText)
            }
            .font(.fottyScaled(size: 9, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Formation \(formationString), squad cost £\(String(format: "%.1f", totalCostMillion)) million, bank £\(String(format: "%.1f", remainingBankMillion)) million"
            )

            Spacer(minLength: 0)

            Button {
                HapticManager.impact(.heavy)
                autoOptimizeStartingXI()
            } label: {
                Label("Best XI", systemImage: "wand.and.stars")
                    .font(.fottyScaled(size: 9, weight: .bold))
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
                    .background(FottyTheme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Optimizes the starting eleven from the current squad")

            Menu {
                ForEach(PitchDisplayChipMode.allCases) { mode in
                    Button {
                        HapticManager.impact(.light)
                        pitchDisplayChip = mode
                    } label: {
                        HStack {
                            Text(mode.rawValue)
                            if pitchDisplayChip == mode { Image(systemName: "checkmark") }
                        }
                    }
                }

                if hasChanges {
                    Divider()
                    Button("Reset squad changes", systemImage: "arrow.uturn.backward") {
                        resetSquadChanges()
                    }
                }
            } label: {
                Label(pitchDisplayChip.compactTitle, systemImage: "slider.horizontal.3")
                    .font(.fottyScaled(size: 9, weight: .bold))
                    .foregroundStyle(FottyTheme.accentText)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
                    .background(FottyTheme.surfaceElevated)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Squad decision lens, \(pitchDisplayChip.rawValue)")
        }
    }

    private var squadActionStrip: some View {
        HStack(spacing: 8) {
            Button {
                HapticManager.impact(.heavy)
                autoOptimizeStartingXI()
            } label: {
                Label("Optimize XI", systemImage: "wand.and.stars")
                    .font(.fottyScaled(size: 10, weight: .bold))
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(FottyTheme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(PitchDisplayChipMode.allCases) { mode in
                    Button {
                        HapticManager.impact(.light)
                        pitchDisplayChip = mode
                    } label: {
                        HStack {
                            Text(mode.rawValue)
                            if pitchDisplayChip == mode { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Label(pitchDisplayChip.rawValue, systemImage: "slider.horizontal.3")
                    .font(.fottyScaled(size: 10, weight: .bold))
                    .foregroundStyle(FottyTheme.accentText)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(FottyTheme.surfaceElevated)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Squad decision lens, \(pitchDisplayChip.rawValue)")

            if hasChanges {
                Button {
                    resetSquadChanges()
                } label: {
                    Label("Reset", systemImage: "arrow.uturn.backward")
                        .font(.fottyScaled(size: 10, weight: .bold))
                        .foregroundStyle(FottyTheme.accentText)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .background(FottyTheme.surfaceElevated)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : nil, alignment: .trailing)
    }

    private func resetSquadChanges() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            currentPicks = initialPicks
            selectedPickID = nil
        }
    }
    
    // MARK: - Official FPL App Player Card
    
    @ViewBuilder
    private func officialFPLPlayerCard(for pick: FPLPick, isBench: Bool = false) -> some View {
        if let score = getScore(for: pick.element) {
            let isSelected = selectedPickID == pick.element
            let isGK = score.player.elementType == 1
            let teamCode = score.team.code
            
            Button(action: {
                handlePlayerTap(pick)
            }) {
                VStack(spacing: 2) {
                    // Official Fantasy Premier League CDN Club Shirt Image
                    ZStack(alignment: .topTrailing) {
                        // Ambient Selection Pulse
                        if isSelected {
                            Circle()
                                .fill(FottyTheme.accent.opacity(0.45))
                                .frame(
                                    width: isCompactWidth ? 46 : 60,
                                    height: isCompactWidth ? 46 : 60
                                )
                                .blur(radius: 4)
                        }
                        
                        // Official Premier League Server Shirt
                        FPLOfficialShirtImageView(
                            teamCode: teamCode,
                            isGoalkeeper: isGK,
                            size: playerShirtSize
                        )
                        .scaleEffect(isSelected ? 1.15 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
                        
                        // Season goals are not a live goal event; don't badge them as one.
                        
                        // Official FPL Captain (C) / Vice (V) Badge
                        if pick.isCaptain {
                            Text("C")
                                .font(.fottyScaled(size: 10, weight: .black))
                                .foregroundStyle(Color.black)
                                .frame(width: 18, height: 18)
                                .background(
                                    LinearGradient(colors: [Color(red: 1.0, green: 0.85, blue: 0.0), Color(red: 1.0, green: 0.65, blue: 0.0)], startPoint: .top, endPoint: .bottom)
                                )
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                .shadow(color: .black.opacity(0.6), radius: 2)
                                .offset(x: 4, y: -2)
                        } else if pick.isViceCaptain {
                            Text("V")
                                .font(.fottyScaled(size: 10, weight: .black))
                                .foregroundStyle(Color.white)
                                .frame(width: 18, height: 18)
                                .background(Color(red: 0.2, green: 0.2, blue: 0.25))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
                                .shadow(color: .black.opacity(0.6), radius: 2)
                                .offset(x: 4, y: -2)
                        }
                    }
                    
                    // Official FPL Style Card 3-Tier Nameplate, Subplate & Opponent Fixture
                    VStack(spacing: 0) {
                        // 1. Web Name
                        Text(score.player.webName)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(isSelected ? FottyTheme.textOnAccent : Color.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(width: playerNameplateWidth, height: playerNameplateHeight)
                            .background(isSelected ? FottyTheme.accent : Color(red: 0.08, green: 0.11, blue: 0.16))
                            .clipShape(
                                .rect(
                                    topLeadingRadius: 4,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0,
                                    topTrailingRadius: 4
                                )
                            )
                        
                        // 3. Opponent Team (Upcoming Match & Difficulty Color)
                        if let nextFixture = score.upcomingFixtures.first {
                            let oppCode = nextFixture.opponent.shortName
                            let location = nextFixture.isHome ? "H" : "A"
                            let diff = nextFixture.difficulty
                            let fdrBg = FottyFixtureDifficulty.background(diff)
                            let fdrFg = FottyFixtureDifficulty.foreground(diff)
                            
                            HStack(spacing: 2) {
                                Text("\(oppCode) \(location)\n\(diff)/5")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(fdrFg)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: playerNameplateWidth, height: playerSubplateHeight)
                            .background(fdrBg)
                            .clipShape(
                                .rect(
                                    topLeadingRadius: 0,
                                    bottomLeadingRadius: 4,
                                    bottomTrailingRadius: 4,
                                    topTrailingRadius: 0
                                )
                            )
                        } else {
                            HStack(spacing: 2) {
                                Text(score.team.shortName)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.black.opacity(0.7))
                            }
                            .frame(width: playerNameplateWidth, height: playerSubplateHeight)
                            .background(Color(red: 0.85, green: 0.85, blue: 0.87))
                            .clipShape(
                                .rect(
                                    topLeadingRadius: 0,
                                    bottomLeadingRadius: 4,
                                    bottomTrailingRadius: 4,
                                    topTrailingRadius: 0
                                )
                            )
                        }
                    }
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    
                    if pitchDisplayChip != .fixture {
                        Text(lensText(for: score, pick: pick))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(lensColor(for: score))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 5)
                            .frame(minHeight: isCompactWidth ? 12 : 14)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Capsule())
                    }
                }
                .frame(width: playerCardWidth)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playerAccessibilityLabel(score: score, pick: pick))
            .accessibilityHint("Opens player stats and squad actions")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
    }

    /// Large text gets a readable, full-width roster rather than a shrunken pitch.
    private var readableSquadList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach([false, true], id: \.self) { isBench in
                Text(isBench ? "Bench · substitution order" : "Starting eleven · \(formationString)")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(isBench ? benchPicks : startingPicks.sorted { $0.position < $1.position }) { pick in
                    if let score = getScore(for: pick.element) {
                        Button { handlePlayerTap(pick) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(score.player.webName + (pick.isCaptain ? " · Captain" : (pick.isViceCaptain ? " · Vice-captain" : "")))
                                    .font(.headline)
                                    .foregroundStyle(FottyTheme.textPrimary)
                                Text("\(score.team.name) · \(score.player.formattedCost)")
                                    .font(.subheadline)
                                    .foregroundStyle(FottyTheme.textSecondary)
                                if let fixture = score.upcomingFixtures.first {
                                    Text("\(fixture.opponent.shortName) · \(fixture.isHome ? "Home" : "Away") · \(FottyFixtureDifficulty.label(fixture.difficulty))")
                                        .font(.subheadline)
                                        .foregroundStyle(FottyTheme.textSecondary)
                                }
                                if pitchDisplayChip != .fixture {
                                    Text(lensText(for: score, pick: pick)).font(.subheadline).foregroundStyle(FottyTheme.accentText)
                                }
                            }
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(FottyTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(playerAccessibilityLabel(score: score, pick: pick))
                        .accessibilityHint("Opens player stats and squad actions")
                    }
                }
            }
        }
    }

    private func playerAccessibilityLabel(score: PlayerScore, pick: FPLPick) -> String {
        let role = pick.isCaptain ? "Captain" : (pick.isViceCaptain ? "Vice-captain" : "")
        let slot = pick.position <= 11 ? "Starting eleven" : (pick.position == 12 ? "Bench goalkeeper" : "Substitute \(pick.position - 12)")
        let fixture = score.upcomingFixtures.first.map {
            "\($0.opponent.name), \($0.isHome ? "home" : "away"), \(FottyFixtureDifficulty.label($0.difficulty))"
        } ?? "No upcoming fixture"
        return "\(score.player.webName), \(score.team.name), \(role), \(slot), \(score.player.formattedCost), \(fixture), \(lensText(for: score, pick: pick))"
    }

    private func lensProjection(for score: PlayerScore) -> FPLPlayerProjection {
        FPLProjectionEngine.project(
            player: score.player,
            fixtures: fixtures,
            startGameweek: projectionStartGameweek,
            horizon: 1
        )
    }

    private func lensText(for score: PlayerScore, pick: FPLPick) -> String {
        switch pitchDisplayChip {
        case .fixture:
            return score.upcomingFixtures.first.map { "\($0.opponent.shortName) \($0.isHome ? "H" : "A")" } ?? "No fixture"
        case .projection:
            let projection = lensProjection(for: score)
            return "xP \(String(format: "%.1f", projection.gameweekPoints[projectionStartGameweek] ?? 0))"
        case .minutes:
            let projection = lensProjection(for: score)
            return "xMin \(projection.expectedMinutes[projectionStartGameweek] ?? 0) · \(projection.confidence.rawValue.prefix(1))"
        case .form:
            return "Form \(score.player.form)"
        case .ownership:
            return "Own \(score.player.selectedByPercent)%"
        case .price:
            return "\(score.player.formattedCost) · \(score.priceChangeRisk.rawValue)"
        case .livePoints:
            return "\(score.player.eventPoints * pick.multiplier) pts"
        }
    }

    private func lensColor(for score: PlayerScore) -> Color {
        switch pitchDisplayChip {
        case .price where score.priceChangeRisk == .falling: return FottyTheme.accentText
        case .price where score.priceChangeRisk == .rising: return FottyTheme.success
        case .livePoints where score.player.eventPoints > 0: return FottyTheme.success
        default: return FottyTheme.accentText
        }
    }
    
    private func handlePlayerTap(_ tappedPick: FPLPick) {
        if let firstID = selectedPickID {
            if firstID == tappedPick.element {
                selectedPickID = nil
            } else if let firstIdx = currentPicks.firstIndex(where: { $0.element == firstID }),
                      let secondIdx = currentPicks.firstIndex(where: { $0.element == tappedPick.element }) {
                
                let p1 = currentPicks[firstIdx]
                let p2 = currentPicks[secondIdx]
                
                let type1 = getScore(for: p1.element)?.player.elementType ?? 0
                let type2 = getScore(for: p2.element)?.player.elementType ?? 0
                
                if (type1 == 1 && type2 != 1) || (type2 == 1 && type1 != 1) {
                    selectedPickID = tappedPick.element
                    return
                }
                
                var updated = currentPicks
                let pos1 = p1.position
                let pos2 = p2.position
                
                updated[firstIdx] = FPLPick(element: p1.element, position: pos2, multiplier: p2.multiplier, isCaptain: p2.isCaptain, isViceCaptain: p2.isViceCaptain, purchasePrice: p1.purchasePrice, sellingPrice: p1.sellingPrice)
                updated[secondIdx] = FPLPick(element: p2.element, position: pos1, multiplier: p1.multiplier, isCaptain: p1.isCaptain, isViceCaptain: p1.isViceCaptain, purchasePrice: p2.purchasePrice, sellingPrice: p2.sellingPrice)
                
                selectedPickID = nil
                commitDraft(updated)
            }
        } else {
            playerForActionSheet = tappedPick
        }
    }
    
    private func autoOptimizeStartingXI() {
        let currentScores = currentPicks.compactMap { pick in
            getScore(for: pick.element).map { (pick: pick, score: $0) }
        }
        guard currentScores.count == 15 else { return }
        
        let gks = currentScores.filter { $0.score.player.elementType == 1 }.sorted { $0.score.compositeScore > $1.score.compositeScore }
        let defs = currentScores.filter { $0.score.player.elementType == 2 }.sorted { $0.score.compositeScore > $1.score.compositeScore }
        let mids = currentScores.filter { $0.score.player.elementType == 3 }.sorted { $0.score.compositeScore > $1.score.compositeScore }
        let fwds = currentScores.filter { $0.score.player.elementType == 4 }.sorted { $0.score.compositeScore > $1.score.compositeScore }
        
        let legalFormations = [
            (def: 3, mid: 5, fwd: 2),
            (def: 3, mid: 4, fwd: 3),
            (def: 4, mid: 4, fwd: 2),
            (def: 4, mid: 3, fwd: 3),
            (def: 4, mid: 5, fwd: 1),
            (def: 5, mid: 3, fwd: 2),
            (def: 5, mid: 4, fwd: 1),
            (def: 5, mid: 2, fwd: 3)
        ]
        
        var bestFormation = legalFormations[0]
        var bestScore = -1.0
        
        for f in legalFormations {
            guard defs.count >= f.def, mids.count >= f.mid, fwds.count >= f.fwd else { continue }
            let startingDEFScore = defs.prefix(f.def).reduce(0.0) { $0 + $1.score.compositeScore }
            let startingMIDScore = mids.prefix(f.mid).reduce(0.0) { $0 + $1.score.compositeScore }
            let startingFWDScore = fwds.prefix(f.fwd).reduce(0.0) { $0 + $1.score.compositeScore }
            let total = (gks.first?.score.compositeScore ?? 0) + startingDEFScore + startingMIDScore + startingFWDScore
            if total > bestScore {
                bestScore = total
                bestFormation = f
            }
        }
        
        var updated: [FPLPick] = []
        var pos = 1
        
        // Starting GK
        if let bestGK = gks.first {
            updated.append(FPLPick(element: bestGK.score.player.id, position: pos, multiplier: 1, isCaptain: false, isViceCaptain: false, purchasePrice: bestGK.pick.purchasePrice, sellingPrice: bestGK.pick.sellingPrice))
            pos += 1
        }
        // Starting DEFs
        for d in defs.prefix(bestFormation.def) {
            updated.append(FPLPick(element: d.score.player.id, position: pos, multiplier: 1, isCaptain: false, isViceCaptain: false, purchasePrice: d.pick.purchasePrice, sellingPrice: d.pick.sellingPrice))
            pos += 1
        }
        // Starting MIDs
        for m in mids.prefix(bestFormation.mid) {
            updated.append(FPLPick(element: m.score.player.id, position: pos, multiplier: 1, isCaptain: false, isViceCaptain: false, purchasePrice: m.pick.purchasePrice, sellingPrice: m.pick.sellingPrice))
            pos += 1
        }
        // Starting FWDs
        for f in fwds.prefix(bestFormation.fwd) {
            updated.append(FPLPick(element: f.score.player.id, position: pos, multiplier: 1, isCaptain: false, isViceCaptain: false, purchasePrice: f.pick.purchasePrice, sellingPrice: f.pick.sellingPrice))
            pos += 1
        }
        
        // Bench GK (pos 12)
        if gks.count > 1 {
            updated.append(FPLPick(element: gks[1].score.player.id, position: 12, multiplier: 0, isCaptain: false, isViceCaptain: false, purchasePrice: gks[1].pick.purchasePrice, sellingPrice: gks[1].pick.sellingPrice))
        }
        
        // Bench Outfield Players sorted by score
        let benchOutfield = (defs.dropFirst(bestFormation.def) + mids.dropFirst(bestFormation.mid) + fwds.dropFirst(bestFormation.fwd))
            .sorted { $0.score.compositeScore > $1.score.compositeScore }
        
        var benchPos = 13
        for b in benchOutfield {
            updated.append(FPLPick(element: b.score.player.id, position: benchPos, multiplier: 0, isCaptain: false, isViceCaptain: false, purchasePrice: b.pick.purchasePrice, sellingPrice: b.pick.sellingPrice))
            benchPos += 1
        }
        
        // Auto-assign Captain to Top 1 and Vice to Top 2
        let sortedStarters = updated.filter { $0.position <= 11 }.sorted { p1, p2 in
            (getScore(for: p1.element)?.compositeScore ?? 0) > (getScore(for: p2.element)?.compositeScore ?? 0)
        }
        
        if let capId = sortedStarters.first?.element {
            let viceId = sortedStarters.count > 1 ? sortedStarters[1].element : nil
            for i in 0..<updated.count {
                let isCap = updated[i].element == capId
                let isVice = updated[i].element == viceId
                updated[i] = FPLPick(
                    element: updated[i].element,
                    position: updated[i].position,
                    multiplier: isCap ? 2 : (updated[i].position > 11 ? 0 : 1),
                    isCaptain: isCap,
                    isViceCaptain: isVice,
                    purchasePrice: updated[i].purchasePrice,
                    sellingPrice: updated[i].sellingPrice
                )
            }
        }
        
        commitDraft(updated)
    }
    
    private func replacePlayerInSquad(oldElementId: Int, newElementId: Int) -> Bool {
        guard let idx = currentPicks.firstIndex(where: { $0.element == oldElementId }) else { return false }
        var updated = currentPicks
        let old = currentPicks[idx]
        updated[idx] = FPLPick(
            element: newElementId,
            position: old.position,
            multiplier: old.multiplier,
            isCaptain: old.isCaptain,
            isViceCaptain: old.isViceCaptain
        )
        return commitDraft(updated)
    }
    
    private func setCaptain(elementId: Int) {
        var updated = currentPicks
        let previousCaptain = currentPicks.first(where: \.isCaptain)?.element
        let targetWasVice = currentPicks.first(where: { $0.element == elementId })?.isViceCaptain == true
        for i in 0..<updated.count {
            let p = updated[i]
            let isCap = p.element == elementId
            let isVice = targetWasVice ? p.element == previousCaptain : (p.isViceCaptain && !isCap)
            let mult = isCap ? 2 : (p.position > 11 ? 0 : 1)
            updated[i] = FPLPick(
                element: p.element,
                position: p.position,
                multiplier: mult,
                isCaptain: isCap,
                isViceCaptain: isVice,
                purchasePrice: p.purchasePrice,
                sellingPrice: p.sellingPrice
            )
        }
        commitDraft(updated)
    }
    
    private func setViceCaptain(elementId: Int) {
        var updated = currentPicks
        let previousVice = currentPicks.first(where: \.isViceCaptain)?.element
        let targetWasCaptain = currentPicks.first(where: { $0.element == elementId })?.isCaptain == true
        for i in 0..<updated.count {
            let p = updated[i]
            let isVice = p.element == elementId
            let isCap = targetWasCaptain ? p.element == previousVice : (p.isCaptain && !isVice)
            let mult = isCap ? 2 : (p.position > 11 ? 0 : 1)
            updated[i] = FPLPick(
                element: p.element,
                position: p.position,
                multiplier: mult,
                isCaptain: isCap,
                isViceCaptain: isVice,
                purchasePrice: p.purchasePrice,
                sellingPrice: p.sellingPrice
            )
        }
        commitDraft(updated)
    }

    @discardableResult
    private func commitDraft(_ updated: [FPLPick]) -> Bool {
        guard onUpdateSquad?(updated) != false else { return false }
        currentPicks = updated
        return true
    }
}

// MARK: - Official Player Deep-Dive Sheet

public struct FPLPlayerDetailSheet: View {
    let score: PlayerScore
    let onMakeCaptain: () -> Void
    let onMakeViceCaptain: () -> Void
    let onReplace: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    private var photoURL: URL? {
        if let code = score.player.code {
            return URL(string: "https://resources.premierleague.com/premierleague/photos/players/250x250/p\(code).png")
        }
        return nil
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                FottyTheme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        heroCardView
                        underlyingMetricsCard
                        upcomingFixturesCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle(score.player.webName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.fottyScaled(size: 14, weight: .bold))
                    .foregroundStyle(FottyTheme.accentText)
                }
            }
        }
    }
    
    @ViewBuilder
    private var heroCardView: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                AsyncImage(url: photoURL) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 84, height: 106)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    default:
                        FPLOfficialShirtImageView(
                            teamCode: score.team.code,
                            isGoalkeeper: score.player.elementType == 1,
                            size: 64
                        )
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(score.player.firstName) \(score.player.secondName)")
                        .font(.fottyScaled(size: 18, weight: .black))
                        .foregroundStyle(FottyTheme.textPrimary)
                    
                    Text("\(score.team.name) • \(score.player.positionName)")
                        .font(.fottyScaled(size: 12, weight: .bold))
                        .foregroundStyle(FottyTheme.accentText)
                    
                    HStack(spacing: 8) {
                        Text(score.player.formattedCost)
                            .font(.fottyScaled(size: 14, weight: .black))
                            .foregroundStyle(FottyTheme.textPrimary)
                        
                        Text("•")
                            .foregroundStyle(FottyTheme.textTertiary)
                        
                        Text("\(score.player.selectedByPercent)% Owned")
                            .font(.fottyScaled(size: 12, weight: .medium))
                            .foregroundStyle(FottyTheme.textSecondary)
                    }
                }
                
                Spacer()
            }
            
            HStack(spacing: 8) {
                Button {
                    onMakeCaptain()
                    dismiss()
                } label: {
                    Label("Captain (C)", systemImage: "crown.fill")
                        .font(.fottyScaled(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.yellow)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                Button {
                    onMakeViceCaptain()
                    dismiss()
                } label: {
                    Label("Vice (V)", systemImage: "star.fill")
                        .font(.fottyScaled(size: 11, weight: .bold))
                        .foregroundStyle(FottyTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(FottyTheme.surfaceElevated)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                Button {
                    dismiss()
                    onReplace()
                } label: {
                    Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                        .font(.fottyScaled(size: 11, weight: .bold))
                        .foregroundStyle(FottyTheme.accentText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(FottyTheme.accent.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
    
    @ViewBuilder
    private var underlyingMetricsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("UNDERLYING EXPECTED METRICS")
                .font(.fottyScaled(size: 11, weight: .black))
                .foregroundStyle(FottyTheme.textSecondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statTile(title: "FPL next-GW estimate", value: metric(score.player.officialExpectedPointsNext))
                statTile(title: "Points / match", value: score.player.pointsPerGame)
                statTile(title: "xGI / 90", value: metric(score.player.expectedGoalInvolvementsPer90))
                statTile(title: "Expected Goals (xG)", value: String(format: "%.2f", score.player.xGValue))
                statTile(title: "Expected Assists (xA)", value: String(format: "%.2f", score.player.xAValue))
                statTile(title: "Def. contrib / 90", value: metric(score.player.defensiveContributionPer90))
                statTile(title: "Minutes", value: score.player.minutes.formatted())
                statTile(title: "Form", value: score.player.form)
                statTile(title: "ICT Index", value: score.player.ictIndex)
            }

            Text(setPieceText)
                .font(.caption2)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !score.player.news.isEmpty {
                Label(score.player.news, systemImage: "cross.case.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(FottyTheme.accentText)
            }
        }
        .padding(16)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
    
    @ViewBuilder
    private var upcomingFixturesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("UPCOMING 5 FIXTURES")
                .font(.fottyScaled(size: 11, weight: .black))
                .foregroundStyle(FottyTheme.textSecondary)
            
            HStack(spacing: 8) {
                ForEach(score.upcomingFixtures.prefix(5)) { fix in
                    VStack(spacing: 4) {
                        Text("GW\(fix.gameweek)")
                            .font(.fottyScaled(size: 9, weight: .bold))
                            .foregroundStyle(FottyTheme.textTertiary)
                        
                        Text(fix.opponent.shortName)
                            .font(.fottyScaled(size: 11, weight: .black))
                            .foregroundStyle(FottyTheme.textPrimary)
                        
                        Text(fix.isHome ? "(H)" : "(A)")
                            .font(.fottyScaled(size: 8, weight: .medium))
                            .foregroundStyle(FottyTheme.textSecondary)
                        
                        Text("\(fix.difficulty)")
                            .font(.fottyScaled(size: 10, weight: .black))
                            .foregroundStyle(fix.difficulty <= 2 ? Color.green : (fix.difficulty >= 4 ? FottyTheme.accentText : FottyTheme.accentText))
                            .frame(width: 22, height: 18)
                            .background(FottyTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(FottyTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
    
    @ViewBuilder
    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.fottyScaled(size: 8, weight: .black))
                .foregroundStyle(FottyTheme.textTertiary)
                .lineLimit(1)
            Text(value)
                .font(.fottyScaled(size: 15, weight: .black))
                .foregroundStyle(FottyTheme.textPrimary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FottyTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func metric(_ value: Double?) -> String {
        value?.formatted(.number.precision(.fractionLength(2))) ?? "Not supplied"
    }

    private var setPieceText: String {
        var roles = [String]()
        if let order = score.player.penaltiesOrder { roles.append("penalties #\(order)") }
        if let order = score.player.directFreekicksOrder { roles.append("direct free-kicks #\(order)") }
        if let order = score.player.cornersAndIndirectFreekicksOrder { roles.append("corners/indirect #\(order)") }
        return roles.isEmpty ? "Official set-piece order is not supplied for this player." : "Official set pieces: " + roles.joined(separator: ", ") + "."
    }
}

// MARK: - Player Picker Sheet

public struct FPLPlayerPickerSheet: View {
    let initialPositionType: Int // 1: GKP, 2: DEF, 3: MID, 4: FWD, 0: All
    let currentElementId: Int
    let scores: [PlayerScore]
    let teams: [FPLTeam]
    /// Nil means accepted; an explanation keeps the picker open on rejection.
    let onSelect: (PlayerScore) -> String?
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPositionType: Int
    @State private var searchText = ""
    @State private var selectedTeamId: Int? = nil
    @State private var sortOption: SortOption = .compositeScore
    @State private var selectionError: String?
    
    public init(
        positionType: Int,
        currentElementId: Int,
        scores: [PlayerScore],
        teams: [FPLTeam],
        onSelect: @escaping (PlayerScore) -> String?
    ) {
        self.initialPositionType = positionType
        self.currentElementId = currentElementId
        self.scores = scores
        self.teams = teams
        self.onSelect = onSelect
        _selectedPositionType = State(initialValue: positionType)
    }
    
    public enum SortOption: String, CaseIterable, Identifiable {
        case compositeScore = "Fotty rating"
        case cost = "Price"
        case totalPoints = "Points"
        case selectedBy = "Ownership"
        
        public var id: String { rawValue }
    }
    
    private var currentPlayerScore: PlayerScore? {
        scores.first(where: { $0.player.id == currentElementId })
    }
    
    private var filteredPlayers: [PlayerScore] {
        scores.filter { score in
            // A replacement must keep the outgoing player's FPL position.
            if initialPositionType > 0 && score.player.elementType != initialPositionType {
                return false
            }
            if selectedPositionType > 0 && score.player.elementType != selectedPositionType {
                return false
            }
            if let teamId = selectedTeamId, score.player.team != teamId {
                return false
            }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                let matchName = score.player.webName.lowercased().contains(q) ||
                                score.player.firstName.lowercased().contains(q) ||
                                score.player.secondName.lowercased().contains(q)
                let matchTeam = score.team.name.lowercased().contains(q) ||
                                score.team.shortName.lowercased().contains(q)
                if !matchName && !matchTeam { return false }
            }
            return true
        }
        .sorted { left, right in
            switch sortOption {
            case .compositeScore:
                return left.compositeScore > right.compositeScore
            case .cost:
                return left.player.nowCost > right.player.nowCost
            case .totalPoints:
                return left.player.totalPoints > right.player.totalPoints
            case .selectedBy:
                let lPct = Double(left.player.selectedByPercent) ?? 0
                let rPct = Double(right.player.selectedByPercent) ?? 0
                return lPct > rPct
            }
        }
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                FottyTheme.background.ignoresSafeArea()
                
                VStack(spacing: 12) {
                    // Header / Currently Replaced Player
                    if let cur = currentPlayerScore {
                        HStack(spacing: 10) {
                            Text("REPLACING:")
                                .font(.fottyScaled(size: 10, weight: .black))
                                .foregroundStyle(FottyTheme.textTertiary)
                            
                            Text("\(cur.player.webName) (\(cur.team.shortName) • \(cur.player.formattedCost))")
                                .font(.fottyScaled(size: 12, weight: .bold))
                                .foregroundStyle(FottyTheme.accentText)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                    
                    // Position filters are only useful when not replacing a player.
                    if initialPositionType == 0 {
                    HStack(spacing: 6) {
                        positionTabButton(title: "All", type: 0)
                        positionTabButton(title: "GKP", type: 1)
                        positionTabButton(title: "DEF", type: 2)
                        positionTabButton(title: "MID", type: 3)
                        positionTabButton(title: "FWD", type: 4)
                    }
                    .padding(.horizontal, 16)
                    }
                    
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(FottyTheme.textTertiary)
                        
                        TextField("Search player name or club...", text: $searchText)
                            .font(.fottyScaled(size: 14, weight: .medium))
                            .foregroundStyle(FottyTheme.textPrimary)
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(FottyTheme.textTertiary)
                            }
                        }
                    }
                    .padding(10)
                    .background(FottyTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(FottyTheme.border, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    
                    // Sort & Filter Bar
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SortOption.allCases) { opt in
                                let isSelected = sortOption == opt
                                Button {
                                    HapticManager.impact(.light)
                                    sortOption = opt
                                } label: {
                                    HStack(spacing: 4) {
                                        if isSelected {
                                            Image(systemName: "arrow.down")
                                                .font(.fottyScaled(size: 9, weight: .black))
                                        }
                                        Text(opt.rawValue)
                                            .font(.fottyScaled(size: 11, weight: isSelected ? .bold : .medium))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? FottyTheme.accent : FottyTheme.surface)
                                    .foregroundStyle(isSelected ? FottyTheme.textOnAccent : FottyTheme.textSecondary)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(isSelected ? Color.clear : FottyTheme.border, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Divider()
                                .frame(height: 18)
                                .background(FottyTheme.border)
                            
                            Button {
                                HapticManager.impact(.light)
                                selectedTeamId = nil
                            } label: {
                                Text("All Clubs")
                                    .font(.fottyScaled(size: 11, weight: selectedTeamId == nil ? .bold : .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(selectedTeamId == nil ? FottyTheme.surfaceElevated : FottyTheme.surface)
                                    .foregroundStyle(selectedTeamId == nil ? FottyTheme.textPrimary : FottyTheme.textSecondary)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(selectedTeamId == nil ? FottyTheme.accent.opacity(0.4) : FottyTheme.border, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            
                            ForEach(teams) { team in
                                let isSelected = selectedTeamId == team.id
                                Button {
                                    HapticManager.impact(.light)
                                    selectedTeamId = isSelected ? nil : team.id
                                } label: {
                                    Text(team.shortName)
                                        .font(.fottyScaled(size: 11, weight: isSelected ? .bold : .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? FottyTheme.surfaceElevated : FottyTheme.surface)
                                        .foregroundStyle(isSelected ? FottyTheme.accentText : FottyTheme.textSecondary)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule().stroke(isSelected ? FottyTheme.accent : FottyTheme.border, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    if let selectionError {
                        Label(selectionError, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(FottyTheme.error)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16)
                            .accessibilityIdentifier("fpl-player-selection-error")
                    }

                    // Player Results ScrollView
                    if filteredPlayers.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.slash")
                                .font(.fottyScaled(size: 36))
                                .foregroundStyle(FottyTheme.textTertiary)
                            
                            Text("No players found")
                                .font(.fottyScaled(size: 16, weight: .bold))
                                .foregroundStyle(FottyTheme.textPrimary)
                            
                            Text("Try adjusting your position tab, search query, or club filter.")
                                .font(.fottyScaled(size: 12))
                                .foregroundStyle(FottyTheme.textSecondary)
                                .multilineTextAlignment(.center)
                            
                            Button {
                                searchText = ""
                                selectedTeamId = nil
                                selectedPositionType = 0
                            } label: {
                                Text("Reset All Filters")
                                    .font(.fottyScaled(size: 12, weight: .bold))
                                    .foregroundStyle(FottyTheme.accentText)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(FottyTheme.surfaceElevated)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 6)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(filteredPlayers) { score in
                                    let isCurrent = score.player.id == currentElementId
                                    let isGK = score.player.elementType == 1
                                    
                                    Button {
                                        HapticManager.impact(.medium)
                                        selectionError = onSelect(score)
                                        if selectionError == nil { dismiss() }
                                    } label: {
                                        playerCardRow(score, isCurrent: isCurrent, isGK: isGK)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("fpl-replacement-\(score.player.id)")
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
            .navigationTitle("Select Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.fottyScaled(size: 14, weight: .bold))
                    .foregroundStyle(FottyTheme.accentText)
                }
            }
        }
    }
    
    @ViewBuilder
    private func positionTabButton(title: String, type: Int) -> some View {
        let isSelected = selectedPositionType == type
        Button {
            HapticManager.impact(.light)
            selectedPositionType = type
        } label: {
            Text(title)
                .font(.fottyScaled(size: 11, weight: isSelected ? .black : .bold))
                .foregroundStyle(isSelected ? FottyTheme.textOnAccent : FottyTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(isSelected ? FottyTheme.accent : FottyTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.clear : FottyTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func playerCardRow(_ score: PlayerScore, isCurrent: Bool, isGK: Bool) -> some View {
        let comp = score.compositeScore
        let color: Color = comp >= 65 ? FottyTheme.success : (comp >= 40 ? FottyTheme.accentText : FottyTheme.error)
        
        HStack(spacing: 12) {
            FPLOfficialShirtImageView(
                teamCode: score.team.code,
                isGoalkeeper: isGK,
                size: 40
            )
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(score.player.webName)
                        .font(.fottyScaled(size: 15, weight: .bold))
                        .foregroundStyle(FottyTheme.textPrimary)
                    
                    if isCurrent {
                        Text("CURRENT")
                            .font(.fottyScaled(size: 8, weight: .black))
                            .foregroundStyle(FottyTheme.textOnAccent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(FottyTheme.accent)
                            .clipShape(Capsule())
                    }
                }
                
                HStack(spacing: 4) {
                    Text("\(score.team.name) • \(score.player.positionName)")
                    
                    if let nextFixture = score.upcomingFixtures.first {
                        Text("•")
                        let opp = nextFixture.opponent.shortName
                        let loc = nextFixture.isHome ? "(H)" : "(A)"
                        Text("vs \(opp) \(loc)")
                            .font(.fottyScaled(size: 11, weight: .bold))
                            .foregroundStyle(nextFixture.difficulty <= 2 ? FottyTheme.success : (nextFixture.difficulty >= 4 ? FottyTheme.accentText : FottyTheme.textSecondary))
                    }
                }
                .font(.fottyScaled(size: 11, weight: .medium))
                .foregroundStyle(FottyTheme.textSecondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(score.player.formattedCost)
                    .font(.fottyScaled(size: 15, weight: .black))
                    .foregroundStyle(FottyTheme.accentText)
                
                HStack(spacing: 6) {
                    Text("AI \(Int(comp.rounded()))")
                        .font(.fottyScaled(size: 10, weight: .bold))
                        .foregroundStyle(color)
                    
                    Text("\(score.player.selectedByPercent)%")
                        .font(.fottyScaled(size: 10, weight: .medium))
                        .foregroundStyle(FottyTheme.textTertiary)
                }
            }
        }
        .padding(12)
        .background(isCurrent ? FottyTheme.accent.opacity(0.12) : FottyTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrent ? FottyTheme.accent.opacity(0.4) : FottyTheme.border, lineWidth: 1)
        )
    }
}
