import XCTest
@testable import Fotty

final class SharedStreamDiscoveryTests: XCTestCase {
    private typealias Candidate = AnalyticalDataEngine.StreamCandidate

    func testValidMirrorArrivingAfterFourSecondsIsNotDiscarded() async {
        let report = await SharedStreamDiscovery.collect(descriptors: [descriptor("hotel") { _ in
            try? await Task.sleep(for: .milliseconds(4100))
            guard !Task.isCancelled else { return [] }
            return [self.candidate("hotel")]
        }], validate: { self.success($0) }, report: { _ in })
        XCTAssertEqual(report.sessions.count, 1)
        XCTAssertFalse(report.failures.contains { $0.category == .providerTimeout })
    }

    func testParentCancellationCancelsActualMirroredURLSessionTasks() async {
        let began = expectation(description: "Three URLSession mirror requests started")
        began.expectedFulfillmentCount = 3
        let stopped = expectation(description: "Three URLSession mirror requests cancelled")
        stopped.expectedFulfillmentCount = 3
        let returned = expectation(description: "Collector returned after transport cancellation")
        let session = hangingSession(onStart: { began.fulfill() }, onStop: { stopped.fulfill() })
        defer { session.invalidateAndCancel(); DiscoveryHangingProtocol.reset() }
        let work = Task {
            _ = await SharedStreamDiscovery.collect(descriptors: [descriptor("hotel") { _ in
                await self.hangingMirrors(session: session)
            }], validate: { self.success($0) }, report: { _ in })
            returned.fulfill()
        }
        await fulfillment(of: [began], timeout: 2)
        work.cancel()
        await fulfillment(of: [stopped, returned], timeout: 2)
    }

    func testOverallDeadlineCancelsActualMirroredURLSessionTasks() async {
        let began = expectation(description: "Three URLSession mirror requests started")
        began.expectedFulfillmentCount = 3
        let stopped = expectation(description: "Deadline cancelled three URLSession mirror requests")
        stopped.expectedFulfillmentCount = 3
        let returned = expectation(description: "Overall collector returned")
        let session = hangingSession(onStart: { began.fulfill() }, onStop: { stopped.fulfill() })
        defer { session.invalidateAndCancel(); DiscoveryHangingProtocol.reset() }
        let work = Task {
            let result = await StreamDiscoveryCoordinator.collect(lanes: [{ _ in
                let partial = await SharedStreamDiscovery.collect(descriptors: [self.descriptor("hotel") { _ in
                    await self.hangingMirrors(session: session)
                }], validate: { self.success($0) }, report: { _ in })
                return self.outcome(partial.sessions)
            }], deadline: .milliseconds(250))
            XCTAssertTrue(result.reachedDeadline)
            returned.fulfill()
        }
        await fulfillment(of: [began, stopped, returned], timeout: 3)
        work.cancel()
    }

    @MainActor
    func testOptionalLateCatalogTimeoutRetainsOnlyAnAdmittedPreferredEvent() async throws {
        let kickoff = Date()
        let preferred = fixture(kickoff: kickoff, away: "Liverpool")
        let request = StreamPlaybackRequest(event: preferred)
        let resolver = LiveStreamResolver()
        let activity = DiscoveryTestActivity()
        let result = try await resolver.resolveCatalogEvent(for: request, fetch: { budget in
            XCTAssertEqual(budget, .milliseconds(10))
            activity.begin("catalog", key: "refresh")
            defer { activity.end("catalog") }
            try await Task.sleep(for: budget)
            // The typed collector throws when its budget expires without any
            // completed observation. The resolver does not own another timer.
            throw URLError(.timedOut)
        }, lateRefreshTimeout: .milliseconds(10))
        XCTAssertEqual(result?.id, preferred.id)
        XCTAssertEqual(activity.active("catalog"), 0)

        // A mismatched preferred event cannot become fallback authority, and
        // this cold path is allowed to outlive the optional-refresh-only slice.
        let wrong = fixture(kickoff: kickoff, away: "Chelsea")
        let cold = StreamPlaybackRequest(matchID: preferred.id, displayTitle: "Ipswich Town vs Liverpool",
            homeTeam: "Ipswich Town", awayTeam: "Liverpool", category: "football", kickoffDate: kickoff,
            preferredEvent: wrong)
        let fresh = try await resolver.resolveCatalogEvent(for: cold, fetch: { budget in
            XCTAssertEqual(budget, .seconds(7))
            try await Task.sleep(for: .milliseconds(30))
            return [preferred]
        }, lateRefreshTimeout: .milliseconds(1))
        XCTAssertEqual(fresh?.awayName, "Liverpool")
    }

