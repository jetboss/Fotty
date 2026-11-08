import Foundation

/// Reconciles only StreamViX's reviewed original schedule contract. A display
/// clock, opaque identifier, kickoff alone or a fixed hour adjustment is never
/// fixture authority. The caller must also corroborate teams and competition.
enum StreamVixTimingPolicy {
    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let months = [
        "Jan": 1, "January": 1, "Feb": 2, "February": 2, "Mar": 3, "March": 3,
        "Apr": 4, "April": 4, "May": 5, "Jun": 6, "June": 6, "Jul": 7, "July": 7,
        "Aug": 8, "August": 8, "Sep": 9, "Sept": 9, "September": 9,
        "Oct": 10, "October": 10, "Nov": 11, "November": 11, "Dec": 12, "December": 12
    ]

    /// The explicit source marker says GMT, not the seasonal Europe/London
    /// timezone. Parse every calendar component; never fill missing pieces from
    /// today or silently normalize an invalid date into another month.
    static func originalKickoff(dayHeader: String, clock: String) -> Date? {
        guard dayHeader.utf8.count <= 128,
              clock.range(of: #"^(?:[01][0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression) != nil,
              let regex = try? NSRegularExpression(pattern:
                #"^(Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday) ([0-9]{1,2})(st|nd|rd|th)? ([A-Za-z]+) ([0-9]{4}) - Schedule Time UK GMT$"#),
              let match = regex.firstMatch(in: dayHeader, range: NSRange(dayHeader.startIndex..., in: dayHeader)),
              match.range == NSRange(dayHeader.startIndex..., in: dayHeader) else { return nil }
        func part(_ index: Int) -> String? {
            Range(match.range(at: index), in: dayHeader).map { String(dayHeader[$0]) }
        }
        guard let weekday = part(1), let day = part(2).flatMap(Int.init),
              let month = part(4).flatMap({ months[$0] }), let year = part(5).flatMap(Int.init),
              (2000...2099).contains(year) else { return nil }
        if let suffix = part(3), suffix != ordinalSuffix(day) { return nil }
        let time = clock.split(separator: ":").compactMap { Int($0) }
        guard time.count == 2 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let wanted = DateComponents(year: year, month: month, day: day,
                                    hour: time[0], minute: time[1], second: 0)
        guard let date = calendar.date(from: wanted) else { return nil }
        let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
        guard actual.year == year, actual.month == month, actual.day == day,
              actual.hour == time[0], actual.minute == time[1], actual.second == 0,
              let weekdayIndex = actual.weekday, weekdays[weekdayIndex - 1] == weekday else { return nil }
        return date
    }

    /// Permit the original UTC fact or exactly the reviewed upstream defect:
    /// interpreting that same dated wall clock in Europe/Rome before emitting
    /// UTC. This is date/DST-aware and does not accept an arbitrary ±1/2h fence.
    /// Ambiguous/nonexistent Rome wall times cannot justify a correction.
    static func corroborates(derived: Date, original: Date) -> Bool {
        if derived == original { return true } // An upstream correction needs no adjustment.
        return legacyRomeInterpretation(of: original) == derived
    }

    static func legacyRomeInterpretation(of original: Date) -> Date? {
        guard let rome = TimeZone(identifier: "Europe/Rome") else { return nil }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var local = Calendar(identifier: .gregorian); local.timeZone = rome
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let wanted = utc.dateComponents(fields, from: original)
        // Current reviewed schedule years use CET/CEST. Both candidates are
        // round-tripped, so the autumn duplicate and spring gap fail closed.
        let candidates = [3600.0, 7200.0].map { original.addingTimeInterval(-$0) }.filter {
            local.dateComponents(fields, from: $0) == wanted
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private static func ordinalSuffix(_ day: Int) -> String {
        if (11...13).contains(day % 100) { return "th" }
        switch day % 10 { case 1: return "st"; case 2: return "nd"; case 3: return "rd"; default: return "th" }
    }
}
