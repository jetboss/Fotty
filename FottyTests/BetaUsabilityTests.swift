import XCTest
import SwiftUI
@testable import Fotty

final class BetaUsabilityTests: XCTestCase {
    @MainActor
    func testMajorLeagueBadgeFallbackSurvivesSparseAndInvalidCachedData() throws {
        let seed = TeamBrandService.majorLeagueBadgeURLs
        XCTAssertEqual(seed.values.filter { $0.path.contains("/mlb/") }.count, 30)
        XCTAssertEqual(Set(seed.values.filter { $0.path.contains("/nba/") }).count, 30)
        XCTAssertEqual(seed["new york yankees"]?.lastPathComponent, "nyy.png")
        XCTAssertEqual(seed["houston astros"]?.lastPathComponent, "hou.png")
        XCTAssertEqual(seed["st louis cardinals"]?.lastPathComponent, "stl.png")
        let cached = ["chelsea": "https://example.test/chelsea.png", "new york yankees": "not-a-web-url", "houston astros": "file:///private/badge.png"]
        let merged = TeamBrandService.mergingBadgeCache(cached, into: seed)
        XCTAssertEqual(merged["new york yankees"], seed["new york yankees"])
        XCTAssertEqual(merged["houston astros"], seed["houston astros"])
        XCTAssertNotNil(merged["chelsea"])
        XCTAssertEqual(merged.count, seed.count + 1)
    }