    @MainActor
    func testFreshConflictingIdentityStillQuarantinesPreferredCatalogFallback() async throws {
        let kickoff = Date()
        let preferred = fixture(kickoff: kickoff, away: "Liverpool")
        let conflict = fixture(kickoff: kickoff, away: "Chelsea")
        let resolver = LiveStreamResolver()
        let result = try await resolver.resolveCatalogEvent(for: StreamPlaybackRequest(event: preferred),
            fetch: { _ in [conflict] }, lateRefreshTimeout: .seconds(1))
        XCTAssertNil(result)
    }

    @MainActor
    func testPartialCatalogConflictAtOptionalDeadlineCannotRevivePreferredEvent() async throws {
        let kickoff = Date()
        let preferred = fixture(kickoff: kickoff, away: "Liverpool")
        let conflict = fixture(kickoff: kickoff, away: "Chelsea")
        let accumulator = LiveCatalogAccumulator(sources: ["first", "fallback", "pending"])
        accumulator.record([preferred], source: "first")
        accumulator.record([conflict], source: "fallback", fallbackPart: "live")
        let partial = try LiveCatalogSnapshot.combine(accumulator.observations)
        XCTAssertTrue(partial.isPartial)
        XCTAssertTrue(partial.events.contains(where: \.hasCatalogIdentityConflict))
        let observedRows = partial.events

        let result = try await LiveStreamResolver().resolveCatalogEvent(
            for: StreamPlaybackRequest(event: preferred), fetch: { budget in
                XCTAssertEqual(budget, .milliseconds(10))
                try await Task.sleep(for: budget)
                // Return the completed evidence when the collector's own timer
                // expires, even though a complementary feed remains unfinished.
                return observedRows
            }, lateRefreshTimeout: .milliseconds(10))
        XCTAssertNil(result)
    }

    @MainActor
    func testCancellingOptionalCatalogRefreshDoesNotReturnPreferredEvent() async throws {
        let preferred = fixture(kickoff: Date(), away: "Liverpool")
        let began = expectation(description: "Optional catalog refresh began")
        let work = Task {
            try await LiveStreamResolver().resolveCatalogEvent(
                for: StreamPlaybackRequest(event: preferred), fetch: { _ in
                    began.fulfill()
                    try await Task.sleep(for: .seconds(60))
                    return []
                })
        }
        await fulfillment(of: [began], timeout: 1)
        work.cancel()
        do {
            _ = try await work.value
            XCTFail("A cancelled request must not revive its preferred event")
        } catch is CancellationError {
            // Expected: cancellation belongs to the navigation/playback owner.
        }
    }

    func testFastMirrorIsValidatedBeforeItsSlowSiblingFinishes() async {
        let slowMirror = DiscoveryTestGate()
        let validated = expectation(description: "Fast mirror validated while sibling is pending")
        let candidate = candidate("hotel")
        let work = Task {
            await SharedStreamDiscovery.collect(descriptors: [descriptor("hotel") { publish in
                publish(.candidates([candidate]))
                await slowMirror.wait()
                return [candidate]
            }], validate: { self.success($0) }, report: { update in
                if case .validated(_, .success, _, true) = update { validated.fulfill() }
            })
        }
        await fulfillment(of: [validated], timeout: 1)
        XCTAssertFalse(slowMirror.isOpen)
        slowMirror.open()
        let report = await work.value
        XCTAssertEqual(report.sessions.count, 1)
        XCTAssertEqual(report.startedValidations, 1)
    }

    func testSlowFirstDescriptorsReleaseBoundedSlotsForLaterHealthyFamily() async {
        let activity = DiscoveryTestActivity()
        var limits = SharedStreamDiscovery.Limits()
        limits.concurrentLookups = 2
        limits.lookupTime = .milliseconds(20)
        let descriptors = (0..<6).map { index in
            descriptor("family\(index)") { _ in
                activity.begin("lookup", key: String(index))
                defer { activity.end("lookup") }
                if index == 5 { return [self.candidate("healthy")] }
                try? await Task.sleep(for: .seconds(60))
                return []
            }
        }
        let report = await SharedStreamDiscovery.collect(descriptors: descriptors, limits: limits,
            validate: { self.success($0) }, report: { _ in })
        XCTAssertEqual(report.sessions.first?.providerName, "healthy")
        XCTAssertEqual(activity.keys("lookup").count, 6)
        XCTAssertLessThanOrEqual(activity.maximum("lookup"), 2)
        XCTAssertEqual(activity.active("lookup"), 0)
        XCTAssertEqual(report.failures.filter { $0.category == .providerTimeout }.count, 5)
    }

