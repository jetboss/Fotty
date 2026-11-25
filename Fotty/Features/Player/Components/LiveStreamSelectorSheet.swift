import SwiftUI

// MARK: - Live Stream Selector Sheet
// A compact, consumer-facing picker. Diagnostics and provider health internals do
// not belong here: every visible label should help somebody choose a source.

struct LiveStreamSelectorSheet: View {
    enum ViewingContext: Equatable { case match, channel }
    let sessions: [StreamSession]
    @Binding var currentSourceIndex: Int
    let failedSessionIDs: Set<UUID>
    let currentPlaybackHasError: Bool
    let currentPlaybackMode: LivePlaybackMode?
    let isCheckingAdditionalSources: Bool
    let usesSinglePlayerPresentation: Bool
    let viewingContext: ViewingContext
    let recommendedIndices: [Int]?
    let onWrongMatch: ((UUID) -> Void)?
    let onSelect: (Int) -> Void
    @State private var selection: BroadcastSourcePickerPolicy.Filter = .automatic
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    init(
        sessions: [StreamSession],
        currentSourceIndex: Binding<Int>,
        failedSessionIDs: Set<UUID>,
        currentPlaybackHasError: Bool = false,
        currentPlaybackMode: LivePlaybackMode? = nil,
        isCheckingAdditionalSources: Bool = false,
        usesSinglePlayerPresentation: Bool = false,
        viewingContext: ViewingContext = .match,
        recommendedIndices: [Int]? = nil,
        onWrongMatch: ((UUID) -> Void)? = nil,
        onSelect: @escaping (Int) -> Void
    ) {
        self.sessions = sessions
        self._currentSourceIndex = currentSourceIndex
        self.failedSessionIDs = failedSessionIDs
        self.currentPlaybackHasError = currentPlaybackHasError
        self.currentPlaybackMode = currentPlaybackMode
        self.isCheckingAdditionalSources = isCheckingAdditionalSources
        self.usesSinglePlayerPresentation = usesSinglePlayerPresentation
        self.viewingContext = viewingContext
        self.recommendedIndices = recommendedIndices
        self.onWrongMatch = onWrongMatch
        self.onSelect = onSelect
    }
    
    private var playableSessions: [(index: Int, session: StreamSession)] {
        sessions.enumerated().compactMap { index, session in
            (session.validationStatus == .validated) ? (index, session) : nil
        }
    }

    private var groups: [String] { BroadcastSourcePickerPolicy.groups(in: playableSessions.map(\.session)) }
    private var effectiveGroup: String? {
        guard case .group(let group) = selection, groups.contains(group) else { return nil }
        return group
    }
    private var matchProjection: BroadcastSourcePickerPolicy.MatchProjection? {
        guard usesSinglePlayerPresentation, viewingContext == .match, let recommendedIndices else { return nil }
        return BroadcastSourcePickerPolicy.matchProjection(sessions, recommended: recommendedIndices, filter: selection)
    }
    private var visibleSessions: [(index: Int, session: StreamSession)] {
        if let projection = matchProjection {
            return projection.indices.map { ($0, sessions[$0]) }
        }
        return playableSessions.filter { effectiveGroup == nil || BroadcastSourcePickerPolicy.group(for: $0.session) == effectiveGroup }
    }
    private var offersGroupFilter: Bool {
        groups.count > 1 || (recommendedIndices.map { $0.count < playableSessions.count } ?? false)
    }
    
    var body: some View {
        Group {
            if usesSinglePlayerPresentation { singlePlayerSheet }
            else { standardSheet }
        }
        .background(FottyTheme.background)
        .preferredColorScheme(.dark)
        .onChange(of: groups) { _, next in
            if case .group(let group) = selection, !next.contains(group) { selection = .automatic }
        }
    }

