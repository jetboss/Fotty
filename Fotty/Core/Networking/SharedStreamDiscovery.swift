import Foundation

/// Pipelines mirror results into validation without waiting for other mirrors
/// or descriptors. One caller owns every child task and the outer 18s deadline.
enum SharedStreamDiscovery {
    typealias Candidate = AnalyticalDataEngine.StreamCandidate
    enum LookupUpdate: Sendable {
        case candidates([Candidate])
        /// A mirror decoded a recognized catalog array containing no rows.
        /// Admission filtering, decoding and transport failures are not empty.
        case emptyCatalog
        case failure(StreamFailure)
    }
    typealias LookupReporter = @Sendable (LookupUpdate) -> Void
    struct Descriptor: Sendable {
        let id: String
        let family: String
        let fallback: Candidate?
        // An unreported [] result promises a completed, known-empty catalog.
        // Mirrored lookups report .emptyCatalog explicitly so failures or
        // admission-filtered [] results cannot make that promise implicitly.
        let lookup: @Sendable (@escaping LookupReporter) async -> [Candidate]
    }
    struct Limits: Sendable {
        var descriptors = 12
        // All six supported families get a first opportunity together. This
        // permits at most 18 mirror requests plus six 8KiB HTML validations;
        // URLSession still applies its per-host connection limits. Additional
        // same-family descriptors are opportunistic under the common 18s clock.
        var concurrentLookups = 6
        var concurrentValidations = 6
        var candidatesPerDescriptor = 8
        var validations = 12
        var sessions = 6
        // Preserve the real transport envelopes: a valid response at 4–5s
        // must not be discarded merely to rotate scheduler slots faster.
        var lookupTime: Duration = .seconds(7)
        var validationTime: Duration = .seconds(8)
    }
    enum Update: Sendable {
        case validationStarted(Candidate)
        case validated(Candidate, Result<StreamSession, StreamFailure>, Int, Bool)
        case lookupFailure(StreamFailure)
        case fairOpportunity
    }
    struct Report: Sendable {
        var sessions: [StreamSession] = []
        var failures: [StreamFailure] = []
        var completedLookups = 0
        var startedValidations = 0
    }
    private enum Event: Sendable {
        case lookupUpdate(Int, LookupUpdate)
        case lookupEnded(Int, [Candidate]?)
        case validated(Int, Candidate, Result<StreamSession, StreamFailure>, Int)
    }
    private struct UnpublishedSuccess {
        let index: Int
        let candidate: Candidate
        let session: StreamSession
        let elapsed: Int
    }

