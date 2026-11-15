import XCTest
import SwiftUI
import UIKit
@testable import Fotty

/// Scene reservation and admission ordering, not physical first-frame or
/// decoded playback evidence. No test resolves or starts a media URL.
@MainActor
final class WatchTapAcknowledgementTests: XCTestCase {
    /// These are hosted layout checks, not frame-rate measurements or physical
    /// Dynamic Type acceptance. The UIKit trait and SwiftUI environment agree.
    private func hostedSize<Content: View>(of content: Content, width: CGFloat? = nil,
                                          type: DynamicTypeSize) -> CGSize {
        let host = UIHostingController(rootView: content
            .environment(\.dynamicTypeSize, type)
            .frame(width: width)
            .fixedSize(horizontal: width == nil, vertical: true))
        host.loadViewIfNeeded()
        switch type {
        case .xxxLarge:
            host.traitOverrides.preferredContentSizeCategory = .extraExtraExtraLarge
        case .accessibility3:
            host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraLarge
        default:
            host.traitOverrides.preferredContentSizeCategory = .large
        }
        return host.sizeThatFits(in: CGSize(width: width ?? 2_000, height: 2_000))
    }

    private func pendingAction(title: String, pending: Bool) -> some View {
        PendingWatchLabel(title: title, symbol: title == "Retry" ? "arrow.clockwise" : "play.fill",
                          isPending: pending)
            .font(FottyTheme.typeMeta.weight(.semibold))
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
    }

