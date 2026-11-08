import Foundation

/// Foundation's formatter classes are mutable reference types. Keep the
/// existing synchronous formatting API while making the synchronization
/// visible to Swift's concurrency checker; every access remains serialized by
/// the same lock that protected these values before the migration.
private final class LockedFormatter<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

/// Fixture validation and merging parse the same receipt formats repeatedly.
/// Reuse the configured formatters without changing admission rules or sharing
/// unsynchronized mutable Foundation objects with background validators.
enum CatalogISO8601DateParser {
    private final class CachedDate {
        let value: Date?
        init(_ value: Date?) { self.value = value }
    }

    private static let formatters = LockedFormatter({
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        let results = NSCache<NSString, CachedDate>()
        results.countLimit = 512
        results.totalCostLimit = 128 * 1024
        return (fractional: fractional, wholeSeconds: wholeSeconds, results: results)
    }())

    static func date(_ value: String) -> Date? {
        formatters.withValue { pair in
            // These immutable ISO8601 configurations use GMT, not the current
            // device zone. Cache only the exact string's parse result, never a
            // fixture's now-relative validation or admission decision.
            let key: NSString? = value.utf8.count <= 256 ? (value as NSString) : nil
            if let key, let cached = pair.results.object(forKey: key) { return cached.value }
            let date = pair.fractional.date(from: value) ?? pair.wholeSeconds.date(from: value)
            if let key {
                pair.results.setObject(CachedDate(date), forKey: key, cost: key.length * 2)
            }
            return date
        }
    }
}

private enum FottyDateFormatters {

    private static let primaryLineFormatter = LockedFormatter<DateFormatter>({
        let f = DateFormatter()
        f.dateFormat = "MMM d • h:mm a"
        return f
    }())

    private static let relativeFormatter = LockedFormatter<RelativeDateTimeFormatter>({
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }())

    private static let dayOfWeekFormatter = LockedFormatter<DateFormatter>({
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }())

    private static let timeOnlyFormatter = LockedFormatter<DateFormatter>({
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }())

    static func formatPrimaryLine(for date: Date, timeZone: TimeZone) -> String {
        primaryLineFormatter.withValue { formatter in
            if formatter.timeZone != timeZone { formatter.timeZone = timeZone }
            return formatter.string(from: date)
        }
    }

    static func formatRelative(for date: Date, relativeTo now: Date) -> String {
        relativeFormatter.withValue { formatter in
            formatter.localizedString(for: date, relativeTo: now)
        }
    }

    static func formatDayOfWeek(for date: Date) -> String {
        dayOfWeekFormatter.withValue { formatter in
            formatter.string(from: date)
        }
    }

    static func formatTimeOnly(for date: Date, timeZone: TimeZone) -> String {
        timeOnlyFormatter.withValue { formatter in
            if formatter.timeZone != timeZone { formatter.timeZone = timeZone }
            return formatter.string(from: date)
        }
    }
}

extension Date {
    /// Matches the near-term live feed window (see `EventReference.passesNearTermLiveListWindow`).
    func liveKickoffRelativeSnippet(relativeTo now: Date = .init()) -> String? {
        let t = timeIntervalSince(now)
        if t < -CatalogTimingPolicy.retentionPastGrace
            || t > CatalogTimingPolicy.retentionFutureHorizon { return nil }
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
