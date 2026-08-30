import SwiftUI

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
    var minimumInformationWidth: CGFloat = 150
    var forceStack = false
    var spacing: CGFloat = 12

    static func fitsBeside(width: CGFloat, informationMinimum: CGFloat, actionWidth: CGFloat,
                           spacing: CGFloat = 12, forceStack: Bool = false) -> Bool {
        !forceStack && width >= informationMinimum + spacing + actionWidth
    }

    private func measurement(_ proposal: ProposedViewSize, _ subviews: Subviews)
        -> (size: CGSize, information: CGSize, action: CGSize, horizontal: Bool) {
        let idealAction = subviews[1].sizeThatFits(.unspecified)
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
            ?? (minimumInformationWidth + spacing + idealAction.width)
        let actionWidth = min(width, idealAction.width)
        let horizontal = Self.fitsBeside(width: width, informationMinimum: minimumInformationWidth,
            actionWidth: actionWidth, spacing: spacing, forceStack: forceStack)
        let informationWidth = horizontal ? width - spacing - actionWidth : width
        let information = subviews[0].sizeThatFits(.init(width: informationWidth, height: nil))
        let actionHeight = subviews[1].sizeThatFits(.init(width: actionWidth, height: nil)).height
        let action = CGSize(width: actionWidth, height: actionHeight)
        let height = horizontal ? max(information.height, action.height) : information.height + spacing + action.height
        return (CGSize(width: width, height: height), information, action, horizontal)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        return measurement(proposal, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let result = measurement(.init(width: bounds.width, height: nil), subviews)
        let informationWidth = result.horizontal ? bounds.width - spacing - result.action.width : bounds.width
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY + (result.horizontal ? (bounds.height - result.information.height) / 2 : 0)),
            anchor: .topLeading, proposal: .init(width: informationWidth, height: result.information.height))
        subviews[1].place(at: CGPoint(x: result.horizontal ? bounds.maxX - result.action.width : bounds.minX,
            y: result.horizontal ? bounds.midY - result.action.height / 2 : bounds.minY + result.information.height + spacing),
            anchor: .topLeading, proposal: .init(result.action))
    }
}

struct MatchStartControls<Information: View>: View {
    let event: AnalyticalDataEngine.EventReference
    var status: FootballMatch.MatchStatus? = nil
    var onWatch: (() -> Void)? = nil
    var showsReminder = true
    private let information: Information
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var minimumInformationWidth: CGFloat = 150
    @State private var reminders = MatchReminderStore.shared
    @State private var feedback = MatchPlaybackFeedback.shared
    @State private var message: String?
    @State private var showSettings = false

    init(event: AnalyticalDataEngine.EventReference, status: FootballMatch.MatchStatus? = nil,
         onWatch: (() -> Void)? = nil, showsReminder: Bool = true,
         @ViewBuilder information: () -> Information) {
        self.event = event
        self.status = status
        self.onWatch = onWatch
        self.showsReminder = showsReminder
        self.information = information()
    }

    var body: some View {
        if scenePhase == .active {
            TimelineView(MatchCountdownSchedule(kickoff: event.isBroadcastChannel ? nil : event.kickoffDate)) { context in
                controls(at: context.date)
            }
        } else {
            controls(at: Date())
        }
    }