    private var longMatchInformation: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Brighton & Hove Albion Women")
            Text("Manchester United Women")
        }
        .font(FottyTheme.typeBody)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func testPendingWatchLabelKeepsItsIdleFootprintAcrossTitlesAndTextSizes() {
        for type in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
            for title in ["Watch", "Retry", "Watch channel"] {
                for (context, font) in [("row", FottyTheme.typeMeta.weight(.semibold)),
                                        ("hero", FottyTheme.typeAction)] {
                    func size(pending: Bool) -> CGSize {
                        hostedSize(of: PendingWatchLabel(title: title,
                            symbol: title == "Retry" ? "arrow.clockwise" : "play.fill", isPending: pending)
                            .font(font), type: type)
                    }
                    let idle = size(pending: false), pending = size(pending: true)
                    let message = "\(context) \(title) at \(type) must acknowledge Watch without moving its neighbours"
                    XCTAssertTrue(idle.width.isFinite && idle.height.isFinite)
                    XCTAssertGreaterThan(idle.width, 0)
                    XCTAssertGreaterThan(idle.height, 0)
                    XCTAssertEqual(pending.width, idle.width, accuracy: 0.5, message)
                    XCTAssertEqual(pending.height, idle.height, accuracy: 0.5, message)
                }
            }
        }
    }

    func testPendingWatchKeepsLongMatchRowsStableAtActualFitThresholdAndDeviceWidths() {
        let minimumInformationWidth: CGFloat = 150
        let spacing: CGFloat = 12
        for type in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
            for title in ["Watch", "Retry", "Watch channel"] {
                let action = hostedSize(of: pendingAction(title: title, pending: false), type: type)
                let threshold = minimumInformationWidth + spacing + action.width
                // Measure the genuine button rather than assuming a particular
                // font's pixel width. Both sides of the fit boundary matter.
                for width in [threshold - 1, threshold + 1, 288, 343, 788] {
                    func rowSize(pending: Bool) -> CGSize {
                        hostedSize(of: MatchRowLayout(minimumInformationWidth: minimumInformationWidth,
                            forceStack: type.isAccessibilitySize, spacing: spacing) {
                                longMatchInformation
                                pendingAction(title: title, pending: pending)
                            }, width: width, type: type)
                    }
                    let idle = rowSize(pending: false), pending = rowSize(pending: true)
                    let message = "\(title) at \(width)pt/\(type) must keep its wrapping and row height while pending"
                    XCTAssertEqual(idle.width, width, accuracy: 0.5)
                    XCTAssertEqual(pending.width, idle.width, accuracy: 0.5, message)
                    XCTAssertEqual(pending.height, idle.height, accuracy: 0.5, message)
                    XCTAssertTrue(pending.height.isFinite)
                    XCTAssertGreaterThanOrEqual(pending.height, 44)

                    // Guard against making equality pass by always stacking or
                    // imposing a fixed row height. Real width changes must still
                    // reflow, and accessibility rows intentionally remain stacked.
                    let horizontal = !type.isAccessibilitySize && width >= threshold
                    let informationWidth = horizontal ? width - spacing - action.width : width
                    let information = hostedSize(of: longMatchInformation, width: informationWidth, type: type)
                    let expectedHeight = horizontal ? max(information.height, action.height)
                        : information.height + spacing + action.height
                    XCTAssertEqual(idle.height, expectedHeight, accuracy: 1,
                                   "The production layout must still respect its real fit boundary")
                }
            }
        }
    }

    func testPendingControlStylePreservesReadableLabelWhileOrdinaryDisabledControlsStillDim() throws {
        for scheme in [ColorScheme.light, .dark] {
            func render(enabled: Bool, dimsWhenDisabled: Bool) throws -> UIImage {
                let content = Button {
                    XCTFail("A static label render must never activate Watch")
                } label: {
                    Label("Watch", systemImage: "play.fill")
                        .font(FottyTheme.typeMeta.weight(.semibold))
                        .foregroundStyle(FottyTheme.textOnAccent)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(FottyTheme.accent, in: Capsule())
                }
                .buttonStyle(FottyPressButtonStyle(dimsWhenDisabled: dimsWhenDisabled))
                .disabled(!enabled)
                .padding(8)
                .background(FottyTheme.surface)
                .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 1
                return try XCTUnwrap(renderer.uiImage)
            }
            let enabled = try render(enabled: true, dimsWhenDisabled: false)
            let pending = try render(enabled: false, dimsWhenDisabled: false)
            let ordinaryDisabled = try render(enabled: false, dimsWhenDisabled: true)
            XCTAssertEqual(enabled.size, pending.size)
            let enabledPixels = try FottyVisualPixelComparison.Pixels(image: enabled)
            let pendingComparison = try FottyVisualPixelComparison.compare(enabledPixels, .init(image: pending))
            XCTAssertTrue(pendingComparison.matches,
                          "A reserved Watch action stays readable while disabled: \(pendingComparison.description)")
            XCTAssertFalse(try FottyVisualPixelComparison.compare(enabledPixels,
                .init(image: ordinaryDisabled)).matches,
                "Ordinary unavailable controls must retain the style's disabled treatment")
        }
    }

    private func event(_ id: String = "watch-feedback", status: SportsFixtureCatalog.Status = .live,
                       conflict: Bool = false) -> EventReference {
        let now = Date(), fixtureID = "sports-fixture:premier-league:\(id)"
        let metadata = SportsFixtureMetadata(fixtureID: fixtureID, sport: "football",
            competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
            title: "Arsenal vs Chelsea", participants: [.init(id: "arsenal", name: "Arsenal"),
                .init(id: "chelsea", name: "Chelsea")], squad: .init(gender: .men, ageGroup: "senior"),
            status: status, observedAt: now, verified: true)
        return .init(id: fixtureID, title: metadata.title, category: "football",
            date: Int64(now.addingTimeInterval(-600).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Arsenal", badge: nil), away: .init(name: "Chelsea", badge: nil)), hasCatalogIdentityConflict: conflict,
            sportsFixture: metadata, competitionID: metadata.competitionID)
    }

    private func cancelled(_ request: StreamPlaybackRequest) -> StreamResolutionOutcome {
        let diagnostics = StreamAttemptDiagnostics(attemptID: "watch-feedback-test", matchID: request.matchID,
            matchTitle: request.displayTitle, finalState: .failed, createdAt: Date(), completedAt: Date(),
            timeline: [], providerAttempts: [])
        return .failure(.init(category: .userCancelled, technicalMessage: "Controlled test cancellation",
            userMessage: "Cancelled", retryable: false, fallbackAllowed: false), diagnostics)
    }

    private func waitFor(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("The bounded Watch operation did not finish", file: file, line: line)
    }

    func testWatchReservesVisiblePendingStateBeforeAdmissionOrDiscoveryAndDeduplicatesTaps() async throws {
        let row = event()
        var admissions = 0, lookups = 0
        let owner = ViewingSessionCoordinator(discoverSinglePlayback: { request, _ in
            lookups += 1
            return self.cancelled(request)
        }, currentSingleEvent: { $0 }, cancelPlayback: { _ in })
        defer { owner.stop() }
        owner.watchSingle(row, admission: { current in
            admissions += 1
            XCTAssertEqual(owner.pendingSingleEvent?.id, row.id)
            XCTAssertNotNil(owner.resolutionMessage)
            return current
        })
        XCTAssertEqual(owner.pendingSingleEvent?.id, row.id)
        XCTAssertNotNil(owner.resolutionMessage)
        XCTAssertEqual(admissions, 0, "Synchronous catalog admission must not precede acknowledgement")
        XCTAssertEqual(lookups, 0)
        owner.watchSingle(row, admission: { _ in XCTFail("A duplicate tap must reuse the pending owner"); return nil })
        try await waitFor { lookups == 1 && owner.pendingSingleEvent == nil }
        XCTAssertEqual(admissions, 1)
        XCTAssertEqual(lookups, 1)
        XCTAssertNil(owner.resolutionError)
    }

    func testCancelledPendingWatchDoesNotRunDelayedAdmissionOrDiscovery() async throws {
        let row = event("cancelled")
        var admissions = 0, lookups = 0
        let owner = ViewingSessionCoordinator(discoverSinglePlayback: { request, _ in
            lookups += 1; return self.cancelled(request)
        }, currentSingleEvent: { $0 }, cancelPlayback: { _ in })
        defer { owner.stop() }
        owner.watchSingle(row, admission: { current in admissions += 1; return current })
        XCTAssertNotNil(owner.pendingSingleEvent)
        owner.cancelPendingSingleDiscovery()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(admissions, 0)
        XCTAssertEqual(lookups, 0)
        XCTAssertNil(owner.pendingSingleEvent)
        XCTAssertNil(owner.resolutionMessage)
        XCTAssertNil(owner.resolutionError)
        XCTAssertTrue(owner.panes.isEmpty)
    }

    func testExpiredWatchActionAcknowledgesThenRejectsVisiblyWithoutResolving() async throws {
        let row = event("expired")
        var lookups = 0
        let owner = ViewingSessionCoordinator(discoverSinglePlayback: { request, _ in
            lookups += 1; return self.cancelled(request)
        }, currentSingleEvent: { _ in XCTFail("Denied caller admission must not reach current-event resolution"); return nil },
            cancelPlayback: { _ in })
        defer { owner.stop() }
        owner.watchSingle(row, admission: { _ in nil })
        XCTAssertEqual(owner.pendingSingleEvent?.id, row.id)
        XCTAssertNotNil(owner.resolutionMessage)
        try await waitFor { owner.resolutionError != nil }
        XCTAssertNil(owner.pendingSingleEvent)
        XCTAssertEqual(lookups, 0)
        XCTAssertTrue(owner.panes.isEmpty)
    }

    func testTerminalOrConflictingCurrentFixtureCannotStartAfterAcknowledgement() async throws {
        for current in [event("stopped", status: .finished), event("stopped", conflict: true)] {
            let row = event("stopped")
            var lookups = 0
            let owner = ViewingSessionCoordinator(discoverSinglePlayback: { request, _ in
                lookups += 1; return self.cancelled(request)
            }, currentSingleEvent: { _ in current }, cancelPlayback: { _ in })
            defer { owner.stop() }
            owner.watchSingle(row, admission: { $0 })
            XCTAssertNotNil(owner.pendingSingleEvent)
            try await waitFor { owner.resolutionError != nil }
            XCTAssertEqual(lookups, 0)
            XCTAssertTrue(owner.panes.isEmpty)
        }
    }

    func testSupersedingWatchCannotPublishOrResolveTheEarlierTap() async throws {
        let first = event("first"), second = event("second")
        var admitted: [String] = [], resolved: [String] = []
        let owner = ViewingSessionCoordinator(discoverSinglePlayback: { request, _ in
            resolved.append(request.matchID); return self.cancelled(request)
        }, currentSingleEvent: { $0 }, cancelPlayback: { _ in })
        defer { owner.stop() }
        owner.watchSingle(first, admission: { current in admitted.append(current.id); return current })
        owner.watchSingle(second, admission: { current in admitted.append(current.id); return current })
        XCTAssertEqual(owner.pendingSingleEvent?.id, second.id)
        try await waitFor { resolved == [second.id] && owner.pendingSingleEvent == nil }
        XCTAssertEqual(admitted, [second.id])
        XCTAssertNil(owner.resolutionError)
    }

    func testCancellationDuringAdmissionCannotPublishAStaleErrorOrReachDiscovery() async throws {
        let row = event("cancel-during-admission")
        var admissions = 0, lookups = 0
        let owner = ViewingSessionCoordinator(discoverSinglePlayback: { request, _ in
            lookups += 1; return self.cancelled(request)
        }, currentSingleEvent: { _ in XCTFail("Cancelled admission must not continue"); return nil }, cancelPlayback: { _ in })
        defer { owner.stop() }
        owner.watchSingle(row, admission: { _ in
            admissions += 1
            owner.cancelPendingSingleDiscovery()
            return nil
        })
        try await waitFor { admissions == 1 }
        XCTAssertEqual(lookups, 0)
        XCTAssertNil(owner.pendingSingleEvent)
        XCTAssertNil(owner.resolutionError)
    }

    func testTVDefersCurrentCatalogReadUntilPendingFeedbackExists() async throws {
        let row = try XCTUnwrap(SportsTVStation.station(provider: "TV2")).event
        var catalogReads = 0, lookups = 0
        let owner = ViewingSessionCoordinator(discoverSinglePlayback: { request, _ in
            lookups += 1; return self.cancelled(request)
        }, currentSingleEvent: { $0 }, cancelPlayback: { _ in })
        defer { owner.stop() }
        SportsTVWatchPolicy.watch(row, using: owner, currentCatalog: {
            catalogReads += 1
            XCTAssertEqual(owner.pendingSingleEvent?.id, row.id)
            XCTAssertNotNil(owner.resolutionMessage)
            return []
        })
        XCTAssertEqual(catalogReads, 0)
        XCTAssertEqual(owner.pendingSingleEvent?.id, row.id)
        try await waitFor { lookups == 1 && owner.pendingSingleEvent == nil }
        XCTAssertEqual(catalogReads, 1)
    }
}