    func testAppearanceHasDedicatedDestinationAndEngineeringIsNotInSettings() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Settings/SettingsScreen.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("SettingsAppearanceView()"))
        XCTAssertTrue(source.contains("title: \"Appearance\""))
        XCTAssertTrue(source.contains("settings-appearance-screen"))
        XCTAssertFalse(source.contains("debugEngineeringSection"))
        XCTAssertFalse(source.contains("SettingsSection(title: \"Engineering\")"))
        XCTAssertFalse(source.contains("StreamPipelineValidationView()"))
    }

    func testUIClubNamesPreserveTheirIdentity() {
        for name in ["Internacional de Bogotá", "Estudiantes de La Plata", "Coventry City", "Deportivo Alavés"] {
            XCTAssertEqual(MatchCardFormatting.compactTeamName(name), name)
            XCTAssertEqual(MatchCardFormatting.denseTeamName(name), name)
        }
        XCTAssertEqual(MatchCardFormatting.denseTeamName("Manchester United"), "Man United")
        XCTAssertEqual(MatchCardFormatting.compactTeamName("  Coventry City FC  "), "Coventry City")
    }

    @MainActor
    func testUIBroadcastLabelsDoNotPromiseFutureMatchesAreLive() {
        XCTAssertEqual(LiveEventCard.broadcastActionLabel(isLive: true), "Watch live")
        XCTAssertEqual(LiveEventCard.broadcastActionLabel(isLive: false), "Check streams")
    }

    @MainActor
    func testUIPointsLabelsIdentifyTheGameweekAndSource() {
        XCTAssertEqual(FPLMainView.pointsLabel(live: nil, officialGameweek: 1), "GW 1 points · official")
        XCTAssertEqual(FPLMainView.pointsLabel(live: nil, officialGameweek: nil), "Official points")
        for (isFinal, projected, expected) in [(true, false, "final"), (false, false, "live"), (false, true, "projected")] {
            let summary = FPLLiveSquadSummary(gameweek: 2, totalPoints: 64, officialCurrentPoints: 50, publishedLineupPoints: 50, hasCompleteScoringData: true, transferCost: 0, playersPlayed: 11, playersRemaining: 0, officialBonus: 0, automaticSubs: [], projectedAutomaticSubs: [], projectedCaptainElementID: projected ? 42 : nil, rows: [], isFinal: isFinal)
            XCTAssertEqual(FPLMainView.pointsLabel(live: summary, officialGameweek: 1), "GW 2 points · \(expected)")
        }
        let incomplete = FPLLiveSquadSummary(gameweek: 2, totalPoints: nil, officialCurrentPoints: nil, publishedLineupPoints: nil, hasCompleteScoringData: false, transferCost: 0, playersPlayed: 0, playersRemaining: 0, officialBonus: 0, automaticSubs: [], projectedAutomaticSubs: [], projectedCaptainElementID: nil, rows: [], isFinal: false)
        XCTAssertEqual(FPLMainView.pointsLabel(live: incomplete, officialGameweek: 1), "GW 2 points · incomplete data")
    }

    @MainActor
    func testUIFixtureDifficultyTextMeetsNormalTextContrast() {
        func luminance(_ color: Color) -> Double {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            XCTAssertTrue(UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            func linear(_ value: CGFloat) -> Double {
                let value = Double(value)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
        for difficulty in 0...5 {
            let foreground = luminance(FottyFixtureDifficulty.foreground(difficulty))
            let background = luminance(FottyFixtureDifficulty.background(difficulty))
            let contrast = (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
            XCTAssertGreaterThanOrEqual(contrast, 4.5, "Difficulty \(difficulty)")
        }
        XCTAssertEqual(FottyFixtureDifficulty.label(2), "Difficulty 2 of 5")
        XCTAssertEqual(FottyFixtureDifficulty.label(0), "Difficulty not rated")
    }

    @MainActor
    func testUIFPLSessionPreservesToolUntilExplicitReset() async throws {
        let suite = "FottyCoachSessionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "fotty.fpl.smartCoachConsent")
        let model = FPLAdvisorViewModel(draftDefaults: defaults)
        let session = FPLWorkspaceSession(viewModel: model)
        let started = expectation(description: "Pending Coach question")
        var reply: CheckedContinuation<Void, Never>?
        let request = try XCTUnwrap(model.sendCoachQuestion("Test pending question") { _, _ in
            await withCheckedContinuation {
                reply = $0
                started.fulfill()
            }
            throw CancellationError()
        })
        await fulfillment(of: [started], timeout: 2)
        session.workspace = .tools
        session.selectedTool = .captain
        session.scrollOffsets["Tools/Captain"] = 200
        model.coachInputDraft = "Should I keep my captain?"
        _ = FPLMainView(session: session)
        _ = FPLMainView(session: session)
        XCTAssertTrue(session.viewModel === model)
        XCTAssertEqual(session.workspace, .tools)
        XCTAssertEqual(session.selectedTool, .captain)
        XCTAssertEqual(session.scrollOffsets["Tools/Captain"], 200)
        XCTAssertEqual(model.coachInputDraft, "Should I keep my captain?")
        XCTAssertTrue(model.isCoachThinking)
        session.resetNavigation()
        XCTAssertEqual(session.workspace, .gameweek)
        XCTAssertNil(session.selectedTool)
        XCTAssertTrue(session.scrollOffsets.isEmpty)
        XCTAssertTrue(model.isCoachThinking, "Navigation changes must not cancel a valid question")
        model.cancelCoachRequest()
        reply?.resume()
        await request.value
    }

    func testManagerIDAcceptsNumbersAndOfficialTeamLinks() {
        for input in [
            "123456", "  123456\n", "000123456",
            "https://fantasy.premierleague.com/entry/123456/event/2",
            "https://fantasy.premierleague.com/entry/123456/history/",
            "fantasy.premierleague.com/entry/123456/event/2",
            "https://FANTASY.PREMIERLEAGUE.COM/entry/123456/",
            "http://fantasy.premierleague.com/a/entry/123456",
            "https://fantasy.premierleague.com/api/entry/123456/?x=1#test"
        ] {
            XCTAssertEqual(FPLManagerIDParser.parse(input), 123456, input)
        }
    }

    func testManagerIDRejectsInvalidAndUntrustedLinksWithoutFetchingThem() {
        for input in [
            "", "0", "-1", "+12", "1.5", "12 34", "１２３", "9999999999999999999999999999",
            "https://example.com/entry/123/",
            "https://fantasy.premierleague.com.example.com/entry/123/",
            "https://fantasy.premierleague.com@evil.example/entry/123/",
            "https://user:password@fantasy.premierleague.com/entry/123/",
            "https://fantasy.premierleague.com:444/entry/123/",
            "file://fantasy.premierleague.com/entry/123/",
            "https://fantasy.premierleague.com/leagues/123/",
            "https://fantasy.premierleague.com/entry/",
            "https://fantasy.premierleague.com/entry/0/",
            "https://fantasy.premierleague.com/?entry=123"
        ] {
            XCTAssertNil(FPLManagerIDParser.parse(input), input)
        }
    }

    @MainActor
    func testInvalidManagerInputNeverStartsLookup() async {
        var calls = 0
        let model = FPLManagerConnectionModel { id in
            calls += 1
            return Self.identity(id)
        }
        await model.lookup("not a team")
        XCTAssertEqual(calls, 0)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isChecking)
        XCTAssertNil(model.identity)
    }

    @MainActor
    func testManagerLookupFailureCanRetryTheSameID() async {
        var calls = 0
        let previousSelection = UserDefaults.standard.object(forKey: "fotty.user.fplManagerId") as? Int
        let model = FPLManagerConnectionModel { id in
            calls += 1
            if calls == 1 { throw URLError(.notConnectedToInternet) }
            return Self.identity(id)
        }
        await model.lookup("123")
        XCTAssertNil(model.identity)
        XCTAssertTrue(model.errorMessage?.contains("offline") == true)
        XCTAssertFalse(model.isChecking)
        await model.lookup("123")
        XCTAssertEqual(model.identity?.id, 123)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isChecking)
        // Checking a team isn't consent to replace the connected manager.
        XCTAssertEqual(UserDefaults.standard.object(forKey: "fotty.user.fplManagerId") as? Int, previousSelection)
    }

    @MainActor
    func testLateManagerLookupCannotReplaceANewerTeam() async {
        let firstStarted = expectation(description: "First lookup started")
        var firstReply: CheckedContinuation<FPLManagerIdentity, Error>?
        let model = FPLManagerConnectionModel { id in
            if id == 1 {
                return try await withCheckedThrowingContinuation { continuation in
                    firstReply = continuation
                    firstStarted.fulfill()
                }
            }
            return Self.identity(id)
        }
        let first = Task { await model.lookup("1") }
        await fulfillment(of: [firstStarted], timeout: 2)
        await model.lookup("2")
        firstReply?.resume(returning: Self.identity(1))
        await first.value
        XCTAssertEqual(model.identity?.id, 2)
        XCTAssertFalse(model.isChecking)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testCancellingLookupPreventsLateErrorFromRestoringFailureState() async {
        let started = expectation(description: "Lookup started")
        var reply: CheckedContinuation<FPLManagerIdentity, Error>?
        let model = FPLManagerConnectionModel { _ in
            try await withCheckedThrowingContinuation { continuation in
                reply = continuation
                started.fulfill()
            }
        }
        let task = Task { await model.lookup("1") }
        await fulfillment(of: [started], timeout: 2)
        model.reset()
        task.cancel()
        reply?.resume(throwing: URLError(.badServerResponse))
        await task.value
        XCTAssertNil(model.identity)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isChecking)
    }

    @MainActor
    func testMismatchedLookupIdentityIsNotOfferedForConfirmation() async {
        let model = FPLManagerConnectionModel { _ in Self.identity(99) }
        await model.lookup("123")
        XCTAssertNil(model.identity)
        XCTAssertNotNil(model.errorMessage)
    }

    @MainActor
    func testAlreadyCancelledLookupDoesNotResetANewIdentityOrFetch() async {
        var calls = 0
        let model = FPLManagerConnectionModel { id in
            calls += 1
            return Self.identity(id)
        }
        await model.lookup("2")
        let ready = expectation(description: "Cancelled task ready")
        var resume: CheckedContinuation<Void, Never>?
        let task = Task {
            await withCheckedContinuation { continuation in
                resume = continuation
                ready.fulfill()
            }
            await model.lookup("1")
        }
        await fulfillment(of: [ready], timeout: 2)
        task.cancel()
        resume?.resume()
        await task.value
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.identity?.id, 2)
    }

    func testFeedbackIncludesBuildAndContextButDiagnosticsAreOptIn() {
        var report = FottyFeedbackReport(
            area: "Playback", expected: "  Resume the match  ", actual: "The picture stayed still",
            version: "2.0.0 (34)", device: "iPhone", system: "iOS 27", date: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(report.text.contains("2.0.0 (34)"))
        XCTAssertTrue(report.text.contains("iPhone"))
        XCTAssertTrue(report.text.contains("1970-01-01T00:00:00Z"))
        XCTAssertTrue(report.text.contains("expected:\nResume the match"))
        XCTAssertFalse(report.text.contains("Optional on-device diagnostics"))
        report.diagnostics = "{\"recordCount\":0}"
        XCTAssertTrue(report.text.contains("included by the tester"))
        XCTAssertTrue(report.text.contains("recordCount"))
    }

    func testSetupCanBeDismissedAndDoesNotRequireFPLToUseTheApp() {
        XCTAssertTrue(MatchdaySetupPolicy.shouldShow(dismissed: false, followedCount: 0, savedCount: 0))
        XCTAssertFalse(MatchdaySetupPolicy.shouldShow(dismissed: true, followedCount: 0, savedCount: 0))
        XCTAssertFalse(MatchdaySetupPolicy.shouldShow(dismissed: true, followedCount: 1, savedCount: 2))
        XCTAssertFalse(MatchdaySetupPolicy.shouldShow(dismissed: false, followedCount: 1, savedCount: 2))
    }

    func testDiscoveryAndMatchdayDoNotPromoteOrDependOnFPL() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for path in [
            "Fotty/Features/Dashboard/SportsDashboardView.swift",
            "Fotty/Features/Dashboard/Components/HeroMatchCarousel.swift",
            "Fotty/Features/Dashboard/Components/LiveEventCard.swift",
            "Fotty/Features/Dashboard/Components/HomeSportsDiscovery.swift",
            "Fotty/Features/Dashboard/Components/SportsDiscoveryViews.swift",
            "Fotty/Features/Onboarding/MatchdaySetupCard.swift",
            "Fotty/Features/Social/ArenaDiscoveryView.swift",
            "Fotty/Features/MatchHub/Tabs/InsightsHubTab.swift"
        ] {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertFalse(source.contains("FPL"), path)
            XCTAssertFalse(source.contains("fplContext"), path)
        }
    }

    @MainActor
    func testCricketChannelIsNotACPLMatchOrAnUnknownTimeFixture() {
        let willow = cricketEvent(title: "Willow Cricket", date: -3_600_000)
        XCTAssertTrue(willow.isBroadcastChannel)
        XCTAssertEqual(willow.homeName, "Willow Cricket")
        XCTAssertEqual(willow.awayName, "")
        XCTAssertEqual(willow.displayTitle, "Willow Cricket")
        XCTAssertFalse(willow.isCPLFixture)
        XCTAssertEqual(willow.broadcastTiming(), .available)
        XCTAssertFalse(willow.isPastEstimatedMatchWindow())
        XCTAssertFalse(CricketCatalogFilter.cpl.includes(willow))
        XCTAssertTrue(CricketCatalogFilter.channels.includes(willow))
        XCTAssertFalse(cricketEvent(title: "India vs Australia", date: nil).isBroadcastChannel)
        XCTAssertFalse(cricketEvent(title: "Willow Cricket vs Fox Cricket", date: nil).isBroadcastChannel)
    }

    @MainActor
    func testCPLIdentityRequiresCricketAndExplicitCompetitionOrTwoTeams() {
        XCTAssertTrue(cricketEvent(title: "Trinbago Knight Riders vs Barbados Royals", date: nil).isCPLFixture)
        XCTAssertTrue(cricketEvent(title: "St. Lucia Kings vs Antigua Falcons", date: nil).isCPLFixture)
        XCTAssertTrue(cricketEvent(title: "CPL Final", date: nil).isCPLFixture)
        XCTAssertFalse(cricketEvent(title: "Trinbago Knight Riders news", date: nil).isCPLFixture)
        XCTAssertFalse(cricketEvent(title: "India vs Australia", date: nil).isCPLFixture)
        let football = AnalyticalDataEngine.EventReference(id: "test-football", title: "CPL Final", category: "football", date: nil, poster: nil, popular: nil, teams: nil, sources: nil)
        XCTAssertFalse(football.isCPLFixture)
    }

    @MainActor
    func testCricketTimingDoesNotExpireAtFootballFullTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let started = Int64(now.addingTimeInterval(-3 * 3600).timeIntervalSince1970)
        let cpl = cricketEvent(title: "CPL · Trinbago Knight Riders vs Barbados Tridents", date: started)
        XCTAssertEqual(cpl.broadcastTiming(at: now), .live)
        XCTAssertFalse(cpl.isPastEstimatedMatchWindow(at: now))
        XCTAssertTrue(cpl.isPastEstimatedMatchWindow(at: now.addingTimeInterval(3 * 3600)))
        let testMatch = cricketEvent(title: "India vs Australia, 1st Test", date: started)
        XCTAssertEqual(testMatch.broadcastTiming(at: now), .available)
        XCTAssertFalse(testMatch.isPastEstimatedMatchWindow(at: now.addingTimeInterval(48 * 3600)))
    }

    @MainActor
    func testSavedChannelSurvivesNegativeProviderDateAndRelaunch() throws {
        let suite = "Fotty.CricketPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let willow = cricketEvent(title: "Willow Cricket", date: -3_600_000)
        let store = MyMatchdayStore(defaults: defaults)
        store.save(willow)
        store.pruneExpiredMatches(relativeTo: Date().addingTimeInterval(72 * 3600))
        XCTAssertTrue(store.contains(eventID: willow.id))
        XCTAssertTrue(MyMatchdayStore(defaults: defaults).contains(eventID: willow.id))
    }

    @MainActor
    func testCPLSchedulePreservesVenueTimeZonesAndJulyOpponentCorrection() throws {
        XCTAssertEqual(CPLSchedule.fixtures.count, 39)
        XCTAssertEqual(Set(CPLSchedule.fixtures.map(\.id)).count, 39)
        for fixture in CPLSchedule.fixtures { XCTAssertNotNil(ISO8601DateFormatter().date(from: fixture.start)) }
        let jamaica = CPLSchedule.fixtures[3]
        XCTAssertEqual(ISO8601DateFormatter().string(from: jamaica.kickoff), "2026-08-12T00:00:00Z")
        XCTAssertEqual(CPLSchedule.fixtures[19].away, .jamaica)
        XCTAssertEqual(CPLSchedule.fixtures[21].away, .guyana)
        XCTAssertEqual(CPLSchedule.fixtures[18].away, .barbados)
        XCTAssertEqual(CPLSchedule.fixtures[18].away?.rawValue, "Barbados Tridents")
    }

    @MainActor
    func testCPLScheduleNeverBorrowsWillowSourcesAndExpiresAfterSeason() {
        let fixture = CPLSchedule.fixtures[18]
        let willow = cricketEvent(title: "Willow Cricket", date: nil, sources: [.init(source: "delta", id: "test-channel")])
        let schedule = CPLSchedule.merging(into: [willow], at: fixture.kickoff)
        XCTAssertTrue(schedule.contains { $0.id == willow.id })
        XCTAssertTrue(schedule.filter { $0.isCPLFixture }.allSatisfy { $0.sources?.isEmpty != false })
        XCTAssertEqual(schedule.first { $0.id == fixture.id }?.broadcastTiming(at: fixture.kickoff), .available)
        let expired = CPLSchedule.merging(into: schedule, at: CPLSchedule.fixtures[38].kickoff.addingTimeInterval(48 * 3600))
        XCTAssertEqual(expired.map(\.id), [willow.id])
    }

    @MainActor
    func testCPLSourceMatchingRequiresTeamsAndKickoffAndKeepsStableSavedIdentity() throws {
        let fixture = CPLSchedule.fixtures[18]
        let provider = cricketEvent(title: "Trinbago Knight Riders vs Barbados Royals", date: Int64(fixture.kickoff.timeIntervalSince1970), sources: [.init(source: "delta", id: "test-fixture")])
        XCTAssertTrue(CPLSchedule.matches(provider, fixture: fixture))
        let wrongDate = cricketEvent(title: provider.title!, date: Int64(fixture.kickoff.addingTimeInterval(24 * 3600).timeIntervalSince1970))
        XCTAssertFalse(CPLSchedule.matches(wrongDate, fixture: fixture))
        let merged = CPLSchedule.merging(into: [provider], at: fixture.kickoff)
        let event = try XCTUnwrap(merged.first { $0.id == fixture.id })
        XCTAssertEqual(event.sources?.map(\.id), ["test-fixture"])
        XCTAssertFalse(merged.contains { $0.id == provider.id })
        let refreshedWithoutProvider = CPLSchedule.merging(into: merged, at: fixture.kickoff)
        XCTAssertTrue(refreshedWithoutProvider.first { $0.id == fixture.id }?.sources?.isEmpty == true)
    }

    @MainActor
    private func cricketEvent(title: String, date: Int64?, sources: [NexusASource]? = nil) -> AnalyticalDataEngine.EventReference {
        .init(id: "test-\(title)", title: title, category: "cricket", date: date, poster: nil, popular: nil, teams: nil, sources: sources)
    }

    func testHelpKeepsBackgroundAlertsAndOfficialFPLActionsTruthful() {
        XCTAssertTrue(FottyHelpContent.matchAlerts.contains("not background push"))
        XCTAssertTrue(FottyHelpContent.matchAlerts.contains("Premier League"))
        XCTAssertTrue(FottyHelpContent.deadlineAlerts.contains("scheduled"))
        XCTAssertTrue(FottyHelpContent.fplDrafts.contains("Confirm any real changes in official FPL"))
        XCTAssertTrue(FottyHelpContent.scores.contains("Other competitions can still have broadcasts"))
        XCTAssertTrue(FottyHelpContent.fplPoints.contains("Provisional"))
    }

    func testManagerClearResetsLoadingAndErrorAndKeepsDraftStorage() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Fotty/Features/FPL/ViewModels/FPLAdvisorViewModel.swift"), encoding: .utf8)
        let body = try XCTUnwrap(source.components(separatedBy: "public func clearManagerId()").dropFirst().first)
            .components(separatedBy: "private func migrateLegacyLocalDataIfNeeded").first ?? ""
        for reset in ["isLoading = false", "isRefreshing = false", "errorMessage = nil", "bootstrap = nil", "managerId = nil", "rivalPicks = nil", "managerSelectionID = UUID()", "coachInputDraft = \"\"", "isCoachThinking = false", "comparisonPlayer1ID = nil", "comparisonPlayer2ID = nil"] {
            XCTAssertTrue(body.contains(reset), reset)
        }
        XCTAssertFalse(body.contains("removeObject"))
    }

    private static func identity(_ id: Int) -> FPLManagerIdentity {
        FPLManagerIdentity(id: id, teamName: "Test team \(id)", managerName: "Test manager", sourceDescription: "Test fixture")
    }
}