    func testPendingValidationCannotBlockAnotherDescriptor() async {
        let gate = DiscoveryTestGate()
        let healthy = expectation(description: "Other descriptor validated")
        let activity = DiscoveryTestActivity()
        let candidates = [candidate("slow", suffix: "one"), candidate("slow", suffix: "two")]
        let work = Task {
            await SharedStreamDiscovery.collect(descriptors: [
                descriptor("slow") { _ in candidates },
                descriptor("healthy") { _ in [self.candidate("healthy")] }
            ], validate: { candidate in
                activity.begin("validation", key: candidate.sourceCode)
                defer { activity.end("validation") }
                if candidate.sourceCode == "slow" { await gate.wait() }
                return self.success(candidate)
            }, report: { update in
                if case .validated(let candidate, .success, _, true) = update, candidate.sourceCode == "healthy" {
                    healthy.fulfill()
                }
            })
        }
        await fulfillment(of: [healthy], timeout: 1)
        XCTAssertFalse(gate.isOpen)
        XCTAssertEqual(activity.keys("validation").filter { $0 == "slow" }.count, 1)
        gate.open()
        let report = await work.value
        XCTAssertEqual(report.sessions.count, 3)
        XCTAssertLessThanOrEqual(activity.maximum("validation"), 3)
    }

    func testCandidateBudgetReservesFirstChanceForEveryDescriptor() async {
        let others = DiscoveryTestGate()
        var limits = SharedStreamDiscovery.Limits()
        limits.validations = 3
        let first = (0..<8).map { candidate("first", suffix: String($0)) }
        let report = await SharedStreamDiscovery.collect(descriptors: [
            descriptor("first") { _ in first },
            descriptor("second") { _ in await others.wait(); return [self.candidate("second")] },
            descriptor("third") { _ in await others.wait(); return [self.candidate("third")] }
        ], limits: limits, validate: { candidate in
            if candidate.sourceCode == "first" { others.open() }
            return self.success(candidate)
        }, report: { _ in })
        XCTAssertEqual(Set(report.sessions.map(\.providerName)), ["first", "second", "third"])
        XCTAssertEqual(report.startedValidations, 3)
    }

    func testTwoResultSlotsRetainLateIndependentFamilyAfterThreeFastSiblings() async {
        let (report, activity) = await reservedFamilyScenario(capacity: 2, fastChoices: 3)
        XCTAssertEqual(report.sessions.count, 2)
        XCTAssertEqual(Set(report.sessions.map(\.providerName)), ["first", "second"])
        XCTAssertEqual(activity.keys("published").count, 2)
    }

    func testSixResultSlotsRetainLateIndependentFamilyAfterSixFastSiblings() async {
        let (report, activity) = await reservedFamilyScenario(capacity: 6, fastChoices: 6)
        XCTAssertEqual(report.sessions.count, 6)
        XCTAssertEqual(report.sessions.filter { $0.providerName == "first" }.count, 5)
        XCTAssertEqual(report.sessions.filter { $0.providerName == "second" }.count, 1)
        XCTAssertEqual(activity.keys("published").count, 6)
    }

    func testFullFastFamilyCannotPublishSixChoicesBeforeLateFamilyGetsItsSlot() async {
        // Starting the seventh validation proves the sixth completion was
        // already processed; this barrier does not rely on scheduler sleeps.
        let (report, activity) = await reservedFamilyScenario(capacity: 6, fastChoices: 7)
        XCTAssertEqual(report.sessions.count, 6)
        XCTAssertEqual(Set(report.sessions.map(\.providerName)), ["first", "second"])
        XCTAssertEqual(activity.keys("reported").count, report.startedValidations)
    }

    func testEmptyIndependentFamilyReleasesReservedResultSlot() async {
        let (report, activity) = await reservedFamilyScenario(capacity: 3, fastChoices: 3,
            secondHasCandidate: false)
        XCTAssertEqual(report.sessions.count, 3)
        XCTAssertTrue(report.sessions.allSatisfy { $0.providerName == "first" })
        XCTAssertEqual(activity.keys("published").count, 3)
    }

    func testFailedIndependentFamilyReleasesReservedResultSlot() async {
        let (report, activity) = await reservedFamilyScenario(capacity: 3, fastChoices: 3,
            secondFails: true)
        XCTAssertEqual(report.sessions.count, 3)
        XCTAssertTrue(report.sessions.allSatisfy { $0.providerName == "first" })
        XCTAssertEqual(report.failures.map(\.category), [.providerReturnedEmpty])
        XCTAssertEqual(activity.keys("published").count, 3)
    }

