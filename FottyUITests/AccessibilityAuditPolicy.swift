import XCTest

/// Exceptions are narrowly scoped to observed Catalyst 27 sampling issues.
/// iOS/iPadOS and future toolchains fail closed; uppercase copy is never artwork.
enum FottyAccessibilityAuditPolicy {
    static func ignoresDynamicType(
        identifier: String, label: String, isStaticText: Bool,
        frame: CGRect, isCatalyst: Bool, osMajor: Int
    ) -> Bool {
        isCatalyst && osMajor == 27 && isStaticText
            && identifier == "team-badge-decorative-initials"
            && (1...3).contains(label.count) && label == label.uppercased()
            && frame.width <= 48 && frame.height <= 48
    }

    static func ignoresContrast(
        identifier: String, label: String, isStaticText: Bool,
        frame: CGRect, isCatalyst: Bool, osMajor: Int
    ) -> Bool {
        guard isCatalyst, osMajor == 27, isStaticText else { return false }
        if ignoresDynamicType(identifier: identifier, label: label, isStaticText: true,
                              frame: frame, isCatalyst: true, osMajor: osMajor) { return true }
        // Fixed theme pairs have pixel/contrast coverage. Do not infer an
        // exemption from position below the dock, a label, or a prefix alone.
        let reviewedIdentifiers: Set<String> = [
            "dashboard-team-name", "dashboard-empty-state-message",
            "dashboard-empty-refresh-label", "dashboard-home-interests-edit",
            "dashboard-event-status", "dashboard-event-competition",
            "home-discovery-heading", "match-start-action-label",
            "match-start-countdown-label", "match-reminder-label"
        ]
        let reviewedSportIDs: Set<String> = [
            "all-sports", "football", "cricket", "baseball", "basketball",
            "hockey", "american-football", "tennis", "rugby", "fight",
            "motorsport", "golf", "other"
        ]
        return reviewedIdentifiers.contains(identifier)
            || reviewedSportIDs.contains {
                identifier == "home-sport-color-\($0)-title"
                    || identifier == "home-sport-color-\($0)-summary"
            }
    }
}

final class AccessibilityAuditPolicyTests: XCTestCase {
    private let badgeFrame = CGRect(x: 0, y: 0, width: 32, height: 32)

    func testDeviceContrastNeverUsesCatalystExceptions() {
        XCTAssertFalse(FottyAccessibilityAuditPolicy.ignoresContrast(
            identifier: "dashboard-team-name", label: "Man United", isStaticText: true,
            frame: badgeFrame, isCatalyst: false, osMajor: 27))
    }

    func testOnlyReviewedCatalystVersionCanIgnoreSampling() {
        XCTAssertTrue(FottyAccessibilityAuditPolicy.ignoresContrast(
            identifier: "dashboard-team-name", label: "Man United", isStaticText: true,
            frame: badgeFrame, isCatalyst: true, osMajor: 27))
        XCTAssertFalse(FottyAccessibilityAuditPolicy.ignoresContrast(
            identifier: "dashboard-team-name", label: "Man United", isStaticText: true,
            frame: badgeFrame, isCatalyst: true, osMajor: 28))
    }

    func testUppercaseStatusOrHeadingIsNotDecorativeArtwork() {
        for label in ["LIVE", "TODAY", "FPL", "PLAY", "SETTINGS", "WATCH NOW"] {
            XCTAssertFalse(FottyAccessibilityAuditPolicy.ignoresDynamicType(
                identifier: "", label: label, isStaticText: true,
                frame: badgeFrame, isCatalyst: true, osMajor: 27))
        }
    }

    func testBadgeExceptionRequiresExactIdentityAndSmallStaticText() {
        XCTAssertTrue(FottyAccessibilityAuditPolicy.ignoresDynamicType(
            identifier: "team-badge-decorative-initials", label: "MU", isStaticText: true,
            frame: badgeFrame, isCatalyst: true, osMajor: 27))
        XCTAssertFalse(FottyAccessibilityAuditPolicy.ignoresDynamicType(
            identifier: "team-badge-decorative-initials", label: "MU", isStaticText: true,
            frame: CGRect(x: 0, y: 0, width: 100, height: 32), isCatalyst: true, osMajor: 27))
        XCTAssertFalse(FottyAccessibilityAuditPolicy.ignoresDynamicType(
            identifier: "team-badge-decorative-initials", label: "MU", isStaticText: false,
            frame: badgeFrame, isCatalyst: true, osMajor: 27))
        XCTAssertFalse(FottyAccessibilityAuditPolicy.ignoresDynamicType(
            identifier: "team-badge-decorative-initials", label: "MU", isStaticText: true,
            frame: badgeFrame, isCatalyst: false, osMajor: 27))
    }

    func testUnreviewedSportPrefixDoesNotBypassContrast() {
        XCTAssertFalse(FottyAccessibilityAuditPolicy.ignoresContrast(
            identifier: "home-sport-color-unknown-new-label", label: "Unknown", isStaticText: true,
            frame: badgeFrame, isCatalyst: true, osMajor: 27))
    }
}