    static func collect(
        descriptors input: [Descriptor], limits: Limits = .init(),
        validate: @escaping @Sendable (Candidate) async -> Result<StreamSession, StreamFailure>,
        report: @escaping @Sendable (Update) async -> Void
    ) async -> Report {
        guard !Task.isCancelled, limits.descriptors > 0, limits.concurrentLookups > 0,
              limits.concurrentValidations > 0, limits.validations > 0, limits.sessions > 0 else { return Report() }
        // Breadth before a second descriptor in the same family. Never invent
        // a descriptor or cross the exact catalog identity supplied by Watch.
        var grouped: [String: [Descriptor]] = [:]
        var families: [String] = []
        var descriptorIDs = Set<String>()
        for descriptor in input where descriptorIDs.insert(descriptor.id).inserted {
            if grouped[descriptor.family] == nil { families.append(descriptor.family) }
            grouped[descriptor.family, default: []].append(descriptor)
        }
        var descriptors: [Descriptor] = []
        var round = 0
        while descriptors.count < limits.descriptors {
            let next = families.compactMap { family in grouped[family].flatMap { round < $0.count ? $0[round] : nil } }
            guard !next.isEmpty else { break }
            descriptors += next.prefix(limits.descriptors - descriptors.count)
            round += 1
        }
        guard !descriptors.isEmpty else { return Report() }
        let (events, continuation) = AsyncStream<Event>.makeStream()
        return await withTaskGroup(of: Void.self) { group in
            defer { group.cancelAll(); continuation.finish() }
            var result = Report()
            var nextLookup = 0
            var activeLookups = 0
            var finishedLookups = Set<Int>()
            var reportedLookups = Set<Int>()
            var confirmedEmptyLookups = Set<Int>()
            var queues = Array(repeating: [Candidate](), count: descriptors.count)
            var identities = Set<String>()
            var activeValidations = Set<Int>()
            var validationCounts = Array(repeating: 0, count: descriptors.count)
            var validationCompletions = Set<Int>()
            var sawConcreteCandidate = false
            var evaluatedFallback = false
            var reportedOpportunity = false
            var sessionIdentities = Set<StreamDeliveryIdentity>()
            var retainedFamilies = Set<String>()
            // Successful siblings wait within the existing validation budget,
            // not in the published result. A published choice is never evicted.
            // The cap is a maximum: an owning deadline/grace/cancellation may
            // retain fewer choices rather than flush held siblings after exit.
            var unpublishedSuccesses: [UnpublishedSuccess] = []
            var iterator = events.makeAsyncIterator()

            func enqueue(_ candidates: [Candidate], for index: Int) {
                // Curation keeps HD/SD/language/query alternatives; it only
                // removes duplicate concrete URL/family deliveries from mirrors.
                let curated = AnalyticalDataEngine.curatedPlaybackCandidates(from: [candidates], limit: limits.candidatesPerDescriptor)
                for candidate in curated where queues[index].count < limits.candidatesPerDescriptor {
                    let identity = "\(candidate.sourceCode.lowercased())|\(candidate.embedURL)"
                    if identities.insert(identity).inserted { queues[index].append(candidate) }
                }
            }
            func hasFairOpportunity() -> Bool {
                descriptors.indices.allSatisfy {
                    validationCompletions.contains($0)
                        || finishedLookups.contains($0) && validationCounts[$0] == 0 && queues[$0].isEmpty
                }
            }
            func pendingIndependentFamilies() -> Set<String> {
                var pending = Set(unpublishedSuccesses.map { descriptors[$0.index].family })
                for index in descriptors.indices where !retainedFamilies.contains(descriptors[index].family) {
                    if activeValidations.contains(index)
                        || result.startedValidations < limits.validations
                            && (!finishedLookups.contains(index) || !queues[index].isEmpty) {
                        pending.insert(descriptors[index].family)
                    }
                }
                return pending.subtracting(retainedFamilies)
            }

            while !Task.isCancelled {
                while activeLookups < limits.concurrentLookups && nextLookup < descriptors.count {
                    let index = nextLookup
                    let descriptor = descriptors[index]
                    nextLookup += 1
                    activeLookups += 1
                    group.addTask {
                        let candidates = await bounded(limits.lookupTime) {
                            await descriptor.lookup { update in
                                guard !Task.isCancelled else { return }
                                continuation.yield(.lookupUpdate(index, update))
                            }
                        }
                        continuation.yield(.lookupEnded(index, candidates))
                    }
                }

                if finishedLookups.count == descriptors.count && !evaluatedFallback {
                    evaluatedFallback = true
                    // A failure, filtered result or deadline cannot supply
                    // empty evidence. Retain an explicit successful-empty
                    // receipt even when a sibling times out; each fallback
                    // still needs evidence from its own descriptor.
                    if !sawConcreteCandidate {
                        for index in descriptors.indices where confirmedEmptyLookups.contains(index) {
                            if let fallback = descriptors[index].fallback { enqueue([fallback], for: index) }
                        }
                    }
                }

                while activeValidations.count < limits.concurrentValidations && result.startedValidations < limits.validations {
                    let reserved = descriptors.indices.filter {
                        validationCounts[$0] == 0 && (!finishedLookups.contains($0) || !queues[$0].isEmpty)
                    }.count
                    let ready = descriptors.indices.filter { index in
                        !queues[index].isEmpty && !activeValidations.contains(index)
                            && (validationCounts[index] == 0 || limits.validations - result.startedValidations > reserved)
                    }.sorted {
                        validationCounts[$0] == validationCounts[$1] ? $0 < $1 : validationCounts[$0] < validationCounts[$1]
                    }
                    guard let index = ready.first else { break }
                    let candidate = queues[index].removeFirst()
                    activeValidations.insert(index)
                    validationCounts[index] += 1
                    result.startedValidations += 1
                    await report(.validationStarted(candidate))
                    group.addTask {
                        let started = ContinuousClock.now
                        let validation = await bounded(limits.validationTime) { await validate(candidate) }
                            ?? .failure(timeoutFailure(provider: candidate.sourceCode, phase: "validation"))
                        let elapsed = started.duration(to: .now).components
                        let milliseconds = Int(elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000)
                        continuation.yield(.validated(index, candidate, validation, milliseconds))
                    }
                }

                // Reserve result slots as well as validation opportunities.
                // Without this, six fast sibling pages can fill the cap before
                // another family's first successful validation arrives. Empty,
                // failed and validation-budget-exhausted families release their
                // reservation; already published choices remain unchanged.
                while result.sessions.count < limits.sessions {
                    let reserved = pendingIndependentFamilies().count
                    guard let position = unpublishedSuccesses.firstIndex(where: { success in
                        !retainedFamilies.contains(descriptors[success.index].family)
                            || limits.sessions - result.sessions.count > reserved
                    }) else { break }
                    let success = unpublishedSuccesses.remove(at: position)
                    result.sessions.append(success.session)
                    retainedFamilies.insert(descriptors[success.index].family)
                    await report(.validated(success.candidate, .success(success.session), success.elapsed, true))
                }

                let fair = hasFairOpportunity()
                if fair && !reportedOpportunity && evaluatedFallback {
                    reportedOpportunity = true
                    await report(.fairOpportunity)
                }
                if fair && result.sessions.count >= limits.sessions { break }
                if finishedLookups.count == descriptors.count && activeValidations.isEmpty
                    && (queues.allSatisfy(\.isEmpty) || result.startedValidations >= limits.validations) { break }

                guard let event = await iterator.next(), !Task.isCancelled else { break }
                switch event {
                case .lookupUpdate(let index, .candidates(let candidates)):
                    guard !finishedLookups.contains(index) else { continue }
                    reportedLookups.insert(index)
                    if !candidates.isEmpty { sawConcreteCandidate = true }
                    enqueue(candidates, for: index)
                case .lookupUpdate(let index, .emptyCatalog):
                    guard !finishedLookups.contains(index) else { continue }
                    reportedLookups.insert(index)
                    confirmedEmptyLookups.insert(index)
                case .lookupUpdate(let index, .failure(let failure)):
                    reportedLookups.insert(index)
                    result.failures.append(failure)
                    await report(.lookupFailure(failure))
                case .lookupEnded(let index, let candidates):
                    activeLookups -= 1
                    finishedLookups.insert(index)
                    result.completedLookups += 1
                    if let candidates {
                        if !candidates.isEmpty { sawConcreteCandidate = true }
                        else if !reportedLookups.contains(index) { confirmedEmptyLookups.insert(index) }
                        enqueue(candidates, for: index)
                    } else {
                        let failure = timeoutFailure(provider: descriptors[index].family, phase: "catalog")
                        result.failures.append(failure)
                        await report(.lookupFailure(failure))
                    }
                case .validated(let index, let candidate, let validation, let elapsed):
                    activeValidations.remove(index)
                    validationCompletions.insert(index)
                    switch validation {
                    case .success(let session):
                        if sessionIdentities.insert(StreamDeliveryIdentity(url: session.playableURL, headers: session.requiredHeaders)).inserted {
                            unpublishedSuccesses.append(.init(index: index, candidate: candidate,
                                session: session, elapsed: elapsed))
                        } else {
                            await report(.validated(candidate, validation, elapsed, false))
                        }
                    case .failure(let failure):
                        result.failures.append(failure)
                        await report(.validated(candidate, validation, elapsed, false))
                    }
                }
            }
            // Keep one diagnostic update per completed validation, including
            // extra successful siblings omitted by the bounded result cap.
            if !Task.isCancelled {
                for success in unpublishedSuccesses {
                    await report(.validated(success.candidate, .success(success.session), success.elapsed, false))
                }
            }
            return result
        }
    }

    private static func bounded<Value: Sendable>(_ duration: Duration, operation: @escaping @Sendable () async -> Value) async -> Value? {
        guard !Task.isCancelled else { return nil }
        return await withTaskGroup(of: Value?.self) { group in
            defer { group.cancelAll() }
            group.addTask { await operation() }
            group.addTask { try? await Task.sleep(for: duration); return nil }
            return await group.next() ?? nil
        }
    }

    private static func timeoutFailure(provider: String, phase: String) -> StreamFailure {
        StreamFailure(providerName: provider, category: .providerTimeout,
            technicalMessage: "Bounded shared-provider \(phase) opportunity elapsed.",
            userMessage: "This broadcast provider took too long to respond.", retryable: true, fallbackAllowed: true,
            redactedMetadata: ["discovery_phase": phase, "scope": "selected_descriptor"])
    }
}
