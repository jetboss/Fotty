import SwiftUI

/// TV uses the same retained-single presentation contract as Home/Matchday.
/// A channel is canonical navigation identity, not a live fixture claim.
@MainActor
enum SportsTVWatchPolicy {
    static func watch(_ event: EventReference, using viewing: ViewingSessionCoordinator,
                      catalog: [EventReference]) {
        watch(event, using: viewing, currentCatalog: { catalog })
    }

    static func watch(_ event: EventReference, using viewing: ViewingSessionCoordinator,
                      currentCatalog: @escaping @MainActor () -> [EventReference]) {
        viewing.watchSingle(event, admission: { requested in
            guard let current = CurrentEventBroadcastPolicy.currentEvent(for: requested, in: currentCatalog()),
                  MatchStartPolicy(event: current).timingAllowsPlayback else { return nil }
            return current
        })
    }
}

/// The guide changes presentation only. Discovery, source order and playback
/// remain owned by the existing catalog and viewing session.
struct SportsTVView: View {
    var isActive = true
    let onWatch: (EventReference) -> Void
    @Environment(ViewingSessionCoordinator.self) private var viewing
    @Environment(LiveScoreService.self) private var scores
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var library = SportsTVLibrary.shared
    @State private var registry = BroadcastRegistryClient.shared
    @State private var discovery = FixtureStreamDiscoveryIndex.shared
    @State private var catalog = MatchListViewModel.shared
    @State private var saved = MyMatchdayStore.shared
    @State private var query = ""
    @State private var filter = SportsTVLibrary.Filter.all
    @State private var day = SportsTVGuidePolicy.Day.today
    @State private var sport = SportsTVGuidePolicy.SportFilter.all
    @State private var selection: GuideSelection?
    @State private var actionError: String?
    @AppStorage(CommentaryPreference.storageKey) private var commentary = CommentaryPreference.english.rawValue

