import Foundation

private enum FottyDateFormatters {
    private static let lock = NSLock()

    private static let primaryLineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d • h:mm a"
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private static let dayOfWeekFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let timeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    static func formatPrimaryLine(for date: Date, timeZone: TimeZone) -> String {
        lock.lock()
        defer { lock.unlock() }
        if primaryLineFormatter.timeZone != timeZone {
            primaryLineFormatter.timeZone = timeZone
        }
        return primaryLineFormatter.string(from: date)
    }

    static func formatRelative(for date: Date, relativeTo now: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    static func formatDayOfWeek(for date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return dayOfWeekFormatter.string(from: date)
    }

    static func formatTimeOnly(for date: Date, timeZone: TimeZone) -> String {
        lock.lock()
        defer { lock.unlock() }
        if timeOnlyFormatter.timeZone != timeZone {
            timeOnlyFormatter.timeZone = timeZone
        }
        return timeOnlyFormatter.string(from: date)
    }
}

extension Date {
    /// Matches the near-term live feed window (see `EventReference.passesNearTermLiveListWindow`).
    func liveKickoffRelativeSnippet(relativeTo now: Date = .init()) -> String? {
        let pastGrace: TimeInterval = 36 * 3600
        let futureHorizon: TimeInterval = 48 * 3600
        let t = timeIntervalSince(now)
        if t < -pastGrace || t > futureHorizon { return nil }
        return FottyDateFormatters.formatRelative(for: self, relativeTo: now)
    }

    /// Top-line kickoff in live list cards (near-term rows only; no year).
    func liveListKickoffPrimaryLine(timeZone: TimeZone = .current) -> String {
        FottyDateFormatters.formatPrimaryLine(for: self, timeZone: timeZone)
    }

    /// Arena row badge: only imminent kickoffs are "Soon".
    func arenaKickoffBadgeLabel(relativeTo now: Date = .init()) -> String {
        let untilKickoff = timeIntervalSince(now)
        if untilKickoff > 0, untilKickoff <= 3 * 3600 { return "Soon" }
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInTomorrow(self) { return "Tomorrow" }
        return FottyDateFormatters.formatDayOfWeek(for: self)
    }

    /// Secondary kickoff line on Arena rows (time only today, date + time otherwise).
    func arenaKickoffDetailLine(timeZone: TimeZone = .current) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return FottyDateFormatters.formatTimeOnly(for: self, timeZone: timeZone)
        }
        return liveListKickoffPrimaryLine(timeZone: timeZone)
    }

    func isWithinStartingSoonWindow(
        threshold: TimeInterval = 6 * 3600,
        relativeTo now: Date = .init()
    ) -> Bool {
        let untilKickoff = timeIntervalSince(now)
        return untilKickoff > 0 && untilKickoff <= threshold
    }
}
