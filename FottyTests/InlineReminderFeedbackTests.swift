import XCTest
@testable import Fotty

@MainActor
final class InlineReminderFeedbackTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ eventID: String = "match", offset: TimeInterval = 0) throws -> MatchReminderRecord {
        let event = AnalyticalDataEngine.EventReference(id: eventID, title: "Home vs Away", category: "cricket",
            date: Int64(now.addingTimeInterval(7_200 + offset).timeIntervalSince1970),
            poster: nil, popular: nil, teams: nil, sources: [])
        return try XCTUnwrap(MatchReminderRecord.make(event: event, now: now))
    }

    func testConfirmationRequiresAcceptedResultAndItsOwnStoreRevision() throws {
        let current = try record()
        for revision in [3, 5] {
            var state = InlineReminderFeedbackState()
            let operation = state.begin(eventID: current.id, previousRecord: nil, intentRevision: 3,
                enablesReminder: true)
            state.complete(operation, result: .scheduled, currentRecord: current, intentRevision: revision)
            XCTAssertNil(state.notice, "An earlier/later store operation cannot confirm this row's request")
            XCTAssertNil(state.operation)
        }

        var state = InlineReminderFeedbackState()
        let operation = state.begin(eventID: current.id, previousRecord: nil, intentRevision: 3,
            enablesReminder: true)
        state.complete(operation, result: .scheduled, currentRecord: nil, intentRevision: 4)
        XCTAssertNil(state.notice, "A nominal success without a current reminder must not offer Undo")
    }

    func testLaterActionRejectsEarlierAsyncSuccessAndFailure() throws {
        let current = try record()
        var state = InlineReminderFeedbackState()
        let earlier = state.begin(eventID: current.id, previousRecord: nil, intentRevision: 0,
            enablesReminder: true)
        let later = state.begin(eventID: current.id, previousRecord: current, intentRevision: 1,
            enablesReminder: false)
        state.complete(later, result: .cancelled, currentRecord: nil, intentRevision: 2)
        let noticeID = try XCTUnwrap(state.notice?.id)
        state.complete(earlier, result: .scheduled, currentRecord: current, intentRevision: 1)
        state.complete(earlier, result: .denied, currentRecord: nil, intentRevision: 2)
        XCTAssertEqual(state.notice?.id, noticeID)
        XCTAssertEqual(state.notice?.isEnabled, false)
        XCTAssertNil(state.failure)
    }

    func testRowIdentityChangeAndDisappearanceRejectLateConfirmation() throws {
        let current = try record()
        for replacement in ["different-match", nil] as [String?] {
            var state = InlineReminderFeedbackState()
            let operation = state.begin(eventID: current.id, previousRecord: nil, intentRevision: 0,
                enablesReminder: true)
            state.reset(eventID: replacement)
            state.complete(operation, result: .scheduled, currentRecord: current, intentRevision: 1)
            XCTAssertNil(state.notice)
            XCTAssertNil(state.failure)
            XCTAssertNil(state.operation)
        }
    }

    func testUndoRestoresPreviousIntentOnceWithoutOfferingUndoOfUndo() throws {
        let current = try record()
        var state = InlineReminderFeedbackState()
        let enabled = state.begin(eventID: current.id, previousRecord: nil, intentRevision: 0,
            enablesReminder: true)
        state.complete(enabled, result: .scheduled, currentRecord: current, intentRevision: 1)
        let notice = try XCTUnwrap(state.notice)
        let undo = try XCTUnwrap(state.consumeUndo(noticeID: notice.id, eventID: current.id,
            currentRecord: current, intentRevision: 1))
        XCTAssertNil(undo.operation.previousRecord, "Undo of enabling only cancels the reminder intent")
        XCTAssertNil(state.consumeUndo(noticeID: notice.id, eventID: current.id,
            currentRecord: current, intentRevision: 1))

        let cancelled = state.begin(eventID: current.id, previousRecord: current, intentRevision: 1,
            enablesReminder: false, isUndo: true)
        state.complete(cancelled, result: .cancelled, currentRecord: nil, intentRevision: 2)
        XCTAssertEqual(state.notice?.canUndo, false)
        XCTAssertEqual(state.notice?.detail, "The match stays saved in My Matchday.")
    }

    func testUndoCancellationKeepsOriginalReminderSnapshotAndPermissionFailureTruth() throws {
        let previous = try record()
        var state = InlineReminderFeedbackState()
        let cancelled = state.begin(eventID: previous.id, previousRecord: previous, intentRevision: 7,
            enablesReminder: false)
        state.complete(cancelled, result: .cancelled, currentRecord: nil, intentRevision: 8)
        let notice = try XCTUnwrap(state.notice)
        let undo = try XCTUnwrap(state.consumeUndo(noticeID: notice.id, eventID: previous.id,
            currentRecord: nil, intentRevision: 8))
        XCTAssertEqual(undo.operation.previousRecord, previous)
        let restore = state.begin(eventID: previous.id, previousRecord: nil, intentRevision: 8,
            enablesReminder: true, isUndo: true)
        state.complete(restore, result: .denied, currentRecord: nil, intentRevision: 9)
        XCTAssertNil(state.notice)
        XCTAssertEqual(state.failure, .denied, "The UI must still offer notification settings")
    }

    func testUndoRejectsAnotherRowsABAChangeEvenWhenRecordIsIdentical() throws {
        let current = try record()
        var state = InlineReminderFeedbackState()
        let operation = state.begin(eventID: current.id, previousRecord: nil, intentRevision: 0,
            enablesReminder: true)
        state.complete(operation, result: .scheduled, currentRecord: current, intentRevision: 1)
        let notice = try XCTUnwrap(state.notice)
        XCTAssertNil(state.consumeUndo(noticeID: notice.id, eventID: current.id,
            currentRecord: current, intentRevision: 3), "Cancel/re-enable elsewhere is newer user intent")
        XCTAssertNil(state.notice)
    }

    func testReconciliationAndNewIntentRemoveStaleNotices() throws {
        let current = try record()
        let rescheduled = try record(offset: 300)
        for (record, revision) in [(rescheduled, 1), (current, 2)] {
            var state = InlineReminderFeedbackState()
            let operation = state.begin(eventID: current.id, previousRecord: nil, intentRevision: 0,
                enablesReminder: true)
            state.complete(operation, result: .scheduled, currentRecord: current, intentRevision: 1)
            state.invalidateChangedIntent(currentRecord: record, intentRevision: revision)
            XCTAssertNil(state.notice)
        }
    }

    func testDismissAndConsumedTokenCannotBeReplayed() throws {
        let current = try record()
        var state = InlineReminderFeedbackState()
        let operation = state.begin(eventID: current.id, previousRecord: nil, intentRevision: 0,
            enablesReminder: true)
        state.complete(operation, result: .scheduled, currentRecord: current, intentRevision: 1)
        let noticeID = try XCTUnwrap(state.notice?.id)
        state.dismiss(noticeID: noticeID)
        state.complete(operation, result: .scheduled, currentRecord: current, intentRevision: 1)
        XCTAssertNil(state.notice)
        XCTAssertNil(state.consumeUndo(noticeID: noticeID, eventID: current.id,
            currentRecord: current, intentRevision: 1))
    }

    func testFailuresStayVisibleAndSupersededEnableDoesNotClaimCancellation() throws {
        for result: MatchReminderStore.Result in [.denied, .tooLate, .limitReached, .failed, .cancelled] {
            var state = InlineReminderFeedbackState()
            let operation = state.begin(eventID: "match", previousRecord: nil, intentRevision: 0,
                enablesReminder: true)
            state.complete(operation, result: result, currentRecord: nil, intentRevision: 1)
            XCTAssertNil(state.notice)
            XCTAssertEqual(state.failure, result == .cancelled ? nil : result)
        }
    }

    func testUndoCannotRestoreCancelledCurrentFixtureAndConsumesItsNotice() throws {
        let oldEvent = fixtureEvent(status: .scheduled)
        let previous = try XCTUnwrap(MatchReminderRecord.make(event: oldEvent, now: now))
        var state = InlineReminderFeedbackState()
        let cancellation = state.begin(eventID: previous.id, previousRecord: previous, intentRevision: 0,
            enablesReminder: false)
        state.complete(cancellation, result: .cancelled, currentRecord: nil, intentRevision: 1)
        let notice = try XCTUnwrap(state.notice)
        _ = try XCTUnwrap(state.consumeUndo(noticeID: notice.id, eventID: previous.id,
            currentRecord: nil, intentRevision: 1))
        guard case .unavailable(let failure) = InlineReminderFeedbackState.restoration(previous: previous,
            currentEvent: fixtureEvent(status: .cancelled), now: now) else {
            return XCTFail("A current cancelled fixture must not re-enable its obsolete scheduled reminder")
        }
        state.showFailure(failure, eventID: previous.id)
        XCTAssertEqual(state.failure, .failed)
        XCTAssertNil(state.notice)
        XCTAssertNil(state.consumeUndo(noticeID: notice.id, eventID: previous.id,
            currentRecord: nil, intentRevision: 1))
    }

    func testUndoRejectsConflictingCurrentFixtureWithTheSameID() throws {
        let previous = try XCTUnwrap(MatchReminderRecord.make(event: fixtureEvent(), now: now))
        let conflicting = fixtureEvent(away: "Different Club")
        XCTAssertEqual(conflicting.id, previous.id)
        guard case .unavailable(let failure) = InlineReminderFeedbackState.restoration(previous: previous,
            currentEvent: conflicting, now: now) else {
            return XCTFail("A reused ID is not proof of the same fixture")
        }
        XCTAssertEqual(failure, .failed)
    }

    func testUndoAdmitsRescheduledCurrentFixtureAndUsesItsNewKickoff() throws {
        let previous = try XCTUnwrap(MatchReminderRecord.make(event: fixtureEvent(), now: now))
        let rescheduled = fixtureEvent(secondsUntilStart: 14_400)
        guard case .enable(let accepted) = InlineReminderFeedbackState.restoration(previous: previous,
            currentEvent: rescheduled, now: now) else {
            return XCTFail("The same fixture may follow an accepted reschedule")
        }
        XCTAssertEqual(accepted.kickoffDate, rescheduled.kickoffDate)
        XCTAssertNotEqual(accepted.kickoffDate, previous.snapshot.event.kickoffDate)
        let restored = try XCTUnwrap(MatchReminderRecord.make(event: accepted, now: now))
        XCTAssertEqual(restored.fireDate, now.addingTimeInterval(14_400 - MatchStartPolicy.reminderLead))
    }

    func testUndoRechecksFiveMinuteBoundaryAndOfficialStoppedStatusAtTapTime() throws {
        let current = fixtureEvent()
        let previous = try XCTUnwrap(MatchReminderRecord.make(event: current, now: now))
        guard case .unavailable(let boundary) = InlineReminderFeedbackState.restoration(previous: previous,
            currentEvent: current, now: now.addingTimeInterval(6_900)) else {
            return XCTFail("An expired Undo cannot create an immediate notification")
        }
        XCTAssertEqual(boundary, .tooLate)
        guard case .unavailable(let stopped) = InlineReminderFeedbackState.restoration(previous: previous,
            currentEvent: current, status: .cancelled, now: now) else {
            return XCTFail("Current official stopped status must override an old scheduled row")
        }
        XCTAssertEqual(stopped, .failed)
    }

    private func fixtureEvent(status: SportsFixtureCatalog.Status = .scheduled,
                              secondsUntilStart: TimeInterval = 7_200,
                              away: String = "Away Club") -> AnalyticalDataEngine.EventReference {
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:reminder-undo", sport: "football",
            competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
            title: "Home Club vs \(away)", participants: [
                .init(id: "home", name: "Home Club", role: "home"),
                .init(id: away, name: away, role: "away")],
            squad: .init(gender: .men, ageGroup: "senior"), status: status, observedAt: now, verified: true)
        return .init(id: metadata.fixtureID, title: metadata.title, category: "football",
            date: Int64(now.addingTimeInterval(secondsUntilStart).timeIntervalSince1970),
            poster: nil, popular: nil,
            teams: .init(home: .init(name: "Home Club", badge: nil), away: .init(name: away, badge: nil)),
            sources: [], sportsFixture: metadata, competitionID: metadata.competitionID)
    }
}
