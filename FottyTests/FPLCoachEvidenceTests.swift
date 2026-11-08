import XCTest
@testable import Fotty

final class FPLCoachEvidenceTests: XCTestCase {
    func testStrategyAssuranceIsNotPresentedAsMeasuredAccuracyOrVerifiedRoute() {
        let card = card(source: "DeepSeek")
        XCTAssertTrue(card.isModelJudgment)
        XCTAssertEqual(card.evidenceHeading, "Evidence cited by Coach")
        XCTAssertEqual(card.confidenceLabel, "High model confidence")
        XCTAssertTrue(card.assuranceNote.contains("not measured accuracy"))
        XCTAssertTrue(card.assuranceNote.contains("do not verify every claim"))
        XCTAssertTrue(card.assuranceNote.contains("Transfer Lab"))
    }

    func testDeterministicEvidenceKeepsSeparateLabelAndProvisionalBoundary() {
        let card = card(source: "Fotty rules engine")
        XCTAssertFalse(card.isModelJudgment)
        XCTAssertEqual(card.evidenceHeading, "Calculation evidence")
        XCTAssertFalse(card.confidenceLabel.contains("model"))
        XCTAssertTrue(card.assuranceNote.contains("not a prediction"))
        XCTAssertTrue(card.assuranceNote.contains("provisional"))
    }

    func testOldPersistedCardsDecodeAndReceiveHonestLabelsWithoutMigration() throws {
        let data = Data(#"{"answer":"Hold","confidence":"high","evidence":["Current price"],"downside":[],"verifyBeforeDeadline":[],"source":"DeepSeek","officialDataStatus":"fresh"}"#.utf8)
        let decoded = try JSONDecoder().decode(FPLCoachCardPayload.self, from: data)
        XCTAssertEqual(decoded.evidenceHeading, "Evidence cited by Coach")
        XCTAssertNil(decoded.verifiedAt)
    }

    func testHistoricalRecheckUsesOriginalUserQuestionNotModelAdviceOrNewerContext() {
        let original = AICoachMessage(sender: .user, text: "Should I buy Leif Davis?")
        let answer = AICoachMessage(sender: .coach, text: "Buy Harry Kane, guaranteed points", coachCard: card(source: "DeepSeek"))
        let newer = AICoachMessage(sender: .user, text: "What about Lewis-Potter?")
        let history = [original, answer, newer]
        XCTAssertEqual(FPLCoachRecheck.question(for: answer, in: history), original.text)
        XCTAssertEqual(history[1].coachCard?.verifiedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(history.count, 3, "Preparing a recheck must not rewrite historical advice")
    }

    func testHistoricalPronounRecheckCarriesItsImmediateUserAntecedent() {
        let earlier = AICoachMessage(sender: .user, text: "Compare Leif Davis and João Gomes")
        let hallucination = AICoachMessage(sender: .coach, text: "Harry Kane is available")
        let followup = AICoachMessage(sender: .user, text: "What about their minutes?")
        let answer = AICoachMessage(sender: .coach, text: "Old answer")
        let newer = AICoachMessage(sender: .user, text: "Consider Lewis-Potter")
        let query = FPLCoachRecheck.question(for: answer, in: [earlier, hallucination, followup, answer, newer])
        XCTAssertEqual(query, "What about their minutes?\nEarlier question: Compare Leif Davis and João Gomes")
        XCTAssertFalse(query?.contains("Harry Kane") == true)
        XCTAssertFalse(query?.contains("Lewis-Potter") == true)
    }

    func testRecheckCannotInventMissingQuestionOrSilentlyTruncateIdentityContext() {
        let answer = AICoachMessage(sender: .coach, text: "Historical answer")
        XCTAssertNil(FPLCoachRecheck.question(for: answer, in: [answer]))
        let oversized = AICoachMessage(sender: .user, text: String(repeating: "x", count: 1_201))
        XCTAssertNil(FPLCoachRecheck.question(for: answer, in: [oversized, answer]))
        XCTAssertNil(FPLCoachRecheck.question(for: oversized, in: [oversized, answer]))
    }

    private func card(source: String) -> FPLCoachCardPayload {
        FPLCoachCardPayload(answer: "Hold", confidence: "high", evidence: ["Official player price"],
            downside: ["Minutes uncertain"], verifyBeforeDeadline: ["Check availability"], source: source,
            officialDataStatus: "fresh", verifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
}