    private struct GuideSelection: Identifiable {
        let station: SportsTVStation
        var entryID: String?
        var id: String { station.id + (entryID ?? "") }
    }
    private var enabled: Bool { discovery.enabledProviderCodes.contains(ReviewedTVPlaylistClient.providerCode) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in content(at: context.date) }
    }

    private func content(at now: Date) -> some View {
        let groups = library.sections(commentary: CommentaryPreference(rawValue: commentary) ?? .english,
            filter: filter, query: "", snapshot: registry.snapshot, at: now)
        let visibleGroups = groups.filter { group in
            group.stations.contains { stationMatches($0, at: now) }
        }
        return NavigationStack {
            GeometryReader { geometry in
                let wide = SportsTVGuideLayout.usesColumns(width: geometry.size.width, typeSize: typeSize)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        guideControls
                        if !enabled {
                            NavigationLink {
                                StreamPluginsSettingsView()
                            } label: { Label("Enable TV sources", systemImage: "tv").frame(minHeight: 44) }
                        }
                        if visibleGroups.isEmpty {
                            ContentUnavailableView {
                                Label(hasNoFavourites ? "Your favourite channels" : "No matching channels",
                                      systemImage: filter == .favourites ? "star" : "magnifyingglass")
                            } description: {
                                Text(hasNoFavourites ? "Tap the star beside a channel to keep it here." : "Try another day, sport, channel or programme.")
                            } actions: {
                                Button("Show all channels") { query = ""; filter = .all; sport = .all }
                                    .frame(minHeight: 44).accessibilityIdentifier("sports-tv-reset")
                            }
                        }
                        ForEach(visibleGroups) { group in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(group.id).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                                    Spacer()
                                    if group.id == "Recently watched" {
                                        Button("Clear") { library.clearRecent() }
                                            .frame(minWidth: 44, minHeight: 44)
                                            .accessibilityLabel("Clear recently watched channels")
                                    }
                                }
                                if wide && day == .today { columnHeadings }
                                ForEach(group.stations.filter {
                                    stationMatches($0, at: now)
                                }) { station in
                                    stationRow(station, wide: wide, at: now)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, wide ? 24 : 16).padding(.vertical, 16)
                }
            }
            .scrollContentBackground(.hidden).background(FottyTheme.background)
            .tint(FottyTheme.accentText)
            .navigationTitle("Sports TV").navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, prompt: "Channels and programmes")
            .refreshable { _ = await registry.refresh() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let pending = viewing.pendingSingleEvent, let message = viewing.resolutionMessage {
                    StreamResolutionPanel(sportCategory: pending.normalizedCategory,
                        competition: SportMotionContext.competition(for: pending), statusMessage: message,
                        subtitle: pending.displayTitle, isMultiStream: false, multiTitles: [],
                        onCancel: { viewing.cancelPendingSingleDiscovery() })
                }
            }
            .sheet(item: guideSelection) { selected in
                guideDetails(selected)
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
            .alert("Couldn't update this programme", isPresented: .init(
                get: { actionError != nil && selection == nil }, set: { if !$0 { actionError = nil } }
            )) { Button("OK") { actionError = nil } } message: { Text(actionError ?? "") }
            .task(id: now) {
                guard isActive, scenePhase == .active, !viewing.expanded else { return }
                _ = await registry.refresh(at: now)
            }
            .task(id: isActive) {
                guard isActive else { return }
                await StreamPluginRegistry.shared.refreshDiscoveryAvailability()
                _ = await registry.refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { viewing.cancelPendingSingleDiscovery() }
                if phase == .active && isActive {
                    Task {
                        await StreamPluginRegistry.shared.refreshDiscoveryAvailability()
                        _ = await registry.refresh()
                    }
                }
            }
            .onChange(of: isActive) { _, active in if !active { viewing.cancelPendingSingleDiscovery() } }
            .onDisappear { viewing.cancelPendingSingleDiscovery() }
        }
        .environment(\.fottyPendingWatchEventID, viewing.pendingSingleEvent?.id)
        .environment(\.fottyStreamLookupBusy, viewing.pendingSingleEvent != nil)
        .environment(\.fottySceneOwnsSingleWatch, true)
        .accessibilityIdentifier("sports-tv")
    }

    private var hasNoFavourites: Bool {
        filter == .favourites && query.isEmpty && !SportsTVStation.all.contains { library.favourites.contains($0.id) }
    }

    private var guideControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if typeSize.isAccessibilitySize {
                dayPicker.pickerStyle(.menu).frame(minHeight: 44)
                sportPicker.pickerStyle(.menu).frame(minHeight: 44)
                channelMenu
            } else {
                dayPicker.pickerStyle(.segmented)
                HStack(spacing: 12) {
                    sportPicker.pickerStyle(.segmented)
                    channelMenu
                }
            }
        }
    }

    private var dayPicker: some View {
        Picker("Guide day", selection: $day) {
            ForEach(SportsTVGuidePolicy.Day.allCases) { Text($0.title).tag($0) }
        }.accessibilityIdentifier("sports-tv-day")
    }

    private var sportPicker: some View {
        Picker("Sport", selection: $sport) {
            ForEach(SportsTVGuidePolicy.SportFilter.allCases) { Text($0.title).tag($0) }
        }.accessibilityIdentifier("sports-tv-sport")
    }

    private var channelMenu: some View {
        Menu {
            Picker("Channels", selection: $filter) {
                ForEach(SportsTVLibrary.Filter.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            if typeSize.isAccessibilitySize {
                Label(filter.rawValue, systemImage: "line.3.horizontal.decrease")
                    .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
            } else {
                Image(systemName: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    .font(.title3).frame(width: 44, height: 44)
            }
        }
        .accessibilityLabel("Channels, \(filter.rawValue)")
        .accessibilityIdentifier("sports-tv-filter")
    }

    private func stationMatches(_ station: SportsTVStation, at now: Date) -> Bool {
        guard SportsTVGuidePolicy.matches(station, sport: sport, snapshot: registry.snapshot, at: now) else { return false }
        return SportsTVGuidePresentationPolicy.matches(station: station, query: query,
            entries: SportsTVGuidePolicy.entries(for: station, snapshot: registry.snapshot, at: now, day: day, sport: sport))
    }

    private var columnHeadings: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("Channel").frame(width: SportsTVGuideLayout.channelWidth, alignment: .leading)
            Text("On now").frame(maxWidth: .infinity, alignment: .leading)
            Text("Next").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 16)
        .accessibilityHidden(true)
    }

    private func stationRow(_ station: SportsTVStation, wide: Bool, at now: Date) -> some View {
        let entries = SportsTVGuidePresentationPolicy.visibleEntries(
            SportsTVGuidePolicy.entries(for: station, snapshot: registry.snapshot, at: now, day: day, sport: sport),
            station: station, query: query)
        let current = entries.first { $0.isOnNow(at: now) }
        let upcoming = entries.filter { $0.start > now }
        return Group {
            if day == .today {
                SportsTVGuideStationRow(usesColumns: wide) {
                    stationIdentity(station, vertical: wide)
                } current: {
                    if let current { programme(current, station: station, at: now) }
                    else { channelFallback(station, message: !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "No current programme matches this search"
                        : (sport == .all ? "Programme guide unavailable" : "No \(sport.rawValue) programme listed now")) }
                } next: {
                    if let next = upcoming.first { programme(next, station: station, at: now) }
                    else { emptyProgramme(query.isEmpty ? "No later programme listed" : "No matching programme listed") }
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    stationIdentity(station, vertical: false)
                    if upcoming.isEmpty { emptyProgramme("Tomorrow’s programmes aren’t listed yet") }
                    ForEach(upcoming) { programme($0, station: station, at: now) }
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(FottyTheme.surface, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sports-tv-station-\(station.id)")
    }

    private func stationIdentity(_ station: SportsTVStation, vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        return layout {
            Button { selection = .init(station: station) } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "tv").font(.title3).foregroundStyle(FottyTheme.accentText)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(station.title).font(.headline).foregroundStyle(FottyTheme.textPrimary)
                        if station.language != .any {
                            Text(station.language.title).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain).accessibilityLabel("\(station.title), full programme guide")
            Button { library.toggleFavourite(station.id) } label: {
                Image(systemName: library.favourites.contains(station.id) ? "star.fill" : "star")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(library.favourites.contains(station.id) ? "Remove \(station.title) from favourites" : "Favourite \(station.title)")
        }
    }

    private func programme(_ entry: SportsTVGuidePolicy.Entry, station: SportsTVStation, at now: Date,
                           details: Bool = false) -> some View {
        let event = linkedEvent(entry, station: station, at: now)
        return VStack(alignment: .leading, spacing: 10) {
            if details {
                programmeLabel(entry, event: event, at: now)
            } else {
                Button { selection = .init(station: station, entryID: entry.id) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        programmeLabel(entry, event: event, at: now)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).padding(.top, 5)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel([SportsTVProgrammeLabel.timing(entry, at: now), event?.displayTitle ?? entry.title, programmeDetail(event, at: now)].compactMap { $0 }.joined(separator: ", "))
                .accessibilityHint("Opens programme details")
            }
            if let event {
                MatchStartControls(event: event,
                    status: MatchStartPolicy.currentStatus(for: event, scores: scores, now: now),
                    onWatch: { watchProgramme(entry, station: station) },
                    onCheckStreams: { watchProgramme(entry, station: station) },
                    reminderAdmission: {
                        let current = linkedEvent(entry, station: station, at: Date())
                        if current == nil { actionError = "The guide has changed. Refresh it before setting a reminder." }
                        return current
                    }, compact: true) { EmptyView() }
                if entry.isOnNow(at: now), !SportsTVGuidePresentationPolicy.offersMatchWatch(event,
                    status: MatchStartPolicy.currentStatus(for: event, scores: scores, now: now), at: now) {
                    watchChannel(station)
                }
                if details {
                    Button {
                        guard let current = linkedEvent(entry, station: station, at: Date()) else {
                            actionError = "The guide has changed. Refresh it before saving this match."; return
                        }
                        actionError = saved.toggle(current).errorMessage
                    } label: {
                        Label(saved.contains(event: event) ? "Remove from My Matchday" : "Save to My Matchday",
                              systemImage: saved.contains(event: event) ? "bookmark.fill" : "bookmark")
                            .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered).accessibilityIdentifier("sports-tv-programme-save")
                    CurrentSportsMatchContextView(event: event)
                }
            } else if entry.isOnNow(at: now) || details {
                // A schedule row is not authority to attach this channel to a
                // fixture. Be explicit that this action tunes the channel.
                watchChannel(station)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sports-tv-programme-\(entry.id)")
    }

    private func programmeLabel(_ entry: SportsTVGuidePolicy.Entry, event: EventReference?, at now: Date) -> some View {
        SportsTVProgrammeLabel(title: event?.displayTitle ?? entry.title,
            timing: SportsTVProgrammeLabel.timing(entry, at: now),
            detail: programmeDetail(event, at: now), progress: entry.progress(at: now))
    }

    private func programmeDetail(_ event: EventReference?, at now: Date) -> String? {
        guard let event else { return nil }
        let competition = event.sportsFixture?.competitionName ?? event.cricketFixture?.competitionName
        if event.normalizedCategory == "football", !WatchingSpoilerProtection.shared.protects(event),
           let score = scores.scoreForMatch(home: event.homeName, away: event.awayName, near: event.kickoffDate) {
            let state = MatchdayEventStatePolicy.section(for: event, at: now,
                status: MatchStartPolicy.currentStatus(for: event, scores: scores, now: now))
            let qualifier = state == .live ? (scores.scoreStatusQualifier ?? score.minute ?? score.status.displayText) : "Last checked score"
            return "\(score.homeGoals)–\(score.awayGoals) · \(qualifier)"
        }
        return competition
    }

    private func linkedEvent(_ entry: SportsTVGuidePolicy.Entry, station: SportsTVStation, at now: Date) -> EventReference? {
        SportsTVGuidePolicy.linkedEvent(for: entry, station: station, snapshot: registry.snapshot,
            catalog: catalog.playbackAdmissionCatalog, at: now)
    }

    private func watchProgramme(_ entry: SportsTVGuidePolicy.Entry, station: SportsTVStation) {
        guard viewing.pendingSingleEvent == nil else { return }
        guard let event = linkedEvent(entry, station: station, at: Date()),
              MatchStartPolicy(event: event, status: MatchStartPolicy.currentStatus(for: event, scores: scores)).timingAllowsPlayback else {
            actionError = "The guide has changed. Refresh it and choose the programme again."; return
        }
        dismissGuide()
        onWatch(event)
    }

    private func watchChannel(_ station: SportsTVStation) -> some View {
        Button {
            guard viewing.pendingSingleEvent == nil, canWatch(station) else { return }
            dismissGuide(); onWatch(station.event)
        } label: {
            PendingWatchLabel(title: "Watch channel", symbol: "play.fill", isPending: viewing.pendingSingleEvent?.id == station.event.id)
                .frame(minHeight: 44)
        }
        .buttonStyle(.borderedProminent).tint(FottyTheme.accent).foregroundStyle(FottyTheme.textOnAccent)
        .disabled(!canWatch(station) || viewing.pendingSingleEvent != nil)
        .accessibilityLabel("Watch channel \(station.title)")
        .accessibilityValue(viewing.pendingSingleEvent?.id == station.event.id ? "Opening broadcast" : "")
    }

    private func channelFallback(_ station: SportsTVStation, message: String = "Programme guide unavailable") -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Watch channel").font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            watchChannel(station)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyProgramme(_ message: String) -> some View {
        Text(message).font(.subheadline).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func guideDetails(_ selected: GuideSelection) -> some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let entries = SportsTVGuidePolicy.entries(for: selected.station, snapshot: registry.snapshot, at: context.date)
                let visible = entries.filter { selected.entryID == nil || $0.id == selected.entryID }
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let actionError {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(actionError).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                                Button("Dismiss") { self.actionError = nil }.frame(minHeight: 44)
                            }.accessibilityIdentifier("sports-tv-guide-action-error")
                        }
                        if visible.isEmpty {
                            channelFallback(selected.station, message: selected.entryID == nil
                                ? "Programme guide unavailable" : "This programme is no longer in the guide")
                        } else if selected.entryID == nil {
                            // Full station guide always retains direct channel access,
                            // regardless of the selected day or fixture availability.
                            watchChannel(selected.station)
                        }
                        ForEach(visible) { entry in
                            programme(entry, station: selected.station, at: context.date, details: true)
                            Divider()
                        }
                    }
                    .padding(20).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
                }
                .background(FottyTheme.background)
            }
            .navigationTitle(selected.station.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismissGuide() } } }
        }
        .tint(FottyTheme.accentText)
        .onChange(of: actionError) { _, message in
            if let message, selection != nil {
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
    }

    private var guideSelection: Binding<GuideSelection?> {
        .init(get: { selection }, set: { next in
            if next == nil { actionError = nil }
            selection = next
        })
    }

    private func dismissGuide() {
        actionError = nil
        selection = nil
    }

    private func canWatch(_ station: SportsTVStation) -> Bool {
        SportsTVStation.canWatchNow(station, discoveryIndex: discovery)
    }
}