    func testReservedResultsArePublishedOnceAndNeverEvictedByOuterCollector() async {
        let late = DiscoveryTestGate()
        let fast = expectation(description: "Three fast sibling validations completed")
        fast.expectedFulfillmentCount = 3
        let published = DiscoveryTestActivity()
        var limits = SharedStreamDiscovery.Limits()
        limits.sessions = 2
        let first = (0..<3).map { candidate("first", suffix: "first-\($0)") }
        let work = Task { [limits] in
            await StreamDiscoveryCoordinator.collect(lanes: [{ outer in
                let result = await SharedStreamDiscovery.collect(descriptors: [
                    self.descriptor("first") { _ in first },
                    self.descriptor("second") { _ in await late.wait(); return [self.candidate("second")] }
                ], limits: limits, validate: { candidate in
                    if candidate.sourceCode == "first" { fast.fulfill() }
                    return self.success(candidate)
                }, report: { update in
                    switch update {
                    case .validated(_, .success(let session), _, true):
                        published.begin("session", key: session.id.uuidString)
                        outer(.partialSession(session))
                    case .lookupFailure(let failure): outer(.failure(failure))
                    case .fairOpportunity: outer(.fairOpportunity)
                    default: break
                    }
                })
                return self.outcome(result.sessions)
            }], deadline: .seconds(2))
        }
        await fulfillment(of: [fast], timeout: 1)
        XCTAssertEqual(published.keys("session").count, 1)
        late.open()
        let result = await work.value
        XCTAssertEqual(result.sessions.count, 2)
        XCTAssertEqual(Set(result.sessions.map(\.providerName)), ["first", "second"])
        XCTAssertEqual(Set(result.sessions.map { $0.id.uuidString }), Set(published.keys("session")))
        XCTAssertEqual(published.keys("session").count, 2)
        XCTAssertFalse(result.reachedDeadline)
    }

    func testDuplicateSuccessfulDeliveryDoesNotConsumeReservedFamilySlot() async {
        let duplicate = session(candidate("first", suffix: "same-delivery"))
        let report = await SharedStreamDiscovery.collect(descriptors: [
            descriptor("first") { _ in [self.candidate("first", suffix: "one"), self.candidate("first", suffix: "two")] },
            descriptor("second") { _ in [self.candidate("second")] }
        ], validate: { candidate in
            candidate.sourceCode == "first" ? .success(duplicate) : self.success(candidate)
        }, report: { _ in })
        XCTAssertEqual(report.sessions.count, 2)
        XCTAssertEqual(report.sessions.filter { $0.id == duplicate.id }.count, 1)
        XCTAssertEqual(Set(report.sessions.map(\.providerName)), ["first", "second"])
    }

    func testCancellationDoesNotPublishReservedFastSiblingsOrRestartWork() async {
        let late = DiscoveryTestGate()
        let fast = expectation(description: "Three fast sibling validations completed")
        fast.expectedFulfillmentCount = 3
        let activity = DiscoveryTestActivity()
        var limits = SharedStreamDiscovery.Limits()
        limits.sessions = 2
        let first = (0..<3).map { candidate("first", suffix: "first-\($0)") }
        let work = Task {
            await SharedStreamDiscovery.collect(descriptors: [
                self.descriptor("first") { _ in first },
                self.descriptor("second") { _ in
                    activity.begin("lookup", key: "second")
                    defer { activity.end("lookup") }
                    await late.wait()
                    return []
                }
            ], limits: limits, validate: { candidate in
                fast.fulfill(); return self.success(candidate)
            }, report: { update in
                if case .validated(_, .success(let session), _, true) = update {
                    activity.begin("published", key: session.id.uuidString)
                }
            })
        }
        await fulfillment(of: [fast], timeout: 1)
        work.cancel()
        let result = await work.value
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(activity.keys("published").count, 1)
        XCTAssertEqual(activity.active("lookup"), 0)
        XCTAssertEqual(result.startedValidations, 3)
    }

    func testOuterDeadlineRetainsPublishedChoiceWithoutFlushingReservedSiblings() async {
        await reservedPartialResultAtOuterExit(usesChoiceGrace: false)
    }

    func testOuterChoiceGraceRetainsPublishedChoiceWithoutFlushingReservedSiblings() async {
        await reservedPartialResultAtOuterExit(usesChoiceGrace: true)
    }

