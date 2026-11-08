import SwiftUI

enum MatchActionAccessibility {
    static func playbackLabel(title: String, eventTitle: String, isChannel: Bool, isRetry: Bool) -> String {
        let action = isChannel && !isRetry ? "Watch channel" : title
        return "\(action) \(eventTitle)"
    }
}

/// Presentation ownership is separate from the notification store's queue. A
/// reused row, later tap or consumed Undo cannot publish an older confirmation.
@MainActor
struct InlineReminderFeedbackState {
    enum Restoration {
        case enable(AnalyticalDataEngine.EventReference)
        case unavailable(MatchReminderStore.Result)
    }

    /// A cancelled reminder has no store record for catalog reconciliation to
    /// update. Undo must re-admit the live row, never replay its saved schedule.
    static func restoration(previous: MatchReminderRecord, currentEvent: AnalyticalDataEngine.EventReference,
                            status: FootballMatch.MatchStatus? = nil, now: Date = Date()) -> Restoration {
        guard let current = SavedMatchContinuityPolicy.currentEvent(for: previous.snapshot, in: [currentEvent]) else {
            return .unavailable(.failed)
        }
        let policy = MatchStartPolicy(event: current, now: now, status: status)
        guard !policy.isStopped else { return .unavailable(.failed) }
        guard let start = policy.upcomingStart, start.timeIntervalSince(now) > MatchStartPolicy.reminderLead else {
            return .unavailable(.tooLate)
        }
        return .enable(current)
    }

    struct Operation: Equatable {
        let id = UUID()
        let eventID: String
        let previousRecord: MatchReminderRecord?
        let startingIntentRevision: Int
        let enablesReminder: Bool
        let isUndo: Bool
    }

    struct Notice: Identifiable {
        let operation: Operation
        let expectedRecord: MatchReminderRecord?
        let intentRevision: Int
        var id: UUID { operation.id }
        var eventID: String { operation.eventID }
        var isEnabled: Bool { expectedRecord != nil }
        var canUndo: Bool {
            !operation.isUndo && (operation.previousRecord != nil) != isEnabled
        }
        var title: String { isEnabled ? "Reminder set" : "Reminder off" }
        var detail: String {
            isEnabled ? "5 minutes before. Saved to My Matchday."
                : "The match stays saved in My Matchday."
        }
    }

    private(set) var eventID: String?
    private(set) var operation: Operation?
    private(set) var notice: Notice?
    private(set) var failure: MatchReminderStore.Result?

    mutating func begin(eventID: String, previousRecord: MatchReminderRecord?, intentRevision: Int, enablesReminder: Bool,
                        isUndo: Bool = false) -> Operation {
        reset(eventID: eventID)
        let next = Operation(eventID: eventID, previousRecord: previousRecord,
            startingIntentRevision: intentRevision,
            enablesReminder: enablesReminder, isUndo: isUndo)
        operation = next
        return next
    }

    mutating func complete(_ completed: Operation, result: MatchReminderStore.Result,
                           currentRecord: MatchReminderRecord?, intentRevision: Int) {
        guard eventID == completed.eventID, operation == completed else { return }
        operation = nil
        guard intentRevision == completed.startingIntentRevision + 1 else { return }
        switch result {
        case .scheduled where completed.enablesReminder && currentRecord?.id == completed.eventID,
             .cancelled where !completed.enablesReminder && currentRecord == nil:
            notice = Notice(operation: completed, expectedRecord: currentRecord, intentRevision: intentRevision)
        case .scheduled, .cancelled:
            // Another control/store revision superseded this request. It is not
            // this row's successful action and must not acquire an Undo button.
            break
        case .denied, .tooLate, .limitReached, .failed:
            failure = result
        }
    }

    mutating func consumeUndo(noticeID: UUID, eventID: String,
                              currentRecord: MatchReminderRecord?, intentRevision: Int) -> Notice? {
        guard let notice, notice.id == noticeID, notice.eventID == eventID, notice.canUndo else { return nil }
        self.notice = nil
        // Reconciliation or another row may have replaced the reminder since
        // this notice appeared. Never reverse a different record's intent.
        guard notice.expectedRecord == currentRecord, notice.intentRevision == intentRevision else { return nil }
        return notice
    }