@MainActor
final class HomeDiscoveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ id: String, sport: String = "football", offset: TimeInterval? = 0, home: String? = nil, away: String = "Visitors", sources: [NexusASource] = []) -> AnalyticalDataEngine.EventReference {
        .init(id: id, title: "\(home ?? id) vs \(away)", category: sport,
              date: offset.map { Int64(now.addingTimeInterval($0).timeIntervalSince1970) },
              poster: nil, popular: false,
              teams: .init(home: .init(name: home ?? id, badge: nil), away: .init(name: away, badge: nil)), sources: sources)
    }

    func testHomeCountsEventsNotSourceVariantsAndKeepsEveryRealSource() throws {
        let first = event("a", offset: -60, home: "City", sources: [.init(source: "delta", id: "one"), .init(source: "golf", id: "two")])
        let duplicate = event("b", offset: -60, home: " city ", sources: [.init(source: "delta", id: "one"), .init(source: "echo", id: "three")])
        let schedule = HomeSportsDiscovery(events: [duplicate, first], now: now)
        XCTAssertEqual(schedule.items.map(\.id), ["a"])
        XCTAssertEqual(schedule.activities.first { $0.id == "football" }?.onNow, 1)
        XCTAssertEqual(schedule.items.first?.event.sources?.count, 3)
        XCTAssertEqual(HomeSportsDiscovery.uniqueEvents([first, duplicate]).map(\.id), ["a"])
    }

    func testHomeNonTeamEventsDoNotInventAnOpponent() {
        for (title, sport) in [("TNA Impact", "fight"), ("Grand Prix qualifying", "motorsports")] {
            let event = AnalyticalDataEngine.EventReference(id: "single-event", title: title, category: sport, date: nil, poster: nil, popular: nil, teams: nil, sources: [])
            XCTAssertEqual(event.displayTitle, title)
        }
        XCTAssertEqual(event("fixture", home: "Arsenal", away: "Chelsea").displayTitle, "Arsenal vs Chelsea")
        XCTAssertEqual(AnalyticalDataEngine.categoryDisplayName(for: "american-football"), "American football")
        XCTAssertEqual(AnalyticalDataEngine.sportIconName(for: "american-football"), "american.football.fill")
    }

    func testHomeDeduplicationPreservesDoubleheadersDifferentSportsAndUnknownTeams() {
        let one = event("a", home: "City")
        let later = event("b", offset: 3600, home: "City")
        let otherSport = event("c", sport: "basketball", home: "City")
        let unknown1 = event("d", offset: nil, home: "Home", away: "Away")
        let unknown2 = event("e", offset: nil, home: "Home", away: "Away")
        XCTAssertEqual(HomeSportsDiscovery.uniqueEvents([one, later, otherSport, unknown1, unknown2]).count, 5)
        XCTAssertEqual(HomeSportsDiscovery.uniqueEvents([one, one]).count, 1)
    }

    func testHomeChannelsAndUnconfirmedStartTimesNeverBecomeOnNow() {
        let willow = AnalyticalDataEngine.EventReference(id: "willow", title: "Willow Cricket", category: "cricket", date: -3_600_000, poster: nil, popular: nil, teams: nil, sources: [.init(source: "delta", id: "channel")])
        let snapshot = event("cpl-2026-test", sport: "cricket", offset: -3600, home: "Trinbago Knight Riders", away: "Barbados Tridents")
        let unknownCricket = event("test-match", sport: "cricket", offset: -3600, sources: [.init(source: "delta", id: "test")])
        let unknownStart = event("undated", offset: nil, sources: [.init(source: "delta", id: "undated")])
        let noSource = event("source-free", offset: -60)
        let schedule = HomeSportsDiscovery(events: [willow, snapshot, unknownCricket, unknownStart, noSource], now: now)
        XCTAssertEqual(schedule.channels.map(\.id), ["willow"])
        XCTAssertEqual(schedule.items.count, 4)
        XCTAssertTrue(schedule.items.allSatisfy { !$0.isOnNow })
        XCTAssertEqual(schedule.activities.first { $0.id == "cricket" }?.onNow, 0)
        XCTAssertTrue(schedule.featured(from: schedule.items, diverse: true).isEmpty)
        XCTAssertEqual(schedule.items.first { $0.id == snapshot.id }?.actionTitle, "No stream listed")
    }

    func testHomeOfficialStatusOverridesEstimatedTimingAndExpiredEventsDisappear() {
        let past = event("expired", offset: -3 * 3600)
        let finished = event("finished", offset: -60)
        let cancelled = event("cancelled", offset: 60)
        let postponed = event("postponed", offset: 3600)
        let live = event("live", offset: -3 * 3600)
        let schedule = HomeSportsDiscovery(events: [past, finished, cancelled, postponed, live], now: now) {
            ["finished": .finished, "cancelled": .cancelled, "postponed": .postponed, "live": .inPlay][$0.id]
        }
        XCTAssertEqual(Set(schedule.items.map(\.id)), ["live", "postponed"])
        XCTAssertEqual(schedule.items.first { $0.id == "live" }?.phase, .live)
        XCTAssertEqual(schedule.items.first { $0.id == "live" }?.statusLabel, "In play")
        XCTAssertEqual(schedule.items.first { $0.id == "postponed" }?.statusLabel, "Postponed")
        XCTAssertEqual(schedule.items.first { $0.id == "postponed" }?.phase, .unconfirmed)
    }

    func testHomeFeaturedHasThreeSportsBeforeRepeatingOneAndStableTies() {
        let events = [event("football-2", offset: 600), event("football-1", offset: 600), event("basketball", sport: "basketball", offset: 1200), event("cricket", sport: "cricket", offset: 1800), event("far", sport: "tennis", offset: 7 * 3600)]
        let schedule = HomeSportsDiscovery(events: events, now: now)
        let featured = schedule.featured(from: schedule.items, diverse: true)
        XCTAssertEqual(featured.map(\.id), ["football-1", "basketball", "cricket"])
        let reversed = HomeSportsDiscovery(events: events.reversed(), now: now)
        XCTAssertEqual(reversed.featured(from: reversed.items, diverse: true).map(\.id), featured.map(\.id))
        let football = schedule.scopedItems(sport: "football")
        XCTAssertEqual(schedule.featured(from: football, diverse: false).count, 2)
        XCTAssertTrue(schedule.scopedItems(sport: "rugby").isEmpty)
        XCTAssertEqual(schedule.scopedItems(sport: HomeSportsDiscovery.allSports).count, 5)
        let active = HomeSportsDiscovery(events: [
            event("earlier-other", sport: "other", offset: -1200),
            event("football", offset: -300), event("basketball", sport: "basketball", offset: -600),
            event("baseball", sport: "baseball", offset: -900)
        ], now: now, status: { _ in .inPlay })
        XCTAssertEqual(active.featured(from: active.items, diverse: true).map(\.sport), ["football", "basketball", "baseball"])
    }

    func testHomeLaterListIsBoundedHasNoDuplicatesAndRespectsLocalDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -4 * 3600)!
        let day = calendar.startOfDay(for: now).addingTimeInterval(18 * 3600)
        let futureEvents = (1...7).map { i in
            AnalyticalDataEngine.EventReference(id: "later-\(i)", title: "Team \(i) vs Visitors", category: "football", date: Int64(day.addingTimeInterval(Double(i) * 3600).timeIntervalSince1970), poster: nil, popular: nil, teams: nil, sources: [])
        }
        let schedule = HomeSportsDiscovery(events: futureEvents, now: day)
        let featured = schedule.featured(from: schedule.items, diverse: true)
        let later = schedule.later(from: schedule.items, excluding: featured, calendar: calendar)
        XCTAssertEqual(later.title, "Later today")
        XCTAssertEqual(later.items.map(\.id), ["later-4", "later-5"])
        let tomorrow = schedule.later(from: Array(schedule.items.suffix(1)), excluding: [], calendar: calendar)
        XCTAssertEqual(tomorrow.title, "Coming up")
        XCTAssertEqual(tomorrow.items.map(\.id), ["later-7"])
    }

    func testHomeActivityGridIsBoundedAndKeepsSelectedOverflowSportVisible() {
        let sports = ["football", "basketball", "cricket", "baseball", "tennis", "hockey", "rugby", "fight"]
        let schedule = HomeSportsDiscovery(events: sports.map { event($0, sport: $0, offset: 300) }, now: now)
        XCTAssertEqual(schedule.visibleActivities(selectedSport: HomeSportsDiscovery.allSports).count, 5)
        let selected = schedule.visibleActivities(selectedSport: "rugby")
        XCTAssertEqual(selected.count, 5)
        XCTAssertTrue(selected.contains { $0.id == "rugby" })
        let empty = HomeSportsDiscovery(events: [], now: now)
        XCTAssertEqual(empty.activities.first?.summary(at: now), "Nothing listed")
        XCTAssertTrue(empty.items.isEmpty)
    }

    func testHomeSportsOverflowIsOnlyForCompactPhones() {
        XCTAssertFalse(SportActivityGrid.showsAllSports(expanded: false, regularWidth: false, isPad: false))
        XCTAssertTrue(SportActivityGrid.showsAllSports(expanded: true, regularWidth: false, isPad: false))
        XCTAssertTrue(SportActivityGrid.showsAllSports(expanded: false, regularWidth: true, isPad: false))
        XCTAssertTrue(SportActivityGrid.showsAllSports(expanded: false, regularWidth: false, isPad: true), "Split View keeps every iPad sport visible in additional rows")
    }

    func testSportGridFillsWidthWithEqualCellsIncludingPartialLastRow() {
        let layout = SportTileGridLayout(minimumTileWidth: 94)
        var grid = layout.metrics(width: 920, count: 11)
        grid.tileHeight = 112
        XCTAssertEqual(grid.columns, 9)
        XCTAssertEqual(grid.rows, 2)
        XCTAssertEqual(grid.size.width, 920)
        XCTAssertEqual(grid.size.height, 230)
        XCTAssertEqual(grid.origin(at: 8).x + grid.tileWidth, 920, accuracy: 0.01)
        XCTAssertEqual(grid.origin(at: 9), CGPoint(x: 0, y: 118))
        XCTAssertEqual(grid.origin(at: 10).x, grid.tileWidth + 6)
        XCTAssertEqual(layout.metrics(width: 343, count: 6).columns, 3)
        XCTAssertEqual(SportTileGridLayout(minimumTileWidth: 210).metrics(width: 343, count: 6).columns, 1)
        XCTAssertEqual(SportTileGridLayout(minimumTileWidth: 210).metrics(width: 920, count: 11).columns, 4)
    }

    func testSportGridHandlesEmptyAndUnspecifiedSizeProposals() {
        let layout = SportTileGridLayout(minimumTileWidth: 94)
        XCTAssertEqual(layout.metrics(width: 920, count: 0).size, CGSize(width: 920, height: 0))
        for width: CGFloat? in [nil, .infinity, .nan] {
            let grid = layout.metrics(width: width, count: 4)
            XCTAssertEqual(grid.columns, 1)
            XCTAssertEqual(grid.tileWidth, 94)
        }
        XCTAssertEqual(layout.metrics(width: 0, count: 4).tileWidth, 0)
        XCTAssertEqual(layout.metrics(width: -10, count: 4).columns, 1)
    }

    func testSportGridMeasuresTheTallestTileAcrossEveryRow() throws {
        let content = SportTileGridLayout(minimumTileWidth: 94) {
            ForEach([44.0, 60.0, 124.0], id: \.self) { height in
                Color.gray.frame(minHeight: height, maxHeight: .infinity)
            }
        }.frame(width: 206)
        let image = try XCTUnwrap(ImageRenderer(content: content).uiImage)
        XCTAssertEqual(image.size.width, 206, accuracy: 0.01)
        XCTAssertEqual(image.size.height, 254, accuracy: 0.01, "Both rows must use 124 points, even though the tallest cell is alone in the last row")
    }

    func testHomeStaleOrUnavailableScoresCannotKeepActivityLive() {
        XCTAssertEqual(HomeSportsDiscovery.recentStatus(.inPlay, refreshedAt: now.addingTimeInterval(-240), liveFeedAvailable: true, now: now), .inPlay)
        XCTAssertNil(HomeSportsDiscovery.recentStatus(.inPlay, refreshedAt: now.addingTimeInterval(-601), liveFeedAvailable: true, now: now))
        XCTAssertNil(HomeSportsDiscovery.recentStatus(.inPlay, refreshedAt: now, liveFeedAvailable: false, now: now))
        XCTAssertNil(HomeSportsDiscovery.recentStatus(.inPlay, refreshedAt: nil, liveFeedAvailable: true, now: now))
        XCTAssertEqual(HomeSportsDiscovery.recentStatus(.finished, refreshedAt: nil, liveFeedAvailable: false, now: now), .finished)
        XCTAssertEqual(HomeSportsDiscovery.recentStatus(.postponed, refreshedAt: nil, liveFeedAvailable: false, now: now), .postponed)
    }

    func testAppearanceDefaultsToDarkAndSupportsExplicitLightOrSystem() {
        XCTAssertEqual(FottyAppearance.saved(""), .dark)
        XCTAssertEqual(FottyAppearance.saved("invalid"), .dark)
        XCTAssertEqual(FottyAppearance.saved("light").colorScheme, .light)
        XCTAssertEqual(FottyAppearance.saved("dark").colorScheme, .dark)
        XCTAssertNil(FottyAppearance.saved("system").colorScheme)
        let suite = "FottyAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(FottyAppearance.light.rawValue, forKey: FottyAppearance.storageKey)
        let reloaded = UserDefaults(suiteName: suite)!
        XCTAssertEqual(FottyAppearance.saved(reloaded.string(forKey: FottyAppearance.storageKey) ?? ""), .light)
    }

    @MainActor
    func testSportIdentityUsesAvailableEquipmentSymbolsAcrossCatalogVariants() {
        let expected = ["football": "soccerball", "soccer": "soccerball", "basketball": "basketball.fill", "NBA": "basketball.fill", "baseball": "baseball.fill", "MLB": "baseball.fill", "cricket": "cricket.ball.fill", "tennis": "tennisball.fill", "hockey": "hockey.puck.fill", "nfl": "american.football.fill", "boxing": "figure.boxing", "f1": "flag.checkered", "all": "square.grid.2x2.fill"]
        for (sport, symbol) in expected {
            XCTAssertEqual(SportIdentity.symbol(for: sport), symbol)
            XCTAssertEqual(AnalyticalDataEngine.sportIconName(for: sport), symbol)
            XCTAssertNotNil(UIImage(systemName: symbol), "Missing equipment artwork for \(sport)")
        }
    }

    @MainActor
    func testHomeShowsTeamIdentityButDoesNotInventOpponentsForChannelsOrEvents() {
        func cricketEvent(title: String, date: Int64?) -> AnalyticalDataEngine.EventReference {
            .init(id: title, title: title, category: "cricket", date: date, poster: nil, popular: nil, teams: nil, sources: [])
        }
        XCTAssertTrue(HomeDiscoveryRow.showsTeamBadges(for: cricketEvent(title: "India vs Australia", date: nil)))
        XCTAssertTrue(HomeDiscoveryRow.showsTeamBadges(for: cricketEvent(title: "Trinbago Knight Riders vs Barbados Royals", date: nil)))
        XCTAssertFalse(HomeDiscoveryRow.showsTeamBadges(for: cricketEvent(title: "Willow Cricket", date: nil)))
        XCTAssertFalse(HomeDiscoveryRow.showsTeamBadges(for: cricketEvent(title: "CPL Final", date: nil)))
    }

    func testHomeIdentityAndAppearanceRenderAtNarrowAndIPadWidths() throws {
        let schedule = HomeSportsDiscovery(events: [
            event("football", sport: "football", offset: -60, home: "Home Test Club", away: "Visiting Test Club", sources: [.init(source: "delta", id: "fixture")]),
            event("basketball", sport: "basketball", offset: 300),
            event("baseball", sport: "baseball", offset: 600),
            event("cricket", sport: "cricket", offset: 900),
            event("tennis", sport: "tennis", offset: 900),
            event("hockey", sport: "hockey", offset: 900),
            event("american-football", sport: "american-football", offset: 900),
            event("motorsports", sport: "motorsports", offset: 900),
            event("fight", sport: "fight", offset: 900)
        ], now: now)
        let item = try XCTUnwrap(schedule.items.first)
        for (label, width, scheme, type) in [
            ("ipad-light", 820.0, ColorScheme.light, DynamicTypeSize.large),
            ("ipad-dark", 820.0, ColorScheme.dark, DynamicTypeSize.large),
            ("ipad-light-large-type", 820.0, ColorScheme.light, DynamicTypeSize.accessibility2),
            ("narrow-light-large-type", 375.0, ColorScheme.light, DynamicTypeSize.accessibility2)
        ] {
            let content = VStack(alignment: .leading, spacing: 16) {
                Text("Home").font(FottyTheme.typeScreenTitle).foregroundStyle(FottyTheme.textPrimary)
                SportActivityGrid(discovery: schedule, selectedSport: .constant("football"), isPad: width > 600)
                Text("Now & next").font(FottyTheme.typeSectionTitle).foregroundStyle(FottyTheme.textPrimary)
                HomeDiscoveryRow(item: item, isSaved: false, onOpen: {}, onSave: {})
                    .environment(LiveScoreService.shared)
            }
            .padding(16)
            .frame(width: width)
            .background(FottyTheme.background)
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, type)
            .environment(\.horizontalSizeClass, width > 600 ? .regular : .compact)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage, label)
            XCTAssertEqual(image.size.width, width, accuracy: 1, label)
            XCTAssertLessThan(image.size.height, 3000, label)
            let attachment = XCTAttachment(image: image)
            attachment.name = label
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testDedicatedAppearanceChoicesRenderAtPhoneAndIPadWidths() throws {
        for (label, width, scheme, appearance) in [
            ("appearance-ipad-light", 820.0, ColorScheme.light, FottyAppearance.light),
            ("appearance-phone-dark", 375.0, ColorScheme.dark, FottyAppearance.dark)
        ] {
            let content = SettingsAppearanceOptions(appearance: .constant(appearance.rawValue))
                .padding(.vertical, 16)
                .frame(width: width, height: 720, alignment: .top)
                .background(FottyTheme.background)
                .environment(\.colorScheme, scheme)
            // Render the actual choice component; offscreen UIKit ScrollViews
            // can be empty on Catalyst. Reject background-only false positives.
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage, label)
            XCTAssertEqual(image.size.width, width, accuracy: 1)
            let pixels = try XCTUnwrap(image.cgImage?.dataProvider?.data) as Data
            XCTAssertGreaterThan(Set(pixels).count, 16, "\(label) must contain rendered choices, not just a background")
            let attachment = XCTAttachment(image: image)
            attachment.name = label
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testAppearancePaletteContrastInBothModes() {
        func rgba(_ color: Color, _ style: UIUserInterfaceStyle) -> [Double] {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            XCTAssertTrue(UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a))
            return [Double(r), Double(g), Double(b), Double(a)]
        }
        func luminance(_ rgb: [Double]) -> Double {
            let linear = rgb.prefix(3).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        func contrast(_ first: [Double], _ second: [Double]) -> Double {
            let a = luminance(first), b = luminance(second)
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
        for style in [UIUserInterfaceStyle.dark, .light] {
            let base = rgba(FottyTheme.background, style)
            for color in [FottyTheme.textPrimary, FottyTheme.textSecondary, FottyTheme.accentText] {
                XCTAssertGreaterThanOrEqual(contrast(rgba(color, style), base), 7, "Home reading contrast, \(style.rawValue)")
            }
            for surface in [FottyTheme.background, FottyTheme.surface, FottyTheme.surfaceSubtle, FottyTheme.surfaceElevated] {
                for color in [FottyTheme.textPrimary, FottyTheme.textSecondary, FottyTheme.textTertiary, FottyTheme.accentText, FottyTheme.success, FottyTheme.error] {
                    XCTAssertGreaterThanOrEqual(contrast(rgba(color, style), rgba(surface, style)), 4.5, "Body/status text, \(style.rawValue)")
                }
            }
            XCTAssertGreaterThanOrEqual(contrast(rgba(FottyTheme.accent, style), rgba(FottyTheme.textOnAccent, style)), 7)
            XCTAssertGreaterThanOrEqual(contrast(rgba(FottyTheme.error, style), rgba(FottyTheme.textOnError, style)), 4.5)
            for difficulty in 0...5 {
                XCTAssertGreaterThanOrEqual(contrast(rgba(FottyFixtureDifficulty.foreground(difficulty), style), rgba(FottyFixtureDifficulty.background(difficulty), style)), 4.5)
            }
            for selected in [true, false] {
                let surface = rgba(SportActivityGrid.tileBackground(selected: selected), style)
                let painted = (0..<3).map { surface[$0] * surface[3] + base[$0] * (1 - surface[3]) }
                XCTAssertGreaterThanOrEqual(contrast(rgba(SportActivityGrid.tileForeground, style), painted), 7, "Selected: \(selected), style: \(style.rawValue)")
            }
        }
    }
}