    func testDescriptorLimitUsesFamilyBreadthAndExactDescriptorDeduplication() async {
        let activity = DiscoveryTestActivity()
        var limits = SharedStreamDiscovery.Limits()
        limits.descriptors = 3
        let definitions = [("a1", "a"), ("a1", "a"), ("a2", "a"), ("a3", "a"), ("b1", "b"), ("c1", "c")]
        let descriptors = definitions.map { id, family in
            SharedStreamDiscovery.Descriptor(id: id, family: family, fallback: nil) { _ in
                activity.begin("lookup", key: id)
                defer { activity.end("lookup") }
                return [self.candidate(family, suffix: id)]
            }
        }
        let report = await SharedStreamDiscovery.collect(descriptors: descriptors, limits: limits,
            validate: { self.success($0) }, report: { _ in })
        XCTAssertEqual(Set(activity.keys("lookup")), ["a1", "b1", "c1"])
        XCTAssertEqual(report.completedLookups, 3)
    }

    func testConcreteQueriesPathsAndFamilyHeadersSurviveMirrorDeduplication() async {
        let hd = candidate("delta", suffix: "Main?token=one")
        let sd = candidate("delta", suffix: "main?token=one", isHD: false)
        let language = candidate("delta", suffix: "Main?token=two")
        let otherHeaders = candidate("hotel", suffix: "Main?token=one")
        let report = await SharedStreamDiscovery.collect(descriptors: [
            descriptor("delta") { publish in
                publish(.candidates([hd, sd, language])); return [hd, sd, language]
            },
            descriptor("hotel") { _ in [otherHeaders] }
        ], validate: { self.success($0) }, report: { _ in })
        XCTAssertEqual(report.sessions.count, 4)
        XCTAssertEqual(report.startedValidations, 4)
        XCTAssertEqual(Set(report.sessions.map { StreamDeliveryIdentity(url: $0.playableURL, headers: $0.requiredHeaders) }).count, 4)
    }

    func testKnownEmptyCatalogUsesOnlyItsProvidedCanonicalFallback() async {
        let fallback = candidate("hotel", suffix: "fallback")
        let report = await SharedStreamDiscovery.collect(descriptors: [
            SharedStreamDiscovery.Descriptor(id: "hotel|exact-id", family: "hotel", fallback: fallback) { _ in [] },
            descriptor("admin") { _ in [] }
        ], validate: { self.success($0) }, report: { _ in })
        XCTAssertEqual(report.sessions.map(\.playableURL.absoluteString), [fallback.embedURL])
    }

    func testConcreteButFailedCandidateDoesNotTriggerInventedFallback() async {
        let concrete = candidate("hotel", suffix: "real")
        let failure = self.failure(.providerSecurityFailure)
        let report = await SharedStreamDiscovery.collect(descriptors: [
            SharedStreamDiscovery.Descriptor(id: "hotel", family: "hotel", fallback: candidate("hotel", suffix: "fallback")) { _ in [concrete] }
        ], validate: { _ in .failure(failure) }, report: { _ in })
        XCTAssertTrue(report.sessions.isEmpty)
        XCTAssertEqual(report.startedValidations, 1)
        XCTAssertEqual(report.failures.first?.category, .providerSecurityFailure)
    }

    func testTimedOutCatalogIsNotTreatedAsKnownEmpty() async {
        var limits = SharedStreamDiscovery.Limits()
        limits.lookupTime = .milliseconds(10)
        let report = await SharedStreamDiscovery.collect(descriptors: [
            SharedStreamDiscovery.Descriptor(id: "hotel", family: "hotel", fallback: candidate("hotel", suffix: "fallback")) { _ in
                try? await Task.sleep(for: .seconds(60)); return []
            }
        ], limits: limits, validate: { self.success($0) }, report: { _ in })
        XCTAssertTrue(report.sessions.isEmpty)
        XCTAssertEqual(report.startedValidations, 0)
        XCTAssertEqual(report.failures.first?.category, .providerTimeout)
    }