    /// Keep only a compact native-style title and Close above the scroll area.
    /// At large text, a count, group menu and discovery phase can otherwise use
    /// an entire medium detent and leave the actual source choices no viewport.
    private var singlePlayerSheet: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text("Sources")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityValue(sourceSummary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(FottyPressButtonStyle(cornerRadius: 22))
                .accessibilityLabel("Close broadcast sources")
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: 672).frame(maxWidth: .infinity)
            .background(FottyTheme.surfaceSubtle)
            .overlay(alignment: .bottom) { Divider() }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(sourceSummary)
                        .font(.subheadline)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if offersGroupFilter || isCheckingAdditionalSources {
                        singleSourceFilters
                    }
                    joinedSourceChoices
                    if let onWrongMatch, sessions.indices.contains(currentSourceIndex), !currentPlaybackHasError {
                        Button {
                            onWrongMatch(sessions[currentSourceIndex].id)
                            dismiss()
                        } label: {
                            Label("Wrong match or blocked picture", systemImage: "flag")
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(minHeight: 44, alignment: .leading)
                        }
                        .accessibilityHint("Tries another broadcast and avoids this delivery for this match")
                        .accessibilityIdentifier("single-source-wrong-programme")
                    }
                    if let title = matchProjection?.showAllTitle {
                        Button(title) { selection = .all }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("broadcast-show-all-sources")
                    }
                }
                .frame(maxWidth: 640)
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("single-source-picker-scroll")
        }
    }

    private var singleSourceFilters: some View {
        filterLayout {
            if offersGroupFilter {
                Menu {
                    Picker("Source group", selection: $selection) {
                        Text(recommendedIndices == nil ? "All sources" : "Recommended").tag(BroadcastSourcePickerPolicy.Filter.automatic)
                        if recommendedIndices != nil { Text("All sources").tag(BroadcastSourcePickerPolicy.Filter.all) }
                        ForEach(groups, id: \.self) { Text($0).tag(BroadcastSourcePickerPolicy.Filter.group($0)) }
                    }
                } label: {
                    Label(effectiveGroup ?? (recommendedIndices == nil || selection == .all ? "All sources" : "Recommended"), systemImage: "line.3.horizontal.decrease")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("broadcast-source-filter")
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            if isCheckingAdditionalSources {
                ProgressView("Checking more sources…")
                    .font(.caption)
                    .accessibilityIdentifier("broadcast-sources-checking")
            }
        }
        .tint(FottyTheme.accentText)
    }

    private var joinedSourceChoices: some View {
        VStack(spacing: 0) {
            ForEach(visibleSessions, id: \.session.id) { index, session in
                SessionRow(session: session, displayNumber: index + 1,
                    isActive: index == currentSourceIndex,
                    isFailed: failedSessionIDs.contains(session.id)
                        || (index == currentSourceIndex && currentPlaybackHasError),
                    isCoolingDown: LiveSourceHealthStore.isTemporarilyUnavailable(session.legacySource),
                    currentMode: index == currentSourceIndex ? currentPlaybackMode : nil,
                    usesJoinedPresentation: true) {
                    if index != currentSourceIndex
                        || failedSessionIDs.contains(session.id)
                        || (index == currentSourceIndex && currentPlaybackHasError)
                        || LiveSourceHealthStore.isTemporarilyUnavailable(session.legacySource) {
                        onSelect(index)
                        dismiss()
                    }
                }
                .contextMenu {
                    if let onWrongMatch, index == currentSourceIndex, !currentPlaybackHasError {
                        Button("Showing a different match", systemImage: "flag") {
                            onWrongMatch(session.id)
                            dismiss()
                        }
                    }
                }
                if index != visibleSessions.last?.index {
                    Divider().padding(.leading, 16)
                }
            }
            if visibleSessions.isEmpty {
                Text(isCheckingAdditionalSources ? "Available sources will appear here." : "No recommended sources are available right now.")
                    .font(.body).foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
        .background(FottyTheme.surface, in: .rect(cornerRadius: FottyTheme.radiusLG))
        .overlay {
            RoundedRectangle(cornerRadius: FottyTheme.radiusLG)
                .strokeBorder(FottyTheme.border, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }

    /// Retain the existing presentation for other consumers, including Watch
    /// Two. Only the explicitly opted-in single player uses the new scroll flow.
    private var standardSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Broadcast sources")
                        .font(usesSinglePlayerPresentation ? .title2.weight(.semibold) : .title2.weight(.bold))
                        .foregroundStyle(FottyTheme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    
                    Text(sourceSummary)
                        .font(.subheadline)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(FottyTheme.textTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FottyPressButtonStyle(cornerRadius: 22))
                .accessibilityLabel("Close broadcast sources")
            }
            .padding(.horizontal, FottyTheme.spacingLG)
            .padding(.top, FottyTheme.spacingLG)
            .padding(.bottom, FottyTheme.spacingMD)
            .frame(maxWidth: usesSinglePlayerPresentation ? 672 : .infinity)
            .frame(maxWidth: .infinity)

            if groups.count > 1 || isCheckingAdditionalSources {
                filterLayout {
                    if groups.count > 1 {
                        Menu {
                            Picker("Source group", selection: $selection) {
                                Text("All sources").tag(BroadcastSourcePickerPolicy.Filter.automatic)
                                ForEach(groups, id: \.self) { Text($0).tag(BroadcastSourcePickerPolicy.Filter.group($0)) }
                            }
                        } label: {
                            Label(effectiveGroup ?? "All sources", systemImage: "line.3.horizontal.decrease")
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("broadcast-source-filter")
                    }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    if isCheckingAdditionalSources {
                        ProgressView("Checking more sources…")
                            .font(.caption)
                            .accessibilityIdentifier("broadcast-sources-checking")
                    }
                }
                .tint(FottyTheme.accentText)
                .padding(.horizontal, FottyTheme.spacingLG)
                .frame(maxWidth: usesSinglePlayerPresentation ? 672 : .infinity)
                .frame(maxWidth: .infinity)
            }
            
            ScrollView {
                VStack(spacing: usesSinglePlayerPresentation ? 0 : FottyTheme.spacingMD) {
                    ForEach(visibleSessions, id: \.session.id) { index, session in
                        SessionRow(
                            session: session,
                            displayNumber: index + 1,
                            isActive: index == currentSourceIndex,
                            isFailed: failedSessionIDs.contains(session.id)
                                || (index == currentSourceIndex && currentPlaybackHasError),
                            isCoolingDown: LiveSourceHealthStore.isTemporarilyUnavailable(session.legacySource),
                            currentMode: index == currentSourceIndex ? currentPlaybackMode : nil,
                            usesJoinedPresentation: usesSinglePlayerPresentation
                        ) {
                            if index != currentSourceIndex
                                || failedSessionIDs.contains(session.id)
                                || (index == currentSourceIndex && currentPlaybackHasError)
                                || LiveSourceHealthStore.isTemporarilyUnavailable(session.legacySource) {
                                onSelect(index)
                                dismiss()
                            }
                        }
                        if usesSinglePlayerPresentation, index != visibleSessions.last?.index {
                            Divider().padding(.leading, 16)
                        }
                    }
                    if playableSessions.isEmpty {
                        Text(isCheckingAdditionalSources ? "Available sources will appear here." : "No supported sources are available right now.")
                            .font(.body).foregroundStyle(FottyTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(usesSinglePlayerPresentation ? 20 : 0)
                    }
                }
                .background(usesSinglePlayerPresentation ? FottyTheme.surface : .clear,
                            in: .rect(cornerRadius: FottyTheme.radiusLG))
                .overlay {
                    if usesSinglePlayerPresentation {
                        RoundedRectangle(cornerRadius: FottyTheme.radiusLG)
                            .strokeBorder(FottyTheme.border, lineWidth: 0.5)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: usesSinglePlayerPresentation ? 640 : .infinity)
                .padding(.horizontal, FottyTheme.spacingMD)
                .padding(.top, usesSinglePlayerPresentation ? FottyTheme.spacingMD : 0)
                .padding(.bottom, FottyTheme.spacingXL)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var sourceSummary: String {
        if let summary = matchProjection?.summary { return summary }
        let count = usesSinglePlayerPresentation && viewingContext == .match ? visibleSessions.count : playableSessions.count
        let subject = usesSinglePlayerPresentation && viewingContext == .channel ? "channel" : "match"
        if count == 0 { return isCheckingAdditionalSources ? "Looking for this \(subject)" : "No sources found" }
        if usesSinglePlayerPresentation {
            return count == 1 ? "1 source for this \(subject)" : "\(count) sources for this \(subject)"
        }
        let noun = count == 1 ? "broadcast option" : "broadcast options"
        return "\(count) \(noun) · Tap one to switch playback"
    }

    private var filterLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
    }
}

/// Neutral primary broadcasts and reviewed opaque families only. Never copy a
/// remote provider title, host or URL into filter labels.
enum BroadcastSourcePickerPolicy {
    enum Filter: Hashable { case automatic, all, group(String) }
    struct MatchProjection {
        let indices: [Int]
        let summary: String?
        let showAllTitle: String?
    }
    static func matchProjection(_ sessions: [StreamSession], recommended: [Int], filter: Filter) -> MatchProjection {
        let all = sessions.indices.filter { sessions[$0].validationStatus == .validated }
        let visible: [Int]
        switch filter {
        case .automatic: visible = recommended.filter { all.contains($0) }
        case .all: visible = all
        case .group(let name): visible = all.filter { group(for: sessions[$0]) == name }
        }
        guard visible.count < all.count else { return .init(indices: visible, summary: nil, showAllTitle: nil) }
        let summary = filter == .automatic ? "\(visible.count) recommended · \(all.count) available"
            : "\(visible.count) of \(all.count) sources"
        let action = all.count == 1 ? "Show the available source" : "Show all \(all.count) sources"
        return .init(indices: visible, summary: summary, showAllTitle: action)
    }
    /// Source IDs in this projection always map back to the full admitted list.
    /// A selected language/group remains manually browsable, including variants
    /// sharing a host. Distinct origins are not advertised as independent feeds.
    @MainActor static func recommendations(
        sessions: [StreamSession], currentIndex: Int, failedIDs: Set<UUID>,
        for event: EventReference, at now: Date = Date(),
        hasRecentStart: ((StreamSource) -> Bool)? = nil,
        enabledProviders: Set<String>? = nil
    ) -> [Int] {
        let request = StreamPlaybackRequest(event: event)
        let candidates = sessions.indices.filter { index in
            let session = sessions[index]
            guard !failedIDs.contains(session.id), session.matchID == event.id,
                  session.validationStatus == .validated else { return false }
            let evidence = LiveSourceHealthStore.matchEvidence(for: session, at: now)
            guard evidence != .wrongProgramme else { return false }
            if index == currentIndex { return true } // An already displayed item can outlive its lookup receipt.
            guard evidence != .recentlyFailed, evidence != .repeatedlyFailed else { return false }
            guard LivePlaybackSourcePolicy.admissionForMatchAlternative(session, request: request, at: now,
                enabledProviders: enabledProviders) == .ready else { return false }
            return session.eventBinding != nil || (hasRecentStart?(session.legacySource) ?? (evidence.hasPlayed))
        }
        let ranked = LiveSourceHealthStore.rankedSingleStreamSessions(candidates.map { sessions[$0] },
            contextKey: LiveSourceHealthStore.contextKey(for: event), at: now)
        let indices = Dictionary(candidates.map { (sessions[$0].id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = ranked.compactMap { indices[$0.id] }
        var result = candidates.contains(currentIndex) ? [currentIndex] : Array(ordered.prefix(1))
        guard !result.isEmpty else { return [] }
        // Prefer different publishers first. Only when no such route is left
        // consider a distinct delivery origin within an already shown publisher.
        for requireNewPublisher in [true, false] {
            for index in ordered where result.count < 3 {
                let source = sessions[index]
                let identity = StreamDeliveryIdentity(url: source.playableURL, headers: source.requiredHeaders)
                let origin = source.playableURL.host?.lowercased()
                let publisher = LivePlaybackSourcePolicy.matchPublisher(for: source.legacySource)
                guard !result.contains(where: {
                    let shown = sessions[$0]
                    return StreamDeliveryIdentity(url: shown.playableURL, headers: shown.requiredHeaders) == identity
                        || shown.playableURL.host?.lowercased() == origin
                        || (requireNewPublisher && LivePlaybackSourcePolicy.matchPublisher(for: shown.legacySource) == publisher)
                }) else { continue }
                result.append(index)
            }
        }
        return result
    }

    static func group(for session: StreamSession) -> String {
        let label = session.providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return CuratedStreamSourceCatalog.opaqueDefinition(for: label)?.opaqueLabelPrefix ?? "Broadcasts"
    }
    static func groups(in sessions: [StreamSession]) -> [String] {
        var seen = Set<String>()
        return sessions.map(group).filter { seen.insert($0).inserted }
    }
}
struct SessionRow: View {
    let session: StreamSession
    let displayNumber: Int
    let isActive: Bool
    let isFailed: Bool
    var isCoolingDown = false
    var currentMode: LivePlaybackMode? = nil
    var usesJoinedPresentation = false
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var numberSize: CGFloat = 30

    var body: some View {
        Button(action: action) {
            rowLayout {
              HStack(alignment: .center, spacing: 12) {
                Text("\(displayNumber)")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(isActive && !usesJoinedPresentation ? FottyTheme.textOnAccent : FottyTheme.textSecondary)
                    .frame(width: numberSize, height: numberSize)
                    .background(isActive && !usesJoinedPresentation ? FottyTheme.accent : FottyTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(sourceTitle)
                        .font(usesJoinedPresentation ? .body.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(FottyTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let sourceDescription {
                        Text(sourceDescription)
                            .font(.caption)
                            .foregroundStyle(FottyTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    if isActive {
                        Image(systemName: isFailed || isCoolingDown ? "arrow.clockwise" : "checkmark")
                            .accessibilityHidden(true)
                    }
                    if !usesJoinedPresentation || !isActive || isFailed || isCoolingDown {
                        Text(actionLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(statusColor.opacity(usesJoinedPresentation ? 0 : 0.12))
                .clipShape(Capsule())
            }
            .padding(.horizontal, usesJoinedPresentation ? 16 : 12)
            .padding(.vertical, usesJoinedPresentation ? 14 : 12)
            .frame(minHeight: 56)
            .background(FottyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous)
                    .strokeBorder(
                        usesJoinedPresentation ? .clear : (isActive ? FottyTheme.accent.opacity(0.7) : FottyTheme.border.opacity(0.75)),
                        lineWidth: isActive ? 1.5 : 0.5
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD))
        }
        .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusMD))
        .accessibilityIdentifier("broadcast-source-\(displayNumber)")
        .accessibilityValue(session.providerName)
        .accessibilityLabel([sourceTitle, sourceDescription, actionLabel].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityHint(isFailed || isCoolingDown
            ? "Try this source again"
            : (isActive ? "This source is selected" : "Switch playback to this source"))
    }

    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }

    private var sourceDescription: String? {
        if usesJoinedPresentation {
            return BroadcastSourcePresentation.watchDescription(provider: session.providerName, qualityLabel: session.qualityLabel)
        }
        let description = BroadcastSourcePresentation.description(qualityLabel: session.qualityLabel,
                                               currentMode: isActive ? currentMode : nil)
        let language = usesJoinedPresentation ? SportsTVStation.station(provider: session.providerName)?.language : nil
        let languageTitle = language == nil || language == .any ? nil : language?.title
        let parts = [languageTitle, description].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Only the optional extra-source lane exposes an opaque family label. The
    /// normal provider families keep the neutral numbered broadcast labels.
    private var sourceTitle: String {
        if usesJoinedPresentation {
            return BroadcastSourcePresentation.watchTitle(provider: session.providerName, number: displayNumber)
        }
        let provider = session.providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if StreamPluginProviderMatching.opaqueProviderFamily(provider) != nil {
            return provider
        }
        return "Broadcast \(displayNumber)"
    }

    private var actionLabel: String {
        if isFailed || isCoolingDown { return "Try again" }
        if isActive { return "Selected" }
        return usesJoinedPresentation ? "Switch" : "Select"
    }

    private var statusColor: Color {
        if isActive { return FottyTheme.accent }
        if isFailed || isCoolingDown { return FottyTheme.textSecondary }
        return FottyTheme.textPrimary
    }
}

/// Supplied metadata is a listing, not decoded quality or a capability promise.
/// Only reviewed display terms are copied; raw titles, URLs and diagnostics stay
/// out of the normal picker. Missing metadata adds no generic filler.
enum BroadcastSourcePresentation {
    static func watchTitle(provider: String, number: Int) -> String {
        SportsTVStation.station(provider: provider)?.title ?? "Broadcast \(number)"
    }

    static func watchDescription(provider: String, qualityLabel: String?) -> String? {
        // Codes remain secondary for support. Display metadata comes from our
        // closed station inventory and reviewed tokens, never provider prose.
        var parts: [String] = []
        if StreamPluginProviderMatching.opaqueProviderFamily(provider) != nil { parts.append(provider) }
        let listed = listedMetadata(qualityLabel)
        if let station = SportsTVStation.station(provider: provider), station.language != .any,
           !listed.contains(station.language.title) { parts.append(station.language.title) }
        if !listed.isEmpty { parts.append("Listed: " + listed.joined(separator: " · ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func description(qualityLabel: String?, currentMode: LivePlaybackMode?) -> String? {
        var parts: [String] = []
        if let currentMode { parts.append(currentMode == .native ? "Native player" : "Web player") }
        let listed = listedMetadata(qualityLabel)
        if !listed.isEmpty { parts.append("Listed: \(listed.joined(separator: " · "))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func listedMetadata(_ raw: String?) -> [String] {
        guard let raw, raw.count <= 200,
              !raw.contains("://"), !raw.contains("/"), !raw.contains("@") else { return [] }
        let tokens = raw.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let languages: [String: String] = ["english": "English", "spanish": "Spanish", "french": "French",
            "portuguese": "Portuguese", "german": "German", "italian": "Italian", "hindi": "Hindi",
            "urdu": "Urdu", "arabic": "Arabic", "bengali": "Bengali", "tamil": "Tamil", "telugu": "Telugu",
            "mandarin": "Mandarin", "cantonese": "Cantonese", "japanese": "Japanese", "korean": "Korean",
            "russian": "Russian", "dutch": "Dutch", "turkish": "Turkish", "polish": "Polish"]
        var result: [String] = []
        for token in tokens {
            if let language = languages[token], !result.contains(language) { result.append(language) }
        }
        let words = Set(tokens)
        if !words.isDisjoint(with: ["4k", "uhd"]) { result.append("4K") }
        else if !words.isDisjoint(with: ["1080", "1080p", "fhd"]) || (words.contains("full") && words.contains("hd")) { result.append("Full HD") }
        else if !words.isDisjoint(with: ["hd", "720", "720p"]) { result.append("HD") }
        else if words.contains("sd") { result.append("SD") }
        return result
    }
}
