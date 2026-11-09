import CryptoKit
import Foundation
import Observation
import SwiftData
import UIKit

/// Local persistence/publication evidence, separate from iCloud's transport
/// status. Preparing a widget never proves it rendered or reached another device.
@Observable @MainActor
final class SportsContinuityPresentation {
    var localError: String?
    var widgetWriteFailed = false
}

/// Narrow integration of the sports intent journal with existing local owners.
/// No full-store migration, new polling, source resolution, FPL or alert opt-in.
@MainActor
final class SportsContinuityBridge {
    static let shared = SportsContinuityBridge()
    let presentation = SportsContinuityPresentation()
    private(set) var lastError: String? {
        get { presentation.localError }
        set { presentation.localError = newValue }
    }
    private let defaults: UserDefaults
    private let sync: SportsPreferenceSyncStore
    private let matchday: MyMatchdayStore
    private let catalog: MatchListViewModel
    private let clock: () -> Date
    private let saveContext: (ModelContext) throws -> Void
    private let publishWidget: @MainActor (SportsWidgetSnapshot) -> Bool
    private let writeSportInterest: @MainActor (String, Bool, UserDefaults) throws -> Void
    private let storageAvailable: @MainActor () -> Bool
    private var context: ModelContext?
    private var saveObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var scheduledTask: Task<Void, Never>?
    private var isApplying = false
    private var remoteApplyFailed = false
    private var applied: [String: SportsPreferenceSyncRecord] = [:]
    private var trackedLocalIDs: Set<String>
    private var importedPlanIDs: [String: String]
    private var lastWidget: SportsWidgetSnapshot?
    private let trackingKey = "fotty.sports-sync.bridge.local-intents.v1"
    private let planMappingKey = "fotty.sports-sync.bridge.plan-mappings.v1"
    private let appliedKey = "fotty.sports-sync.bridge.applied.v1"

    init(defaults: UserDefaults = .standard, sync: SportsPreferenceSyncStore? = nil,
         matchday: MyMatchdayStore? = nil, catalog: MatchListViewModel? = nil,
         clock: @escaping () -> Date = Date.init,
         saveContext: @escaping (ModelContext) throws -> Void = { try $0.save() },
         publishWidget: @escaping @MainActor (SportsWidgetSnapshot) -> Bool = { SportsWidgetSnapshotStore.write(snapshot: $0) },
         writeSportInterest: @escaping @MainActor (String, Bool, UserDefaults) throws -> Void = { sport, enabled, defaults in
             try SportsInterestPreferences.setEnabled(sport, enabled: enabled, in: defaults)
         },
         storageAvailable: @escaping @MainActor () -> Bool = { !LocalDataStore.shared.isUsingVolatileFallback }) {
        self.defaults = defaults; self.sync = sync ?? .shared; self.matchday = matchday ?? .shared
        self.catalog = catalog ?? .shared; self.clock = clock; self.saveContext = saveContext; self.publishWidget = publishWidget
        self.writeSportInterest = writeSportInterest
        self.storageAvailable = storageAvailable
        trackedLocalIDs = Set((defaults.stringArray(forKey: trackingKey) ?? []).prefix(SportsSyncValidation.maximumRecords))
        importedPlanIDs = (defaults.dictionary(forKey: planMappingKey) as? [String: String] ?? [:])
            .filter { SportsSyncValidation.text($0.key, maximum: 360) && SportsSyncValidation.text($0.value, maximum: 200) }
        if importedPlanIDs.count > SportsSyncValidation.maximumRecords { importedPlanIDs = [:] }
        if let data = defaults.data(forKey: appliedKey), data.count <= SportsSyncValidation.maximumJournalBytes,
           let decoded = try? JSONDecoder().decode([SportsPreferenceSyncRecord].self, from: data),
           decoded.count <= SportsSyncValidation.maximumRecords {
            for record in decoded where SportsSyncValidation.encode(record) != nil {
                if applied[record.intent.id].map({ record.wins(over: $0) }) ?? true { applied[record.intent.id] = record }
            }
        }
    }