@MainActor
enum SportsTVGuidePresentationPolicy {
    static func stationMatchesQuery(_ station: SportsTVStation, query: String) -> Bool {
        matchesWords(query, in: [station.title, station.language.title])
    }

    static func visibleEntries(_ entries: [SportsTVGuidePolicy.Entry], station: SportsTVStation,
                               query: String) -> [SportsTVGuidePolicy.Entry] {
        if stationMatchesQuery(station, query: query) { return entries }
        return entries.filter { matchesWords(query, in: [station.title, station.language.title, $0.title]) }
    }

    private static func matchesWords(_ query: String, in fields: [String]) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let searchable = fields.joined(separator: " ")
        return words.allSatisfy { searchable.localizedStandardContains($0) }
    }

    static func matches(station: SportsTVStation, query: String, entries: [SportsTVGuidePolicy.Entry]) -> Bool {
        stationMatchesQuery(station, query: query) || !visibleEntries(entries, station: station, query: query).isEmpty
    }

    static func offersMatchWatch(_ event: EventReference, status: FootballMatch.MatchStatus?, at now: Date,
                                 discoveryIndex: FixtureStreamDiscoveryIndex? = nil,
                                 catalogIndex: FixtureCatalogAvailabilityIndex? = nil) -> Bool {
        let policy = MatchStartPolicy(event: event, now: now, status: status, discoveryIndex: discoveryIndex)
        let lookup = FixtureSourceLookupPresentation.state(for: event, at: now, status: status,
            discoveryIndex: discoveryIndex, catalogIndex: catalogIndex)
        return MatchRowInlineStatus.hasPlaybackAction(policy: policy, hasWatch: true, hasAlternate: false, lookup: lookup)
    }
}