    private func controls(at now: Date) -> some View {
        let policy = MatchStartPolicy(event: event, now: now, status: status)
        return VStack(alignment: .leading, spacing: 5) {
            if Information.self != EmptyView.self {
                MatchRowLayout(minimumInformationWidth: minimumInformationWidth, forceStack: typeSize.isAccessibilitySize) {
                    information
                    VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                        actions(policy: policy)
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
            if let message {
                Text(message)
                    .font(FottyTheme.typeCaption)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("match-reminder-message")
            }
            if showSettings {
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

    @ViewBuilder
    private func actions(policy: MatchStartPolicy) -> some View {
        let actionable = policy.canAttemptPlayback && onWatch != nil
        let retry = feedback.notReadyIDs.contains(event.id) && actionable
        let isRow = Information.self != EmptyView.self
        let title = retry ? (isRow ? "Retry" : "Not ready · Retry")
            : (isRow && event.isBroadcastChannel && actionable ? "Watch" : policy.title)
        if actionable {
            Button {
                // Recheck at the tap, not just the last rendered second.
                guard MatchStartPolicy(event: event, status: status).canAttemptPlayback else { return }
                onWatch?()
            } label: {
                Label(title, systemImage: retry ? "arrow.clockwise" : "play.fill")
                    .font(FottyTheme.typeMeta.weight(.semibold))
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(FottyTheme.accent, in: RoundedRectangle(cornerRadius: FottyTheme.radiusSM))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(event.isBroadcastChannel && !retry ? "Watch channel" : title)
            .accessibilityHint("Checks the listed broadcast. A scheduled start does not guarantee a stream is ready.")
            .accessibilityIdentifier("match-start-play-\(event.id)")
        } else {
            Label(title, systemImage: policy.upcomingStart != nil ? "clock" : "info.circle")
                .font(FottyTheme.typeMeta)
                .monospacedDigit()
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44)
                .accessibilityLabel(policy.upcomingStart != nil ? "Scheduled \(title.lowercased())" : title)
                .accessibilityIdentifier("match-start-countdown-\(event.id)")
        }

        if showsReminder, let start = policy.upcomingStart,
           start.timeIntervalSince(policy.now) > MatchStartPolicy.reminderLead || reminders.contains(event.id) || reminders.busyIDs.contains(event.id) {
            let selected = reminders.contains(event.id)
            let permissionOff = selected && reminders.permission == .denied
            let needsRetry = selected && reminders.failedIDs.contains(event.id)
            let hasIssue = permissionOff || needsRetry
            let busy = reminders.busyIDs.contains(event.id)
            Button {
                showSettings = false
                if permissionOff {
                    message = MatchReminderStore.Result.denied.message
                    showSettings = true
                } else if selected && !needsRetry {
                    reminders.cancel(event.id)
                    message = MatchReminderStore.Result.cancelled.message
                } else {
                    Task { @MainActor in
                        let result = await reminders.enable(event)
                        message = result.message
                        showSettings = result == .denied
                    }
                }
            } label: {
                Label(busy ? "Setting…" : (permissionOff ? "Alerts off" : (needsRetry ? "Retry reminder" : (selected ? "Reminder set" : "Remind me"))),
                      systemImage: hasIssue ? "bell.slash" : (selected ? "bell.fill" : "bell"))
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(selected ? FottyTheme.accentText : FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .contextMenu {
                if selected {
                    Button("Cancel reminder", systemImage: "bell.slash") {
                        reminders.cancel(event.id)
                        message = MatchReminderStore.Result.cancelled.message
                        showSettings = false
                    }
                }
            }
            .accessibilityLabel(hasIssue ? "Restore reminder for \(event.displayTitle)" : (selected ? "Cancel reminder for \(event.displayTitle)" : "Remind me about \(event.displayTitle)"))
            .accessibilityHint(hasIssue ? "Shows how to restore the reminder; use the context menu to cancel it" : (selected ? "Turns off this reminder and keeps the match saved" : "Reminds you five minutes before the scheduled start and saves the match to My Matchday"))
            .accessibilityIdentifier("match-reminder-\(event.id)")
        }
    }
}

extension MatchStartControls where Information == EmptyView {
    init(event: AnalyticalDataEngine.EventReference, status: FootballMatch.MatchStatus? = nil,
         onWatch: (() -> Void)? = nil, showsReminder: Bool = true) {
        self.init(event: event, status: status, onWatch: onWatch, showsReminder: showsReminder) { EmptyView() }
    }
}