    deinit {
        scheduledTask?.cancel()
        if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    func configure(modelContext: ModelContext) {
        guard requirePersistentStorage(), context == nil, sync.prepareForUse() else { return }
        context = modelContext
        // Only persisted, verified application receipts count as applied. A
        // received journal row may still be waiting for a catalog or a save.
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave,
            object: modelContext, queue: .main) { [weak self] _ in Task { @MainActor in self?.scheduleUpdate() } }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
            object: defaults, queue: .main) { [weak self] _ in Task { @MainActor in self?.scheduleUpdate() } }
        observeOwnedState()
        publishLocalSnapshot()
    }

    func refresh() {
        guard requirePersistentStorage(), sync.prepareForUse() else { return }
        sync.refresh()
        applyChangedRemoteIntents()
        publishLocalSnapshot()
    }

    /// Retry existing local/app-group writes; cloud access still obeys the
    /// unchanged sports-sync opt-in. No source discovery or playback command.
    func retryPendingChanges() {
        lastWidget = nil
        refresh()
    }

    func publishLocalSnapshot() {
        guard requirePersistentStorage(), let context, !isApplying, sync.prepareForUse() else { return }
        // The widget reflects durable local bookmarks even when the optional
        // sync journal cannot accept another intent or apply a remote change.
        defer { publishWidgetSnapshot() }
        if !sync.enabled { remoteApplyFailed = false }
        if sync.enabled {
            applyChangedRemoteIntents()
            // A failed write or a not-yet-reconciled preference must not become
            // a newer local value that overwrites the received remote action.
            let unapplied = sync.records.filter { applied[$0.intent.id] != $0 }
            if remoteApplyFailed || unapplied.contains(where: { $0.intent.kind != .plannedMatch }) {
                return
            }
        }
        let pendingPlans = sync.enabled ? sync.records.filter {
            $0.intent.kind == .plannedMatch && applied[$0.intent.id] != $0
        } : []
        let protectedIntentIDs = Set(pendingPlans.map { $0.intent.id })
        let protectedSavedIDs = Set(pendingPlans.compactMap { importedPlanIDs[$0.intent.id] ?? $0.intent.match?.id })
        do {
            let teams = try context.fetch(FetchDescriptor<FollowedTeamItem>())
            let leagues = try context.fetch(FetchDescriptor<FollowedLeagueItem>())
            var intents = teams.compactMap { team -> SportsPreferenceSyncIntent? in
                let identity = SportsPersonalizationPolicy.identity(for: team)
                let intent = SportsPreferenceSyncIntent.followedTeam(key: identity.id, name: identity.displayName, category: identity.sportCategory)
                return intent.isValid() ? intent : nil
            }
            intents += leagues.compactMap { stored in
                guard let league = SportsPersonalizationPolicy.league(for: stored) else { return nil }
                return .followedCompetition(id: league.id, name: league.name, category: league.sportCategory)
            }
            intents += try SportsInterestPreferences.validatedIDs(in: defaults)
                .filter { SportsSyncValidation.supportedWholeSportIDs.contains($0) }
                .sorted().map(SportsPreferenceSyncIntent.followedSport)
            // No fresh-install defaults are promoted into a newer cloud intent.
            if let onlySelected = defaults.object(forKey: HomeInterestPreferences.onlyShowSelectedKey) as? Bool {
                intents.append(.onlySelectedInterests(onlySelected))
            }
            if let raw = defaults.string(forKey: ViewingPlanDuration.storageKey), ViewingPlanDuration(rawValue: raw) != nil {
                intents.append(.viewingWindow(raw))
            }
            for saved in matchday.savedMatches where !saved.event.isBroadcastChannel && !saved.event.hasCatalogIdentityConflict
                && !protectedSavedIDs.contains(saved.id) {
                if let transportID = importedPlanIDs.first(where: { $0.value == saved.id })?.key,
                   let record = sync.records.first(where: { $0.intent.id == transportID }), !record.removed {
                    // Preserve the sender's transport ID through a receiving
                    // catalog alias without making duplicate synced plans.
                    intents.append(record.intent)
                } else {
                    let intent = SportsPreferenceSyncIntent.plannedMatch(SportsPlannedMatchIdentity(event: saved.event))
                    if intent.isValid() { intents.append(intent) }
                }
            }
            let unique = Dictionary(intents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            guard unique.count <= SportsSyncValidation.maximumRecords else { lastError = "Your local sports setup exceeds the sync limit."; return }
            let currentIDs = Set(unique.keys)
            for id in trackedLocalIDs.subtracting(currentIDs).subtracting(protectedIntentIDs) {
                let result = sync.enabled
                    ? sync.removeFromAppliedSnapshot(intentID: id, expected: applied[id], now: clock())
                    : sync.remove(intentID: id, now: clock())
                if result == .applicationNeeded { acceptArrivedStateBeforeRetry(); return }
                guard result != .storageFull && result != .rejected else { lastError = "A sports preference could not be saved for sync."; return }
                if let record = sync.records.first(where: { $0.intent.id == id && $0.removed }), !markApplied(record) { return }
            }
            for intent in unique.values {
                let result = sync.enabled
                    ? sync.upsertFromAppliedSnapshot(intent, expected: applied[intent.id], now: clock())
                    : sync.upsert(intent, now: clock())
                if result == .applicationNeeded { acceptArrivedStateBeforeRetry(); return }
                guard result != .storageFull && result != .rejected else { lastError = "A sports preference could not be saved for sync."; return }
                if let record = sync.records.first(where: { $0.intent.id == intent.id && $0.intent == intent && !$0.removed }) {
                    guard markApplied(record) else { return }
                }
            }
            trackedLocalIDs = currentIDs.union(trackedLocalIDs.intersection(protectedIntentIDs))
            let tracked = Array(trackedLocalIDs).sorted()
            if defaults.stringArray(forKey: trackingKey) != tracked { defaults.set(tracked, forKey: trackingKey) }
            lastError = nil
        } catch {
            lastError = "Sports preferences could not be read. Your saved setup is unchanged."
        }
    }

    private func acceptArrivedStateBeforeRetry() {
        // Stop the stale snapshot before marking its row or tracking set applied.
        // Domain persistence must accept the new journal state first; the normal
        // coalesced retry then reads a new local snapshot, without force-syncing.
        applyChangedRemoteIntents()
        if sync.enabled, sync.status == .updatesQueued { scheduleUpdate() }
    }

    private func scheduleUpdate() {
        guard requirePersistentStorage(), scheduledTask == nil else { return }
        scheduledTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.scheduledTask = nil
            self.applyChangedRemoteIntents()
            self.publishLocalSnapshot()
        }
    }

    private func observeOwnedState() {
        withObservationTracking {
            _ = sync.records
            _ = sync.status
            _ = sync.enabled
            _ = matchday.contentRevision
            _ = catalog.contentRevision
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.scheduleUpdate()
                self?.observeOwnedState()
            }
        }
    }

    private func applyChangedRemoteIntents() {
        guard requirePersistentStorage(), let context, sync.enabled, sync.status == .updatesQueued, !isApplying else { return }
        let changes = sync.records.filter { applied[$0.intent.id] != $0 }
        guard !changes.isEmpty else {
            // A pending foreign match may become resolvable after a later
            // current catalog receipt, without treating its old snapshot as fresh.
            applyPendingPlans()
            return
        }
        isApplying = true
        remoteApplyFailed = false
        defer { isApplying = false }
        var verifiedFollowIDs = Set<String>()
        // Use the view context so @Query reflects restored follows. Commit any
        // existing editor change first; rollback scopes only this new batch.
        if context.hasChanges {
            do { try saveContext(context) }
            catch {
                remoteApplyFailed = true
                lastError = "Your pending local changes could not be saved. The incoming sports update is waiting."
                return
            }
        }
        do {
            let teams = try context.fetch(FetchDescriptor<FollowedTeamItem>())
            let leagues = try context.fetch(FetchDescriptor<FollowedLeagueItem>())
            for record in changes {
                let intent = record.intent
                switch intent.kind {
                case .followedTeam:
                    guard let name = intent.name, let category = intent.category,
                          SportsTeamIdentity(displayName: name, sportCategory: category, badgeURL: nil).id == intent.key else { continue }
                    let existing = teams.filter { SportsPersonalizationPolicy.identity(for: $0).id == intent.key }
                    if record.removed { existing.forEach { context.delete($0) } }
                    else if existing.isEmpty {
                        let known = SportsTeamIdentity.known(name: name, category: category)
                        context.insert(FollowedTeamItem(key: intent.key, teamName: name, sportCategory: category,
                            badgeURLString: known?.badgeURL?.absoluteString, alertsEnabled: false))
                    }
                case .followedCompetition:
                    guard let league = SportsPersonalizationPolicy.leagues.first(where: { $0.id == intent.key && $0.sportCategory == intent.category }) else { continue }
                    let existing = leagues.filter { SportsPersonalizationPolicy.league(for: $0)?.id == league.id }
                    if record.removed { existing.forEach { context.delete($0) } }
                    else if existing.isEmpty {
                        context.insert(FollowedLeagueItem(id: league.id, leagueName: league.name, sportCategory: league.sportCategory, country: league.country))
                    }
                case .preference, .plannedMatch, .followedSport: break
                }
            }
            if context.hasChanges { try saveContext(context) }
            guard !context.hasChanges else { throw CocoaError(.fileWriteUnknown) }
            // A receipt certifies the actual saved domain state, not merely
            // that a valid-looking transport row was visited in the loop.
            let savedTeams = try context.fetch(FetchDescriptor<FollowedTeamItem>())
            let savedLeagues = try context.fetch(FetchDescriptor<FollowedLeagueItem>())
            for record in changes {
                let intent = record.intent
                switch intent.kind {
                case .followedTeam:
                    guard let name = intent.name, let category = intent.category,
                          SportsTeamIdentity(displayName: name, sportCategory: category, badgeURL: nil).id == intent.key else { continue }
                    let exists = savedTeams.contains { SportsPersonalizationPolicy.identity(for: $0).id == intent.key }
                    if exists != record.removed { verifiedFollowIDs.insert(intent.id) }
                case .followedCompetition:
                    guard SportsPersonalizationPolicy.leagues.contains(where: { $0.id == intent.key && $0.sportCategory == intent.category }) else { continue }
                    let exists = savedLeagues.contains { SportsPersonalizationPolicy.league(for: $0)?.id == intent.key }
                    if exists != record.removed { verifiedFollowIDs.insert(intent.id) }
                case .preference, .plannedMatch, .followedSport: break
                }
            }
        } catch {
            context.rollback()
            remoteApplyFailed = true
            lastError = "An incoming sports preference could not be saved. Your previous setup is unchanged."
            return
        }
        // Each persistence owner verifies its own atomic write. A failed plan
        // stays pending; it is never converted to an invented fixture/source.
        for record in changes {
            switch record.intent.kind {
            case .followedSport:
                do {
                    try writeSportInterest(record.intent.key, !record.removed, defaults)
                    guard SportsInterestPreferences.selectedIDs(in: defaults).contains(record.intent.key) != record.removed else {
                        throw SportsInterestPreferences.StorageError.writeNotVerified
                    }
                } catch {
                    remoteApplyFailed = true
                    lastError = "An incoming sports interest could not be saved. Your previous setup is unchanged."
                    continue
                }
            case .preference:
                if record.removed {
                    let key = record.intent.key == SportsPreferenceSyncIntent.Preference.onlySelectedInterests.rawValue
                        ? HomeInterestPreferences.onlyShowSelectedKey : ViewingPlanDuration.storageKey
                    defaults.removeObject(forKey: key)
                    guard defaults.object(forKey: key) == nil else { remoteApplyFailed = true; continue }
                    _ = markApplied(record)
                    continue
                }
                if record.intent.key == SportsPreferenceSyncIntent.Preference.onlySelectedInterests.rawValue, let flag = record.intent.flag {
                    defaults.set(flag, forKey: HomeInterestPreferences.onlyShowSelectedKey)
                    guard defaults.object(forKey: HomeInterestPreferences.onlyShowSelectedKey) as? Bool == flag else { remoteApplyFailed = true; continue }
                } else if record.intent.key == SportsPreferenceSyncIntent.Preference.viewingWindow.rawValue, let raw = record.intent.name {
                    defaults.set(raw, forKey: ViewingPlanDuration.storageKey)
                    guard defaults.string(forKey: ViewingPlanDuration.storageKey) == raw else { remoteApplyFailed = true; continue }
                }
            case .plannedMatch:
                switch applyPlan(record) {
                case .pending: continue
                case .failed:
                    remoteApplyFailed = true
                    continue
                case .applied: break
                }
            case .followedTeam, .followedCompetition:
                guard verifiedFollowIDs.contains(record.intent.id) else { continue }
            }
            _ = markApplied(record)
        }
    }

    private func applyPendingPlans() {
        for record in sync.records where record.intent.kind == .plannedMatch && applied[record.intent.id] != record {
            switch applyPlan(record) {
            case .applied: _ = markApplied(record)
            case .failed: remoteApplyFailed = true
            case .pending: break
            }
        }
    }

    private enum PlanApplication { case applied, pending, failed }

    private func applyPlan(_ record: SportsPreferenceSyncRecord) -> PlanApplication {
        guard let match = record.intent.match else { return .pending }
        if record.removed {
            let localID = importedPlanIDs[record.intent.id] ?? match.id
            let result = matchday.remove(eventID: localID)
            guard result.errorMessage == nil else { lastError = result.errorMessage; return .failed }
            importedPlanIDs.removeValue(forKey: record.intent.id)
            return savePlanMappings() ? .applied : .failed
        }
        guard catalog.scheduleReceipt(category: match.category, matchID: match.id, at: clock()) != nil else { return .pending }
        let request = StreamPlaybackRequest(matchID: match.id, displayTitle: match.title, homeTeam: match.homeName,
            awayTeam: match.awayName, category: match.category, kickoffDate: match.kickoff, preferredEvent: nil)
        guard let current = CatalogPlaybackIdentity.matchingEvent(for: request, in: catalog.playbackCatalog),
              !current.isBroadcastChannel,
              SportsHandoffIdentity.qualifiers(for: current) == match.squadQualifiers,
              match.competitionID.map({ $0 == (current.competitionID ?? current.cricketFixture?.competitionID) }) ?? true else { return .pending }
        let result = matchday.save(current)
        guard result.errorMessage == nil else { lastError = result.errorMessage; return .failed }
        importedPlanIDs[record.intent.id] = matchday.record(for: current)?.id ?? current.id
        return savePlanMappings() ? .applied : .failed
    }

    private func savePlanMappings() -> Bool {
        if (defaults.dictionary(forKey: planMappingKey) as? [String: String]) != importedPlanIDs {
            defaults.set(importedPlanIDs, forKey: planMappingKey)
        }
        guard (defaults.dictionary(forKey: planMappingKey) as? [String: String]) == importedPlanIDs else {
            lastError = "The matched sports plan could not be recorded. Your local matches are preserved."
            return false
        }
        return true
    }

    @discardableResult
    private func markApplied(_ record: SportsPreferenceSyncRecord) -> Bool {
        if applied[record.intent.id] == record { return true }
        var next = applied
        next[record.intent.id] = record
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard next.count <= SportsSyncValidation.maximumRecords,
              let data = try? encoder.encode(next.values.sorted { $0.intent.id < $1.intent.id }),
              data.count <= SportsSyncValidation.maximumJournalBytes else {
            remoteApplyFailed = true
            lastError = "The sports sync application receipt could not be saved. Your local setup is preserved."
            return false
        }
        defaults.set(data, forKey: appliedKey)
        guard defaults.data(forKey: appliedKey) == data else {
            remoteApplyFailed = true
            lastError = "The sports sync application receipt could not be saved. Your local setup is preserved."
            return false
        }
        applied = next
        return true
    }

    private func publishWidgetSnapshot() {
        guard requirePersistentStorage() else { return }
        let now = clock()
        var badges: [String: (URL?, URL?)] = [:]
        let rows = matchday.savedMatches.prefix(SportsSyncValidation.maximumRecords).compactMap { saved -> SportsWidgetSnapshot.Match? in
            let stored = saved.event
            guard !stored.isBroadcastChannel, !stored.hasCatalogIdentityConflict else { return nil }
            let currentCatalogIsFresh = catalog.scheduleReceipt(category: stored.normalizedCategory,
                matchID: stored.id, at: now) != nil
            let event = currentCatalogIsFresh ? SavedMatchContinuityPolicy.currentEvent(for: saved, in: catalog.playbackCatalog) ?? stored : stored
            var phase: SportsWidgetSnapshot.Phase = .unconfirmed
            var observedAt: Date?
            if VerifiedFixtureTerminalPolicy.state(for: event, at: now) != nil { phase = .finished }
            else if let fixture = event.cricketFixture, fixture.verified {
                if fixture.isLive(at: now) { phase = .live; observedAt = fixture.observedAt }
                else if fixture.status == .scheduled, event.kickoffDate.map({ $0 > now }) == true { phase = .scheduled }
            } else if let fixture = event.sportsFixture, fixture.verified {
                if fixture.isLive(at: now) { phase = .live; observedAt = fixture.observedAt }
                else if fixture.status == .scheduled, event.kickoffDate.map({ $0 > now }) == true { phase = .scheduled }
            } else if let start = event.kickoffDate, start > now { phase = .scheduled }
            else if currentCatalogIsFresh, StreamPluginProviderMatching.hasActiveCatalogSource(event), !event.isPastEstimatedMatchWindow(at: now) { phase = .listed }
            let row = SportsWidgetSnapshot.Match(id: saved.id, homeName: event.homeName, awayName: event.awayName,
                category: event.normalizedCategory, competition: event.cricketFixture?.competitionName ?? event.sportsFixture?.competitionName,
                kickoff: event.kickoffDate, phase: phase, statusObservedAt: observedAt,
                scoreText: nil, scoreObservedAt: nil,
                homeBadgeFile: nil, awayBadgeFile: nil)
            // Saved local sports need not all belong to the widget's reviewed
            // wire contract. Reject an invalid row before it can consume a
            // visible slot, cause badge work or poison valid neighboring rows.
            guard SportsWidgetSnapshot.isValidMatch(row, createdAt: now) else { return nil }
            badges[saved.id] = (event.homeBadgeURL, event.awayBadgeURL)
            return row
        }.sorted { left, right in
            if left.phase == .live && right.phase != .live { return true }
            if right.phase == .live && left.phase != .live { return false }
            return (left.kickoff ?? .distantFuture) < (right.kickoff ?? .distantFuture)
        }
        let bounded = rows.filter { $0.phase != .finished }.prefix(SportsWidgetSnapshot.maximumMatches).map { row in
            let urls = badges[row.id]
            return SportsWidgetSnapshot.Match(id: row.id, homeName: row.homeName, awayName: row.awayName,
                category: row.category, competition: row.competition, kickoff: row.kickoff,
                phase: row.phase, statusObservedAt: row.statusObservedAt, scoreText: row.scoreText, scoreObservedAt: row.scoreObservedAt,
                homeBadgeFile: cachedBadgeFile(for: urls?.0), awayBadgeFile: cachedBadgeFile(for: urls?.1))
        }
        if let previous = lastWidget, previous.matches == bounded, previous.isFresh(at: now) { return }
        let snapshot = SportsWidgetSnapshot(createdAt: now, matches: bounded)
        if publishWidget(snapshot) {
            lastWidget = snapshot
            presentation.widgetWriteFailed = false
        } else {
            presentation.widgetWriteFailed = true
        }
    }

    /// An empty fallback context is not evidence that the owner removed their
    /// follows. Preserve the journal, application receipts and previous widget
    /// until durable storage is available again. Tests can explicitly authorize
    /// their deliberately isolated in-memory containers through this boundary.
    private func requirePersistentStorage() -> Bool {
        guard storageAvailable() else {
            lastError = "Sports continuity is paused while Fotty is using temporary storage. Your saved setup is unchanged."
            return false
        }
        return true
    }

    private func cachedBadgeFile(for url: URL?) -> String? {
        // Reuse only the currently authoritative warm candidate. No new network
        // fetch or a lower-priority cached crest may change a team's identity.
        guard let url, let image = FottyImageCache.shared.image(for: url),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SportsWidgetSnapshot.appGroup) else { return nil }
        let directory = container.appendingPathComponent("SportsBadges", isDirectory: true)
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() + ".png"
        let file = directory.appendingPathComponent(name)
        do {
            if FileManager.default.fileExists(atPath: file.path) { return name }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
            let thumbnail = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48), format: format).image { _ in
                let ratio = min(48 / max(image.size.width, 1), 48 / max(image.size.height, 1))
                let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                image.draw(in: CGRect(x: (48 - size.width) / 2, y: (48 - size.height) / 2, width: size.width, height: size.height))
            }
            guard let data = thumbnail.pngData(), data.count <= 128 * 1024 else { return nil }
            try data.write(to: file, options: .atomic)
            return name
        } catch { return nil }
    }
}