    mutating func showFailure(_ result: MatchReminderStore.Result, eventID: String) {
        reset(eventID: eventID)
        failure = result
    }

    mutating func invalidateChangedIntent(currentRecord: MatchReminderRecord?, intentRevision: Int) {
        guard let notice else { return }
        if notice.expectedRecord != currentRecord || notice.intentRevision != intentRevision {
            self.notice = nil
        }
    }

    mutating func dismiss(noticeID: UUID) {
        guard notice?.id == noticeID else { return }
        notice = nil
    }

    mutating func reset(eventID: String? = nil) {
        self.eventID = eventID
        operation = nil
        notice = nil
        failure = nil
    }
}

/// Only visible countdown rows tick. Distant starts update once a minute;
/// the final five minutes update each second, with no data/provider requests.
struct MatchCountdownSchedule: TimelineSchedule {
    let kickoff: Date?
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
        AnySequence(sequence(first: startDate) { current in
            let remaining = kickoff?.timeIntervalSince(current) ?? 0
            let step: TimeInterval
            if remaining > 300 { step = min(60, remaining - 300) }
            else if remaining > 0, mode != .lowFrequency { step = 1 }
            else { step = 60 }
            return current.addingTimeInterval(max(1, step))
        })
    }
}

/// Keeps the action beside the information without duplicating stateful controls
/// in separate ViewThatFits branches. Large text or genuinely narrow space can
/// stack; ordinary live rows never reserve a second strip beneath the teams.
struct MatchRowLayout: Layout {
    struct Cache {
        fileprivate var width: CGFloat?
        fileprivate var measurement: Measurement?
    }

    fileprivate struct Measurement {
        struct Accessory {
            let size: CGSize
            let besideAction: Bool
            let columnWidth: CGFloat
            let columnHeight: CGFloat
        }
        let size: CGSize
        let information: CGSize
        let action: CGSize
        let horizontal: Bool
        let spacing: CGFloat
        var accessory: Accessory? = nil
    }

    var minimumInformationWidth: CGFloat = 150
    var forceStack = false
    var spacing: CGFloat = 12

    static func fitsBeside(width: CGFloat, informationMinimum: CGFloat, actionWidth: CGFloat,
                           spacing: CGFloat = 12, forceStack: Bool = false) -> Bool {
        !forceStack && width >= informationMinimum + spacing + actionWidth
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = Cache()
    }

