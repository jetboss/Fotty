import XCTest
@testable import Fotty

@MainActor
final class MatchdayDayNavigationTests: XCTestCase {
    private struct Item: Identifiable {
        let id: String
    }

    private func headings(_ sections: [MatchdayDisplayLayout.Section<Item>], columns: Int = 1,
                          excluding: String? = nil) -> [MatchdayDayNavigationPolicy.Section] {
        MatchdayDisplayLayout.entries(sections: sections, columns: columns, excluding: excluding,
            reason: { _ in "Saved match" }, isChannel: { _ in false }).compactMap { entry in
                guard case .heading(let heading) = entry else { return nil }
                return .init(id: heading.sectionID, title: heading.title)
            }
    }

    func testJumpTargetsUseOnlyVisibleCurrentAndDayHeadingsInTheirExistingOrder() {
        let sections: [MatchdayDisplayLayout.Section<Item>] = [
            .init(id: "live", title: "Live now", subtitle: nil, items: [.init(id: "current")]),
            .init(id: "listed", title: "Broadcast listed", subtitle: nil, items: []),
            .init(id: "next", title: "Next up", subtitle: nil, items: [.init(id: "soon")]),
            .init(id: "day-815000000.0", title: "Friday, October 30", subtitle: nil, items: [.init(id: "tomorrow")]),
            .init(id: "recent", title: "Recent", subtitle: nil, items: [.init(id: "old")]),
            .init(id: "channels", title: "Saved channels", subtitle: nil, items: [.init(id: "channel")])
        ]
        let result = MatchdayDayNavigationPolicy.targets(sections: headings(sections))
        XCTAssertEqual(result.map(\.id), ["live", "next", "day-815000000.0"])
        XCTAssertEqual(result.map(\.title), ["Live now", "Next up", "Friday, October 30"])
    }

    func testReminderTargetExclusionCannotCreateAJumperToAnAbsentSection() {
        let sections: [MatchdayDisplayLayout.Section<Item>] = [
            .init(id: "live", title: "Live now", subtitle: nil, items: [.init(id: "reminder")]),
            .init(id: "next", title: "Next up", subtitle: nil, items: [.init(id: "future")])
        ]
        let targets = MatchdayDayNavigationPolicy.targets(sections: headings(sections, excluding: "reminder"))
        XCTAssertEqual(targets.map(\.id), ["next"])
        XCTAssertFalse(targets.contains { $0.id == "live" })
    }

    func testNarrowAndWideRowsHaveTheSameDayTargetsAndLongTitles() {
        let longTitle = "Wednesday, September 30 — the complete existing section title"
        let sections: [MatchdayDisplayLayout.Section<Item>] = [
            .init(id: "day-815000000.0", title: longTitle, subtitle: nil,
                  items: [.init(id: "a"), .init(id: "b"), .init(id: "c")])
        ]
        let narrow = MatchdayDayNavigationPolicy.targets(sections: headings(sections, columns: 1))
        let wide = MatchdayDayNavigationPolicy.targets(sections: headings(sections, columns: 2))
        XCTAssertEqual(narrow, wide)
        XCTAssertEqual(narrow.first?.title, longTitle)
        XCTAssertEqual(narrow.first?.id, "day-815000000.0")
    }

    func testCalendarDayIDsRemainExactAcrossDSTWithoutInferringFutureStarts() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let first = try XCTUnwrap(calendar.date(from: .init(year: 2026, month: 11, day: 1)))
        let next = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: first))
        XCTAssertEqual(next.timeIntervalSince(first), 25 * 3_600)
        let ids = [first, next].map { "day-\($0.timeIntervalSinceReferenceDate)" }
        let input = zip(ids, ["Sunday, November 1", "Monday, November 2"]).map {
            MatchdayDayNavigationPolicy.Section(id: $0.0, title: $0.1)
        }
        let targets = MatchdayDayNavigationPolicy.targets(sections: input)
        XCTAssertEqual(targets.map(\.id), ids)
        XCTAssertEqual(targets.map(\.title), input.map(\.title))
    }

    func testMalformedAbsentAndRepeatedSectionsNeverInventDatesOrDuplicateTargets() {
        let targets = MatchdayDayNavigationPolicy.targets(sections: [
            .init(id: "day-not-a-time", title: "Tomorrow"), .init(id: "day-nan", title: "Invalid"),
            .init(id: "day-inf", title: "Invalid"), .init(id: "unconfirmed-time", title: "Time to be confirmed"),
            .init(id: "live", title: "Live now"), .init(id: "live", title: "Live now"),
            .init(id: "next", title: "")])
        XCTAssertEqual(targets.map(\.id), ["live"])
        XCTAssertTrue(MatchdayDayNavigationPolicy.targets(sections: []).isEmpty)
    }
}