    func testOneOuterDeadlineRetainsPartialSessionAndTrustFailure() async {
        let activity = DiscoveryTestActivity()
        let session = self.session(candidate("hotel"))
        let trust = failure(.providerSecurityFailure)
        let result = await StreamDiscoveryCoordinator.collect(lanes: [{ publish in
            let report = await SharedStreamDiscovery.collect(descriptors: [self.descriptor("hotel") { updates in
                activity.begin("lookup", key: "hotel")
                defer { activity.end("lookup") }
                updates(.candidates([self.candidate("hotel")]))
                updates(.failure(trust))
                try? await Task.sleep(for: .seconds(60))
                return []
            }], validate: { _ in .success(session) }, report: { update in
                switch update {
                case .validated(_, .success(let session), _, true): publish(.partialSession(session))
                case .lookupFailure(let failure): publish(.failure(failure))
                case .fairOpportunity: publish(.fairOpportunity)
                default: break
                }
            })
            return self.outcome(report.sessions)
        }], deadline: .milliseconds(40), choiceGrace: .milliseconds(1))
        XCTAssertTrue(result.reachedDeadline)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.exitReason, .deadline)
        XCTAssertEqual(StreamTransportFailurePolicy.mostActionableFailure(in: result.failures)?.category, .providerSecurityFailure)
        XCTAssertEqual(activity.active("lookup"), 0)
    }

    func testIncrementalDiagnosticsSurviveDeadlineAndDeduplicateCompletion() async {
        let record = StreamEventRecord(name: .provider1ValidationStarted, matchID: "match", matchTitle: "A v B",
            attemptID: "attempt", currentState: .validating)
        let attempt = StreamProviderAttemptLog(providerName: "hotel", responseTimeMs: 12, resolvedStreamType: .unknown,
            urlShape: "redacted", requiredHeaders: true, validationResult: "validated")
        let done = outcome([], events: [record], attempts: [attempt])
        let completed = await StreamDiscoveryCoordinator.collect(lanes: [{ publish in
            publish(.event(record)); publish(.attempt(attempt)); return done
        }])
        XCTAssertEqual(completed.timeline.map(\.id), [record.id])
        XCTAssertEqual(completed.attempts.map(\.id), [attempt.id])
        let timedOut = await StreamDiscoveryCoordinator.collect(lanes: [{ publish in
            publish(.event(record)); publish(.attempt(attempt))
            try? await Task.sleep(for: .seconds(60)); return done
        }], deadline: .milliseconds(10))
        XCTAssertEqual(timedOut.timeline.map(\.id), [record.id])
        XCTAssertEqual(timedOut.attempts.map(\.id), [attempt.id])
        XCTAssertEqual(timedOut.incompleteLanes, 1)
    }

    func testCancellationClosesActiveLookupWithoutStartingQueuedDescriptors() async {
        let began = expectation(description: "First lookup began")
        let activity = DiscoveryTestActivity()
        var limits = SharedStreamDiscovery.Limits()
        limits.concurrentLookups = 1
        let descriptors = (0..<4).map { index in descriptor("family\(index)") { _ in
            activity.begin("lookup", key: String(index))
            defer { activity.end("lookup") }
            began.fulfill()
            try? await Task.sleep(for: .seconds(60))
            return []
        } }
        let work = Task {
            await SharedStreamDiscovery.collect(descriptors: descriptors, limits: limits,
                validate: { self.success($0) }, report: { _ in })
        }
        await fulfillment(of: [began], timeout: 1)
        work.cancel()
        let report = await work.value
        XCTAssertEqual(activity.keys("lookup"), ["0"])
        XCTAssertEqual(activity.active("lookup"), 0)
        XCTAssertEqual(report.startedValidations, 0)
        XCTAssertTrue(report.sessions.isEmpty)
    }

    private func reservedPartialResultAtOuterExit(usesChoiceGrace: Bool) async {
        let pending = DiscoveryTestGate()
        let fast = expectation(description: "Three fast sibling validations completed")
        fast.expectedFulfillmentCount = 3
        let pendingStarted = expectation(description: "Independent family still has owned pending work")
        let activity = DiscoveryTestActivity()
        var limits = SharedStreamDiscovery.Limits()
        limits.sessions = 2
        let first = (0..<3).map { candidate("first", suffix: "first-\($0)") }
        let work = Task { [limits] in
            await StreamDiscoveryCoordinator.collect(lanes: [{ outer in
                let result = await SharedStreamDiscovery.collect(descriptors: [
                    self.descriptor("first") { _ in first },
                    self.descriptor("second") { _ in
                        if usesChoiceGrace {
                            // Its first concrete choice fails. Fair discovery
                            // may start the outer grace while a real second
                            // choice from this same family is still validating.
                            return [self.candidate("second", suffix: "first-unavailable"),
                                    self.candidate("second", suffix: "second-pending")]
                        }
                        activity.begin("owned", key: "lookup")
                        defer { activity.end("owned") }
                        pendingStarted.fulfill()
                        await pending.wait()
                        return [self.candidate("second", suffix: "late")]
                    }
                ], limits: limits, validate: { candidate in
                    if candidate.sourceCode == "first" {
                        fast.fulfill()
                    } else if candidate.embedURL.hasSuffix("unavailable") {
                        return .failure(self.failure(.providerReturnedEmpty))
                    } else {
                        activity.begin("owned", key: "validation")
                        defer { activity.end("owned") }
                        pendingStarted.fulfill()
                        await pending.wait()
                    }
                    // A cancelled child can finish with a success; it must
                    // still be unable to publish into the retired outer owner.
                    return self.success(candidate)
                }, report: { update in
                    switch update {
                    case .validated(_, .success(let session), _, true):
                        activity.begin("published", key: session.id.uuidString)
                        outer(.partialSession(session))
                    case .validated(_, .failure(let failure), _, _), .lookupFailure(let failure):
                        outer(.failure(failure))
                    case .fairOpportunity: outer(.fairOpportunity)
                    default: break
                    }
                })
                return self.outcome(result.sessions)
            }], deadline: usesChoiceGrace ? .seconds(2) : .milliseconds(500),
                choiceGrace: .milliseconds(250))
        }
        await fulfillment(of: [fast, pendingStarted], timeout: 1)
        let result = await work.value
        XCTAssertEqual(result.exitReason, usesChoiceGrace ? .choiceGrace : .deadline)
        XCTAssertEqual(result.reachedDeadline, !usesChoiceGrace)
        XCTAssertEqual(result.sessions.count, 1,
            "The cap is a maximum, not a requirement to flush sibling choices at owner exit")
        XCTAssertEqual(result.sessions.first?.providerName, "first")
        XCTAssertEqual(Set(result.sessions.map { $0.id.uuidString }), Set(activity.keys("published")),
            "Every published choice survives; held siblings were never published then evicted")
        XCTAssertEqual(activity.keys("published").count, 1)
        XCTAssertEqual(activity.active("owned"), 0, "All pending child work has been cancelled and joined")
        pending.open()
        XCTAssertEqual(activity.keys("published").count, 1,
            "A late child success cannot revive the exited resolution owner")
    }

    private func reservedFamilyScenario(capacity: Int, fastChoices: Int,
        secondHasCandidate: Bool = true, secondFails: Bool = false
    ) async -> (SharedStreamDiscovery.Report, DiscoveryTestActivity) {
        let late = DiscoveryTestGate()
        let fast = expectation(description: "All fast sibling validations reached the collector")
        fast.expectedFulfillmentCount = fastChoices
        let activity = DiscoveryTestActivity()
        var limits = SharedStreamDiscovery.Limits()
        limits.sessions = capacity
        let first = (0..<fastChoices).map { candidate("first", suffix: "first-\($0)") }
        let work = Task {
            await SharedStreamDiscovery.collect(descriptors: [
                self.descriptor("first") { _ in first },
                self.descriptor("second") { _ in
                    await late.wait()
                    return secondHasCandidate ? [self.candidate("second")] : []
                }
            ], limits: limits, validate: { candidate in
                if candidate.sourceCode == "first" { fast.fulfill() }
                if candidate.sourceCode == "second", secondFails {
                    return .failure(self.failure(.providerReturnedEmpty))
                }
                return self.success(candidate)
            }, report: { update in
                if case .validated(let candidate, _, _, let publish) = update {
                    activity.begin("reported", key: candidate.embedURL)
                    if publish { activity.begin("published", key: candidate.embedURL) }
                }
            })
        }
        await fulfillment(of: [fast], timeout: 1)
        XCTAssertLessThanOrEqual(activity.keys("published").count, capacity - 1,
            "A fast family must leave a result slot for the pending independent family")
        late.open()
        let result = await work.value
        XCTAssertLessThanOrEqual(result.sessions.count, capacity)
        XCTAssertEqual(activity.keys("reported").count, result.startedValidations,
            "Every completed validation has exactly one diagnostic update")
        return (result, activity)
    }

    private func candidate(_ family: String, suffix: String = "stream", isHD: Bool = true) -> Candidate {
        Candidate(sourceCode: family, streamNo: 1, language: "English", isHD: isHD, heatTier: nil,
                  embedURL: "https://media.example.test/\(suffix)", catalogProvider: "fixture")
    }
    @MainActor
    private func fixture(kickoff: Date, away: String) -> AnalyticalDataEngine.EventReference {
        .init(id: "exact-match", title: "Ipswich Town vs \(away)", category: "football",
              date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: false,
              teams: NexusATeams(home: NexusATeam(name: "Ipswich Town", badge: nil), away: NexusATeam(name: away, badge: nil)),
              sources: [NexusASource(source: "delta", id: "exact-provider-id")])
    }

    private func hangingSession(onStart: @escaping () -> Void, onStop: @escaping () -> Void) -> URLSession {
        DiscoveryHangingProtocol.configure(onStart: onStart, onStop: onStop)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DiscoveryHangingProtocol.self]
        config.timeoutIntervalForRequest = 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    private func hangingMirrors(session: URLSession) async -> [Candidate] {
        // Match the production structured-mirror/data(for:) transport ownership
        // with deterministic URLProtocol endpoints; no public request is sent.
        await withTaskGroup(of: [Candidate].self) { group in
            for index in 0..<3 {
                group.addTask {
                    let url = URL(string: "https://mirror\(index).example.test/catalog")!
                    _ = try? await session.data(for: URLRequest(url: url))
                    return []
                }
            }
            var candidates: [Candidate] = []
            for await result in group { candidates += result }
            return candidates
        }
    }
    private func descriptor(_ family: String, lookup: @escaping @Sendable (@escaping SharedStreamDiscovery.LookupReporter) async -> [Candidate]) -> SharedStreamDiscovery.Descriptor {
        .init(id: family, family: family, fallback: nil, lookup: lookup)
    }
    private func session(_ candidate: Candidate) -> StreamSession {
        StreamSession(matchID: "match", playableURL: URL(string: candidate.embedURL)!, streamType: .unknown,
                      providerName: candidate.sourceCode, requiredHeaders: ["X-Family": candidate.sourceCode])
    }
    private func success(_ candidate: Candidate) -> Result<StreamSession, StreamFailure> { .success(session(candidate)) }
    private func failure(_ category: StreamFailureCategory) -> StreamFailure {
        StreamFailure(providerName: "hotel", category: category, technicalMessage: "Fixture failure",
                      userMessage: "Fixture failure", retryable: true, fallbackAllowed: true)
    }
    private func outcome(_ sessions: [StreamSession], events: [StreamEventRecord] = [], attempts: [StreamProviderAttemptLog] = []) -> StreamResolutionOutcome {
        .success(StreamResolutionSuccess(attemptID: "attempt", sessions: sessions, diagnostics:
            StreamAttemptDiagnostics(attemptID: "attempt", matchID: "match", matchTitle: "A v B", finalState: .readyToPlay,
                                     createdAt: Date(), completedAt: Date(), timeline: events, providerAttempts: attempts)))
    }
}