    private func measurement(_ proposal: ProposedViewSize, _ subviews: Subviews, cache: inout Cache)
        -> Measurement {
        let proposedWidth = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
        if let proposedWidth, cache.width == proposedWidth, let measurement = cache.measurement {
            return measurement
        }
        let idealAction = subviews[1].sizeThatFits(.unspecified)
        let effectiveSpacing = idealAction == .zero ? 0 : spacing
        let width = proposedWidth ?? (minimumInformationWidth + effectiveSpacing + idealAction.width)
        let actionWidth = min(width, idealAction.width)
        if subviews.count == 3 {
            let idealAccessory = subviews[2].sizeThatFits(.unspecified)
            let accessoryWidth = min(width, idealAccessory.width)
            let accessory = subviews[2].sizeThatFits(.init(width: accessoryWidth, height: nil))
            let actionHeight = subviews[1].sizeThatFits(.init(width: actionWidth, height: nil)).height
            let action = CGSize(width: actionWidth, height: actionHeight)
            let inlineWidth = accessory.width + 4 + action.width
            let besideAction = action.width > 0 && Self.fitsBeside(
                width: width, informationMinimum: minimumInformationWidth,
                actionWidth: inlineWidth, spacing: spacing, forceStack: forceStack)
            let columnWidth = besideAction ? inlineWidth : max(accessory.width, action.width)
            let columnHeight = besideAction ? max(accessory.height, action.height) : accessory.height + action.height
            let columnSpacing = columnWidth > 0 ? spacing : 0
            let horizontal = Self.fitsBeside(width: width, informationMinimum: minimumInformationWidth,
                actionWidth: columnWidth, spacing: columnSpacing, forceStack: forceStack)
            let informationWidth = horizontal ? width - columnSpacing - columnWidth : width
            let information = subviews[0].sizeThatFits(.init(width: informationWidth, height: nil))
            let height = horizontal ? max(information.height, columnHeight)
                : information.height + columnSpacing + columnHeight
            let measured = Measurement(size: CGSize(width: width, height: height), information: information,
                action: action, horizontal: horizontal, spacing: columnSpacing,
                accessory: .init(size: accessory, besideAction: besideAction,
                                 columnWidth: columnWidth, columnHeight: columnHeight))
            cache.width = width
            cache.measurement = measured
            return measured
        }
        let horizontal = Self.fitsBeside(width: width, informationMinimum: minimumInformationWidth,
            actionWidth: actionWidth, spacing: effectiveSpacing, forceStack: forceStack)
        let informationWidth = horizontal ? width - effectiveSpacing - actionWidth : width
        let information = subviews[0].sizeThatFits(.init(width: informationWidth, height: nil))
        let actionHeight = subviews[1].sizeThatFits(.init(width: actionWidth, height: nil)).height
        let action = CGSize(width: actionWidth, height: actionHeight)
        let height = horizontal ? max(information.height, action.height) : information.height + effectiveSpacing + action.height
        let measurement = Measurement(
            size: CGSize(width: width, height: height),
            information: information,
            action: action,
            horizontal: horizontal,
            spacing: effectiveSpacing
        )
        cache.width = width
        cache.measurement = measurement
        return measurement
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard subviews.count == 2 || subviews.count == 3 else { return .zero }
        return measurement(proposal, subviews, cache: &cache).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard subviews.count == 2 || subviews.count == 3 else { return }
        let result = measurement(.init(width: bounds.width, height: nil), subviews, cache: &cache)
        if let accessory = result.accessory {
            let informationWidth = result.horizontal ? bounds.width - result.spacing - accessory.columnWidth : bounds.width
            let informationY = result.horizontal ? bounds.midY - result.information.height / 2 : bounds.minY
            let columnX = result.horizontal ? bounds.maxX - accessory.columnWidth : bounds.minX
            let columnY = result.horizontal ? bounds.midY - accessory.columnHeight / 2
                : informationY + result.information.height + result.spacing
            subviews[0].place(at: CGPoint(x: bounds.minX, y: informationY), anchor: .topLeading,
                proposal: .init(width: informationWidth, height: result.information.height))
            subviews[1].place(at: CGPoint(x: columnX + accessory.columnWidth - result.action.width,
                y: accessory.besideAction ? bounds.midY - result.action.height / 2 : columnY + accessory.size.height),
                anchor: .topLeading, proposal: .init(result.action))
            subviews[2].place(at: CGPoint(x: accessory.besideAction ? columnX : columnX + accessory.columnWidth - accessory.size.width,
                y: accessory.besideAction ? informationY : columnY),
                anchor: .topLeading, proposal: .init(accessory.size))
            return
        }
        let informationWidth = result.horizontal ? bounds.width - result.spacing - result.action.width : bounds.width
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY + (result.horizontal ? (bounds.height - result.information.height) / 2 : 0)),
            anchor: .topLeading, proposal: .init(width: informationWidth, height: result.information.height))
        subviews[1].place(at: CGPoint(x: result.horizontal ? bounds.maxX - result.action.width : bounds.minX,
            y: result.horizontal ? bounds.midY - result.action.height / 2 : bounds.minY + result.information.height + result.spacing),
            anchor: .topLeading, proposal: .init(result.action))
    }
}