enum SportsTVGuideLayout {
    static let channelWidth: CGFloat = 170
    static func usesColumns(width: CGFloat, typeSize: DynamicTypeSize) -> Bool {
        width >= 800 && !typeSize.isAccessibilitySize
    }
}

/// Shared native layout, also rendered by the local accessibility checks.
struct SportsTVGuideStationRow<Station: View, Current: View, Next: View>: View {
    let usesColumns: Bool
    @ViewBuilder let station: () -> Station
    @ViewBuilder let current: () -> Current
    @ViewBuilder let next: () -> Next

    var body: some View {
        if usesColumns {
            HStack(alignment: .top, spacing: 16) {
                station().frame(width: SportsTVGuideLayout.channelWidth, alignment: .leading)
                current().frame(maxWidth: .infinity, alignment: .leading)
                next().frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                station()
                current()
                Divider()
                next()
            }
        }
    }
}

struct SportsTVProgrammeLabel: View {
    let title: String
    let timing: String
    var detail: String?
    var progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(timing).font(.caption.weight(.semibold)).foregroundStyle(FottyTheme.accentText)
                .fixedSize(horizontal: false, vertical: true)
            Text(title).font(.headline).foregroundStyle(FottyTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let progress {
                ProgressView(value: progress).tint(FottyTheme.accentText)
                    .accessibilityLabel("Scheduled programme progress")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    static func timing(_ entry: SportsTVGuidePolicy.Entry, at now: Date, calendar: Calendar = .current) -> String {
        let start = entry.start.formatted(date: calendar.isDate(entry.start, inSameDayAs: now) ? .omitted : .abbreviated,
                                          time: .shortened)
        let interval = entry.end.map { "\(start) – \($0.formatted(date: .omitted, time: .shortened))" } ?? start
        return entry.isOnNow(at: now) ? "On now · \(interval)" : interval
    }
}

struct SportsPlaybackPreferencesView: View {
    @AppStorage(CommentaryPreference.storageKey) private var commentary = CommentaryPreference.english.rawValue
    @AppStorage(WatchingSpoilerProtection.preferenceKey) private var spoilerSafe = false
    var body: some View {
        Form {
            Section {
                Picker("Preferred language", selection: $commentary) {
                    ForEach(CommentaryPreference.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } header: { Text("Commentary") } footer: {
                Text("Automatic selection prefers a known matching language. Other streams remain available.")
            }
            Section {
                Toggle("Hide scores & goal alerts", isOn: $spoilerSafe)
            } header: { Text("While watching") } footer: {
                Text("Hide external scores and pause Fotty goal alerts for the match you’re watching. The broadcaster’s own scoreboard stays visible.")
            }
        }
        .navigationTitle("Playback preferences").navigationBarTitleDisplayMode(.inline)
        .onChange(of: spoilerSafe) { _, enabled in WatchingSpoilerProtection.shared.enabled = enabled }
        .onAppear { WatchingSpoilerProtection.shared.enabled = spoilerSafe }
        .tint(FottyTheme.accentText)
    }
}