private final class DiscoveryHangingProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var onStart: (() -> Void)?
    private static var onStop: (() -> Void)?
    static func configure(onStart: @escaping () -> Void, onStop: @escaping () -> Void) {
        lock.lock(); self.onStart = onStart; self.onStop = onStop; lock.unlock()
    }
    static func reset() { lock.lock(); onStart = nil; onStop = nil; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https" && request.url?.host?.hasSuffix(".example.test") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let callback = Self.onStart; Self.lock.unlock(); callback?()
    }
    override func stopLoading() {
        Self.lock.lock(); let callback = Self.onStop; Self.lock.unlock(); callback?()
    }
}

private final class DiscoveryTestActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var maxima: [String: Int] = [:]
    private var starts: [String: [String]] = [:]
    func begin(_ kind: String, key: String) {
        lock.lock(); defer { lock.unlock() }
        counts[kind, default: 0] += 1
        maxima[kind] = max(maxima[kind, default: 0], counts[kind, default: 0])
        starts[kind, default: []].append(key)
    }
    func end(_ kind: String) { lock.lock(); counts[kind, default: 0] -= 1; lock.unlock() }
    func keys(_ kind: String) -> [String] { lock.lock(); defer { lock.unlock() }; return starts[kind, default: []] }
    func maximum(_ kind: String) -> Int { lock.lock(); defer { lock.unlock() }; return maxima[kind, default: 0] }
    func active(_ kind: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[kind, default: 0] }
}

private final class DiscoveryTestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var cancelled = Set<UUID>()
    var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return opened }
    func wait() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                if opened || cancelled.remove(id) != nil { lock.unlock(); continuation.resume() }
                else { waiters[id] = continuation; lock.unlock() }
            }
        } onCancel: {
            self.lock.lock()
            let waiter = self.waiters.removeValue(forKey: id)
            if waiter == nil { self.cancelled.insert(id) }
            self.lock.unlock()
            waiter?.resume()
        }
    }
    func open() {
        lock.lock(); opened = true
        let pending = Array(waiters.values); waiters.removeAll()
        lock.unlock(); pending.forEach { $0.resume() }
    }
}