struct MatchStartControls<Information: View>: View {
    let event: AnalyticalDataEngine.EventReference
    var status: FootballMatch.MatchStatus? = nil
    var now: Date? = nil
    var onWatch: (() -> Void)? = nil
    var onCheckStreams: (() -> Void)? = nil
    var alternateActionTitle: String? = nil
    var showsReminder = true
    var compact = false
    var minimumInformationWidth: CGFloat? = nil
    private let rowActions: CatalogMatchActionsMenu?
    private let information: Information
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.fottyStreamLookupBusy) private var streamLookupBusy
    @Environment(\.fottySceneOwnsSingleWatch) private var sceneOwnsSingleWatch
    @Environment(\.fottyPendingWatchEventID) private var pendingWatchEventID
    @ScaledMetric(relativeTo: .body) private var defaultMinimumInformationWidth: CGFloat = 150
    @State private var reminders = MatchReminderStore.shared
    @State private var feedback = MatchPlaybackFeedback.shared
    @State private var reminderFeedback = InlineReminderFeedbackState()
    @FocusState private var reminderButtonFocused: Bool
    @AccessibilityFocusState private var reminderButtonAccessibilityFocused: Bool

    init(event: AnalyticalDataEngine.EventReference, status: FootballMatch.MatchStatus? = nil,
         now: Date? = nil,
         onWatch: (() -> Void)? = nil, alternateActionTitle: String? = nil,
         onCheckStreams: (() -> Void)? = nil,
         showsReminder: Bool = true, compact: Bool = false,
         minimumInformationWidth: CGFloat? = nil,
         rowActions: CatalogMatchActionsMenu? = nil,
         @ViewBuilder information: () -> Information) {
        self.event = event
        self.status = status
        self.now = now
        self.onWatch = onWatch
        self.onCheckStreams = onCheckStreams
        self.alternateActionTitle = alternateActionTitle
        self.showsReminder = showsReminder
        self.compact = compact
        self.minimumInformationWidth = minimumInformationWidth
        self.rowActions = rowActions
        self.information = information()
    }

    var body: some View {
        // Keep the row lifetime stable when a system permission prompt changes
        // scenePhase and swaps the countdown's active/inactive presentation.
        VStack(alignment: .leading, spacing: 0) {
            if let now {
                controls(at: now)
            } else if scenePhase == .active {
                TimelineView(MatchCountdownSchedule(kickoff: event.isBroadcastChannel ? nil : event.kickoffDate)) { context in
                    controls(at: context.date)
                }
            } else {
                controls(at: Date())
            }
        }
        .onChange(of: reminderEventID) { _, newID in reminderFeedback.reset(eventID: newID) }
        .onChange(of: reminders.intentRevision(for: reminderEventID)) { _, revision in
            reminderFeedback.invalidateChangedIntent(currentRecord: reminderRecord, intentRevision: revision)
        }
        .onChange(of: reminderRecord) { _, record in
            reminderFeedback.invalidateChangedIntent(currentRecord: record,
                intentRevision: reminders.intentRevision(for: reminderEventID))
        }
        .onDisappear { reminderFeedback.reset() }
    }

    private func controls(at now: Date) -> some View {
        let policy = MatchStartPolicy(event: event, now: now, status: status)
        // A countdown is secondary information, not an action competing with
        // names for horizontal space. Keep the one reminder owner beside the
        // information; playable rows retain their side-by-side Watch control.
        let inlineStatus = Information.self != EmptyView.self && !hasPlaybackAction(policy)
        return VStack(alignment: .leading, spacing: 5) {
            if Information.self != EmptyView.self {
                MatchRowLayout(minimumInformationWidth: inlineStatus ? min(minimumInformationWidth ?? defaultMinimumInformationWidth, defaultMinimumInformationWidth + 50) : (minimumInformationWidth ?? defaultMinimumInformationWidth),
                               forceStack: typeSize.isAccessibilitySize) {
                    VStack(alignment: .leading, spacing: 5) {
                        if let rowActions, !inlineStatus {
                            HStack(alignment: .top, spacing: 4) {
                                information.frame(maxWidth: .infinity, alignment: .leading)
                                rowActions
                            }
                        } else {
                            information
                        }
                        if inlineStatus {
                            statusInformation(policy: policy)
                        }
                    }
                    if compact || inlineStatus {
                        HStack(spacing: 6) {
                            compactActions(policy: policy, showsStatus: !inlineStatus)
                        }
                    } else {
                        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                            actions(policy: policy)
                        }
                    }
                    if inlineStatus, let rowActions {
                        // The layout keeps wide rows unchanged, but at narrow
                        // widths shares a trailing column with the one existing
                        // reminder control instead of squeezing team names.
                        rowActions
                    }
                }
            } else if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { actions(policy: policy) }
            } else {
                HStack(spacing: 10) { actions(policy: policy) }
            }
            if feedback.notReadyIDs.contains(event.id), policy.canAttemptPlayback {
                Text("No stream found yet. You can try again.")
                    .font(FottyTheme.typeCaption)
                    .foregroundStyle(FottyTheme.textSecondary)
            }
            if let notice = reminderFeedback.notice, notice.eventID == reminderEventID {
                FottyInlineFeedback(title: notice.title, detail: notice.detail,
                    symbol: notice.isEnabled ? "bell.badge" : "bell.slash",
                    onUndo: notice.canUndo ? { undoReminder(notice) } : nil,
                    onDismiss: { dismissReminderNotice(notice.id) })
                    .id(notice.id)
                    .transition(reduceMotion ? .identity : .opacity)
                    .accessibilityIdentifier("match-reminder-confirmation-\(event.id)")
            }
            if reminderFeedback.eventID == reminderEventID, let failure = reminderFeedback.failure {
                Text(failure.message)
                    .font(FottyTheme.typeCaption)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("match-reminder-message")
            }
            if reminderFeedback.eventID == reminderEventID, reminderFeedback.failure == .denied {
                Button("Open notification settings") {
                    guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.accentText)
                .frame(minHeight: 44)
            }
        }
    }

    private func hasPlaybackAction(_ policy: MatchStartPolicy) -> Bool {
        (onWatch != nil && (policy.canAttemptPlayback || (alternateActionTitle != nil && policy.timingAllowsPlayback)))
            || lookupState()?.canTriggerLookup == true
    }

    private func lookupState() -> FixtureSourceLookupPresentation.State? {
        guard onCheckStreams != nil else { return nil }
        // The countdown may retain its scheduled tick while a newer provider
        // completion invalidates the row. Read source receipts at render time.
        return FixtureSourceLookupPresentation.state(for: event,
            at: HomeSportsDiscovery.automatedClockDate ?? Date(), status: status)
    }

    private var isPendingWatch: Bool { pendingWatchEventID == event.id }

    private func watchLabel(_ title: String, symbol: String) -> some View {
        PendingWatchLabel(title: title, symbol: symbol, isPending: isPendingWatch)
    }

    @ViewBuilder
    private func checkStreamsButton(_ state: FixtureSourceLookupPresentation.State) -> some View {
        if state.canTriggerLookup {
            Button {
                guard sceneOwnsSingleWatch || lookupState()?.canTriggerLookup == true else { return }
                onCheckStreams?()
            } label: {
                watchLabel(state.title, symbol: state.symbol)
                    .font(FottyTheme.typeMeta.weight(.semibold))
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(FottyTheme.accent, in: Capsule())
            }
            .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusFull))
            .disabled(streamLookupBusy)
            .accessibilityLabel(state.accessibilityLabel(matchTitle: event.displayTitle))
            .accessibilityValue(isPendingWatch ? "Opening broadcast" : "")
            .accessibilityHint(state.accessibilityHint)
            .accessibilityIdentifier("match-start-check-streams-\(event.id)")
        } else {
            sourceAvailabilityStatus(state)
        }
    }

    private func sourceAvailabilityStatus(_ state: FixtureSourceLookupPresentation.State) -> some View {
        HStack(spacing: 6) {
            if state.isChecking { ProgressView().controlSize(.small) }
            Text(state.statusTitle).fixedSize(horizontal: false, vertical: true)
        }
        .font(FottyTheme.typeMeta)
        .foregroundStyle(FottyTheme.textSecondary)
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel(matchTitle: event.displayTitle))
        .accessibilityHint(state.accessibilityHint)
        .accessibilityIdentifier("match-start-source-status-\(event.id)")
    }

    @ViewBuilder
    private func statusInformation(policy: MatchStartPolicy) -> some View {
        if let state = lookupState(), !state.canWatch {
            sourceAvailabilityStatus(state)
        } else {
          Text(policy.title)
            .font(FottyTheme.typeMeta)
            .monospacedDigit()
            .foregroundStyle(FottyTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(policy.upcomingStart != nil ? "Scheduled \(policy.title.lowercased())" : policy.title)
            .accessibilityIdentifier("match-start-countdown-\(event.id)")
        }
    }

    @ViewBuilder
    private func compactActions(policy: MatchStartPolicy, showsStatus: Bool = true) -> some View {
        let offersAlternate = alternateActionTitle != nil && policy.timingAllowsPlayback
        let actionable = (policy.canAttemptPlayback || offersAlternate) && onWatch != nil
        let retry = feedback.notReadyIDs.contains(event.id) && policy.canAttemptPlayback && actionable
        let title = offersAlternate ? (alternateActionTitle ?? "Options") : (retry ? "Retry" : "Watch")

        if actionable {
            Button {
                if !sceneOwnsSingleWatch {
                    let current = MatchStartPolicy(event: event, status: status)
                    guard current.canAttemptPlayback || (alternateActionTitle != nil && current.timingAllowsPlayback) else { return }
                }
                onWatch?()
            } label: {
                watchLabel(title, symbol: offersAlternate ? "tv" : (retry ? "arrow.clockwise" : "play.fill"))
                    .font(FottyTheme.typeMeta.weight(.semibold))
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(FottyTheme.accent, in: Capsule())
            }
            .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusFull))
            .disabled(streamLookupBusy)
            .accessibilityLabel(MatchActionAccessibility.playbackLabel(
                title: title, eventTitle: event.displayTitle, isChannel: event.isBroadcastChannel, isRetry: retry
            ))
            .accessibilityValue(isPendingWatch ? "Opening broadcast" : "")
            .accessibilityHint(streamLookupBusy ? "Another stream lookup is in progress. Cancel it to choose a different match."
                : "Checks the listed broadcast. A scheduled start does not guarantee a stream is ready.")
            .accessibilityIdentifier("match-start-play-\(event.id)")
        } else if let lookup = lookupState(), lookup.canTriggerLookup || showsStatus {
            checkStreamsButton(lookup)
        } else if showsStatus {
            Text(policy.title)
                .font(FottyTheme.typeMeta)
                .monospacedDigit()
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: true, vertical: true)
                .frame(minHeight: 44)
                .accessibilityLabel(policy.upcomingStart != nil ? "Scheduled \(policy.title.lowercased())" : policy.title)
                .accessibilityIdentifier("match-start-countdown-\(event.id)")
        }

        if showsReminder, let start = policy.upcomingStart,
           start.timeIntervalSince(policy.now) > MatchStartPolicy.reminderLead || reminderRecord != nil || reminders.busyIDs.contains(reminderEventID) {
            let selected = reminderRecord != nil
            let permissionOff = selected && reminders.permission == .denied
            let needsRetry = selected && reminders.failedIDs.contains(reminderEventID)
            let hasIssue = permissionOff || needsRetry
            let busy = reminders.busyIDs.contains(reminderEventID) || reminderFeedback.operation?.eventID == reminderEventID
            Button {
                updateReminder(selected: selected, permissionOff: permissionOff, needsRetry: needsRetry)
            } label: {
                Group {
                    if busy {
                        ProgressView()
                    } else {
                        Image(systemName: hasIssue ? "bell.slash" : (selected ? "bell.fill" : "bell"))
                    }
                }
                .font(FottyTheme.typeMeta.weight(.semibold))
                .foregroundStyle(FottyTheme.accentText)
                .frame(width: 44, height: 44)
                .background(FottyTheme.surfaceSubtle, in: Circle())
                .contentShape(Circle())
            }
            .buttonStyle(FottyPressButtonStyle(cornerRadius: FottyTheme.radiusFull))
            .disabled(busy)
            .contextMenu {
                if selected {
                    Button("Cancel reminder", systemImage: "bell.slash") {
                        cancelReminder()
                    }
                }
            }
            .accessibilityLabel(hasIssue ? "Restore reminder for \(event.displayTitle)" : (selected ? "Cancel reminder for \(event.displayTitle)" : "Remind me about \(event.displayTitle)"))
            .accessibilityHint(hasIssue ? "Shows how to restore the reminder; use the context menu to cancel it" : (selected ? "Turns off this reminder and keeps the match saved" : "Reminds you five minutes before the scheduled start and saves the match to My Matchday"))
            .accessibilityIdentifier("match-reminder-\(event.id)")
            .focused($reminderButtonFocused)
            .accessibilityFocused($reminderButtonAccessibilityFocused)
        }
    }

    private func updateReminder(selected: Bool, permissionOff: Bool, needsRetry: Bool) {
        guard reminderFeedback.operation?.eventID != reminderEventID else { return }
        if permissionOff {
            reminderFeedback.showFailure(.denied, eventID: reminderEventID)
        } else if selected && !needsRetry {
            cancelReminder()
        } else {
            enableReminder(event)
        }
    }

    private var reminderRecord: MatchReminderRecord? {
        reminders.record(for: event)
    }

    /// The catalog may replace its row ID after a verified provider join. Keep
    /// notification requests and Undo under the user's existing opaque save ID.
    private var reminderEventID: String { reminders.eventForIntent(event).id }

    private func cancelReminder(isUndo: Bool = false) {
        let intentID = reminderEventID
        let operation = reminderFeedback.begin(eventID: intentID, previousRecord: reminderRecord,
            intentRevision: reminders.intentRevision(for: intentID),
            enablesReminder: false, isUndo: isUndo)
        reminders.cancel(for: event)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
            reminderFeedback.complete(operation, result: .cancelled, currentRecord: reminderRecord,
                intentRevision: reminders.intentRevision(for: intentID))
        }
    }

    private func enableReminder(_ reminderEvent: AnalyticalDataEngine.EventReference, isUndo: Bool = false) {
        let intentEvent = reminders.eventForIntent(reminderEvent)
        let operation = reminderFeedback.begin(eventID: intentEvent.id, previousRecord: reminderRecord,
            intentRevision: reminders.intentRevision(for: intentEvent.id),
            enablesReminder: true, isUndo: isUndo)
        Task { @MainActor in
            let result = await reminders.enable(intentEvent)
            let currentRecord = reminders.records.first { $0.id == intentEvent.id }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                reminderFeedback.complete(operation, result: result, currentRecord: currentRecord,
                    intentRevision: reminders.intentRevision(for: intentEvent.id))
            }
        }
    }

    private func undoReminder(_ notice: InlineReminderFeedbackState.Notice) {
        guard let consumed = reminderFeedback.consumeUndo(noticeID: notice.id, eventID: reminderEventID,
            currentRecord: reminderRecord, intentRevision: reminders.intentRevision(for: reminderEventID)) else { return }
        if let previous = consumed.operation.previousRecord {
            switch InlineReminderFeedbackState.restoration(previous: previous, currentEvent: event, status: status) {
            case .enable(let current):
                enableReminder(current, isUndo: true)
            case .unavailable(let result):
                reminderFeedback.showFailure(result, eventID: reminderEventID)
            }
        } else {
            cancelReminder(isUndo: true)
        }
        focusReminderButton()
    }

    private func dismissReminderNotice(_ noticeID: UUID) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
            reminderFeedback.dismiss(noticeID: noticeID)
        }
        focusReminderButton()
    }

    private func focusReminderButton() {
        reminderButtonFocused = true
        reminderButtonAccessibilityFocused = true
    }

    @ViewBuilder
    private func actions(policy: MatchStartPolicy) -> some View {
        let offersAlternate = alternateActionTitle != nil && policy.timingAllowsPlayback
        let actionable = (policy.canAttemptPlayback || offersAlternate) && onWatch != nil
        let retry = feedback.notReadyIDs.contains(event.id) && policy.canAttemptPlayback && actionable
        let isRow = Information.self != EmptyView.self
        let title = offersAlternate ? (alternateActionTitle ?? "Options")
            : retry ? (isRow ? "Retry" : "Not ready · Retry")
            : (isRow && event.isBroadcastChannel && actionable ? "Watch" : policy.title)
        if actionable {
            Button {
                // Scene-owned single Watch acknowledges first and performs the
                // same current admission check before discovery. Other routes
                // keep this existing local guard.
                if !sceneOwnsSingleWatch {
                    let current = MatchStartPolicy(event: event, status: status)
                    guard current.canAttemptPlayback || (alternateActionTitle != nil && current.timingAllowsPlayback) else { return }
                }
                onWatch?()
            } label: {
                watchLabel(title, symbol: offersAlternate ? "tv" : (retry ? "arrow.clockwise" : "play.fill"))
                    .font(FottyTheme.typeMeta.weight(.semibold))
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .accessibilityIdentifier("match-start-action-label")
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(FottyTheme.accent, in: RoundedRectangle(cornerRadius: FottyTheme.radiusSM))
            }
            .buttonStyle(FottyPressButtonStyle())
            .disabled(streamLookupBusy)
            .accessibilityLabel(MatchActionAccessibility.playbackLabel(
                title: title, eventTitle: event.displayTitle, isChannel: event.isBroadcastChannel, isRetry: retry
            ))
            .accessibilityValue(isPendingWatch ? "Opening broadcast" : "")
            .accessibilityHint(streamLookupBusy ? "Another stream lookup is in progress. Cancel it to choose a different match." : offersAlternate
                ? "Opens the preferred available cricket channel. Its current programme is not confirmed."
                : "Checks the listed broadcast. A scheduled start does not guarantee a stream is ready.")
            .accessibilityIdentifier("match-start-play-\(event.id)")
        } else if let lookup = lookupState() {
            checkStreamsButton(lookup)
        } else {
            Label(title, systemImage: policy.upcomingStart != nil ? "clock" : "info.circle")
                .font(FottyTheme.typeMeta)
                .monospacedDigit()
                .foregroundStyle(FottyTheme.textSecondary)
                .accessibilityIdentifier("match-start-countdown-label")
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44)
                .accessibilityLabel(policy.upcomingStart != nil ? "Scheduled \(title.lowercased())" : title)
                .accessibilityIdentifier("match-start-countdown-\(event.id)")
        }

        if showsReminder, let start = policy.upcomingStart,
           start.timeIntervalSince(policy.now) > MatchStartPolicy.reminderLead || reminderRecord != nil || reminders.busyIDs.contains(reminderEventID) {
            let selected = reminderRecord != nil
            let permissionOff = selected && reminders.permission == .denied
            let needsRetry = selected && reminders.failedIDs.contains(reminderEventID)
            let hasIssue = permissionOff || needsRetry
            let busy = reminders.busyIDs.contains(reminderEventID) || reminderFeedback.operation?.eventID == reminderEventID
            Button {
                updateReminder(selected: selected, permissionOff: permissionOff, needsRetry: needsRetry)
            } label: {
                Label(busy ? "Setting…" : (permissionOff ? "Alerts off" : (needsRetry ? "Retry reminder" : (selected ? "Reminder set" : "Remind me"))),
                      systemImage: hasIssue ? "bell.slash" : (selected ? "bell.fill" : "bell"))
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.accentText)
                    .accessibilityIdentifier("match-reminder-label")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(FottyPressButtonStyle())
            .disabled(busy)
            .contextMenu {
                if selected {
                    Button("Cancel reminder", systemImage: "bell.slash") {
                        cancelReminder()
                    }
                }
            }
            .accessibilityLabel(hasIssue ? "Restore reminder for \(event.displayTitle)" : (selected ? "Cancel reminder for \(event.displayTitle)" : "Remind me about \(event.displayTitle)"))
            .accessibilityHint(hasIssue ? "Shows how to restore the reminder; use the context menu to cancel it" : (selected ? "Turns off this reminder and keeps the match saved" : "Reminds you five minutes before the scheduled start and saves the match to My Matchday"))
            .accessibilityIdentifier("match-reminder-\(event.id)")
            .focused($reminderButtonFocused)
            .accessibilityFocused($reminderButtonAccessibilityFocused)
        }
    }
}

extension MatchStartControls where Information == EmptyView {
    init(event: AnalyticalDataEngine.EventReference, status: FootballMatch.MatchStatus? = nil,
         now: Date? = nil,
         onWatch: (() -> Void)? = nil, alternateActionTitle: String? = nil,
         showsReminder: Bool = true, compact: Bool = false) {
        self.init(event: event, status: status, now: now, onWatch: onWatch,
                  alternateActionTitle: alternateActionTitle, showsReminder: showsReminder,
                  compact: compact) { EmptyView() }
    }
}


/// Shared by match rows and the featured Home match, including fixture-only discovery.
struct PendingWatchLabel: View {
    let title: String
    let symbol: String
    let isPending: Bool

    var body: some View {
        Label {
            Text(isPending ? "Opening…" : title).fixedSize(horizontal: false, vertical: true)
        } icon: {
            if isPending { ProgressView().controlSize(.small).tint(FottyTheme.textOnAccent) }
            else { Image(systemName: symbol) }
        }
    }
}
