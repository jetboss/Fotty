import Foundation
import Observation

actor AceSessionEngine {
    static let shared = AceSessionEngine()

    enum LifecycleState: Equatable, Sendable {
        case idle
        case starting
        case resolving
        case warming(peerCount: Int, speedKbps: Double, bufferSeconds: Double)
        case validatingManifest
        case ready
        case failed(reason: String)
        case timedOut
    }

    struct SessionSnapshot: Equatable, Sendable {
        let cid: String
        let sessionID: String?
        let playbackURL: URL
        let statusURL: URL
        let state: LifecycleState
        let status: MediaFlowStatus?
        let expiresAt: Date?
        let updatedAt: Date

        var message: String {
            switch state {
            case .idle:
                return "Ready"
            case .starting:
                return "Starting P2P..."
            case .resolving:
                return "Looking for peers..."
            case .warming(let peers, let speed, let buffer):
                if peers > 0 {
                    return "Warming P2P (\(peers) peers, \(Int(speed)) kbps, \(Int(buffer))s)"
                }
                return "Warming P2P..."
            case .validatingManifest:
                return "Verifying playable stream..."
            case .ready:
                return "P2P ready"
            case .failed(let reason):
                return reason
            case .timedOut:
                return "P2P warmup timed out"
            }
        }
    }

    struct PreparedSession: Equatable, Sendable {
        let cid: String
        let sessionID: String
        let playbackURL: URL
        let statusURL: URL
        let preparedAt: Date
        let expiresAt: Date?
        let lastStatus: MediaFlowStatus?
        let headers: [String: String]
    }

    enum PreparationError: LocalizedError, Sendable {
        case invalidSource
        case timedOut
        case brokerSessionNotFound
        case failed(reason: String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .invalidSource:
                return "P2P source is missing content id (infohash) or broker base URL. Check channel headers and Config.P2P."
            case .timedOut:
                return "P2P warmup timed out."
            case .brokerSessionNotFound:
                return "P2P broker session expired. Retrying..."
            case .failed(let reason):
                return reason
            case .cancelled:
                return "P2P warmup cancelled."
            }
        }
    }

    private struct SourceContext {
        let cid: String
        let seedPlaybackURL: URL
        let brokerCreateURL: URL
        let apiPassword: String
        let headers: [String: String]
        let sourceTitle: String?
        let metadata: [String: String]
    }

    private struct BrokerContext {
        let cid: String
        let sessionID: String
        let playbackURL: URL
        let statusURL: URL
        let expiresAt: Date?
        let apiPassword: String
        let headers: [String: String]
    }

    private struct CachedSession {
        var prepared: PreparedSession?
        var snapshot: SessionSnapshot
        var readyAt: Date?
    }

    private struct InFlightPreparation {
        let id: UUID
        let task: Task<PreparedSession, Error>
    }

    private let config: PlaybackReadinessConfig
    private let statusSession: URLSession
    private let probeSession: URLSession
    private let readyReuseWindowSeconds: TimeInterval = 45
    private let minimumSegmentBytes = 512
    private let probeEveryAttemptCount = 2
    private let manifestProbeTimeoutSeconds: TimeInterval = 22
    private let segmentProbeTimeoutSeconds: TimeInterval = 5
    private var cache: [String: CachedSession] = [:]
    private var inFlightPreparations: [String: InFlightPreparation] = [:]
    private var timelineLoggedStatusSessions = Set<String>()
    private var timelineLoggedManifestSessions = Set<String>()

    init(
        config: PlaybackReadinessConfig = PlaybackReadinessConfig(
            minimumBufferSeconds: 2,
            minimumReadySegments: 1,
            minimumPeerCount: 1,
            minimumDownloadSpeedKbps: 250,
            warmupTimeoutSeconds: 100,
            pollingIntervalSeconds: 2.0
        )
    ) {
        self.config = config

        let statusConfig = URLSessionConfiguration.ephemeral
        statusConfig.timeoutIntervalForRequest = 5
        statusConfig.timeoutIntervalForResource = 5
        statusConfig.waitsForConnectivity = false
        statusConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.statusSession = URLSession(configuration: statusConfig)

        let probeConfig = URLSessionConfiguration.ephemeral
        probeConfig.timeoutIntervalForRequest = manifestProbeTimeoutSeconds
        probeConfig.timeoutIntervalForResource = manifestProbeTimeoutSeconds
        probeConfig.waitsForConnectivity = false
        probeConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.probeSession = URLSession(configuration: probeConfig)
    }

    func prepareSession(
        for source: StreamSource,
        forceRestart: Bool = false,
        onUpdate: (@Sendable (SessionSnapshot) async -> Void)? = nil
    ) async throws -> PreparedSession {
        let context = try makeContext(from: source)

        if !forceRestart,
           let prepared = cachedPreparedSession(forCID: context.cid, minimumRemainingLifetime: 8),
           await brokerManifestStillValid(
            playbackURL: prepared.playbackURL,
            sourceHeaders: prepared.headers,
            apiPassword: context.apiPassword
           ) {
            let readySnapshot = SessionSnapshot(
                cid: context.cid,
                sessionID: prepared.sessionID,
                playbackURL: prepared.playbackURL,
                statusURL: prepared.statusURL,
                state: .ready,
                status: prepared.lastStatus,
                expiresAt: prepared.expiresAt,
                updatedAt: Date()
            )
            cache[context.cid] = CachedSession(prepared: prepared, snapshot: readySnapshot, readyAt: prepared.preparedAt)
            if let onUpdate {
                await onUpdate(readySnapshot)
            }
            logP2PTimeline(
                "broker_session_created_at",
                cid: context.cid,
                sessionID: prepared.sessionID,
                metadata: [
                    "prepared_at": ISO8601DateFormatter().string(from: prepared.preparedAt),
                    "reused": "true"
                ]
            )
            return prepared
        }

        if !forceRestart, cache[context.cid]?.prepared != nil {
            // Cached lease was present but manifest or status is gone — force a fresh broker session.
            cache.removeValue(forKey: context.cid)
        }

        if let active = inFlightPreparations[context.cid] {
            if let onUpdate, let snapshot = cache[context.cid]?.snapshot {
                await onUpdate(snapshot)
            }
            return try await active.task.value
        }

        let taskID = UUID()
        let task = Task<PreparedSession, Error> {
            try await self.prepareSessionInternal(context: context, onUpdate: onUpdate)
        }
        inFlightPreparations[context.cid] = InFlightPreparation(id: taskID, task: task)

        do {
            let prepared = try await task.value
            if inFlightPreparations[context.cid]?.id == taskID {
                inFlightPreparations.removeValue(forKey: context.cid)
            }
            return prepared
        } catch {
            if inFlightPreparations[context.cid]?.id == taskID {
                inFlightPreparations.removeValue(forKey: context.cid)
            }
            throw error
        }
    }

    func preparedSession(
        for source: StreamSource,
        minimumRemainingLifetime: TimeInterval = 8
    ) async -> PreparedSession? {
        guard let cid = extractCID(from: source),
              let context = try? makeContext(from: source),
              let prepared = cachedPreparedSession(forCID: cid, minimumRemainingLifetime: minimumRemainingLifetime) else {
            return nil
        }
        guard await brokerManifestStillValid(
            playbackURL: prepared.playbackURL,
            sourceHeaders: prepared.headers,
            apiPassword: context.apiPassword
        ) else {
            cache.removeValue(forKey: cid)
            return nil
        }
        return prepared
    }

    /// Same as ``prepareSession(for:forceRestart:onUpdate:)`` with `forceRestart: false` and no progress callback.
    /// Kept for call sites that only need a validated broker URL; prefer ``prepareSession`` when UI progress matters.
    func resolveBrokerURL(for source: StreamSource) async throws -> PreparedSession {
        try await prepareSession(for: source, forceRestart: false)
    }

    func prewarmSession(for source: StreamSource) async {
        _ = try? await prepareSession(for: source, forceRestart: false)
    }

    private func prepareSessionInternal(
        context: SourceContext,
        onUpdate: (@Sendable (SessionSnapshot) async -> Void)? = nil
    ) async throws -> PreparedSession {
        let pendingSnapshot = SessionSnapshot(
            cid: context.cid,
            sessionID: nil,
            playbackURL: context.seedPlaybackURL,
            statusURL: context.brokerCreateURL,
            state: .starting,
            status: nil,
            expiresAt: nil,
            updatedAt: Date()
        )
        cache[context.cid] = CachedSession(prepared: nil, snapshot: pendingSnapshot, readyAt: nil)
        if let onUpdate {
            await onUpdate(pendingSnapshot)
        }

        var broker: BrokerContext
        do {
            broker = try await createBrokerSession(context)
        } catch let error as PreparationError {
            let failedSnapshot = SessionSnapshot(
                cid: context.cid,
                sessionID: nil,
                playbackURL: context.seedPlaybackURL,
                statusURL: context.brokerCreateURL,
                state: .failed(reason: error.errorDescription ?? "P2P broker session failed."),
                status: nil,
                expiresAt: nil,
                updatedAt: Date()
            )
            cache[context.cid] = CachedSession(prepared: nil, snapshot: failedSnapshot, readyAt: nil)
            if let onUpdate {
                await onUpdate(failedSnapshot)
            }
            throw error
        } catch {
            let failedSnapshot = SessionSnapshot(
                cid: context.cid,
                sessionID: nil,
                playbackURL: context.seedPlaybackURL,
                statusURL: context.brokerCreateURL,
                state: .failed(reason: error.localizedDescription),
                status: nil,
                expiresAt: nil,
                updatedAt: Date()
            )
            cache[context.cid] = CachedSession(prepared: nil, snapshot: failedSnapshot, readyAt: nil)
            if let onUpdate {
                await onUpdate(failedSnapshot)
            }
            throw PreparationError.failed(reason: error.localizedDescription)
        }
        let startSnapshot = SessionSnapshot(
            cid: context.cid,
            sessionID: broker.sessionID,
            playbackURL: broker.playbackURL,
            statusURL: broker.statusURL,
            state: .starting,
            status: nil,
            expiresAt: broker.expiresAt,
            updatedAt: Date()
        )
        cache[context.cid] = CachedSession(prepared: nil, snapshot: startSnapshot, readyAt: nil)
        if let onUpdate {
            await onUpdate(startSnapshot)
        }

        let startedAt = Date()
        var latestStatus: MediaFlowStatus?
        var attempt = 0

        do {
            while Date().timeIntervalSince(startedAt) <= config.warmupTimeoutSeconds {
                try Task.checkCancellation()
                attempt += 1

                do {
                    if let status = try await fetchStatus(
                        from: broker.statusURL,
                        apiPassword: broker.apiPassword,
                        sourceHeaders: broker.headers
                    ) {
                        latestStatus = status
                        let statusSnapshot = SessionSnapshot(
                            cid: context.cid,
                            sessionID: broker.sessionID,
                            playbackURL: broker.playbackURL,
                            statusURL: broker.statusURL,
                            state: lifecycleState(from: status),
                            status: status,
                            expiresAt: status.expiresAt ?? broker.expiresAt,
                            updatedAt: Date()
                        )
                        cache[context.cid] = CachedSession(prepared: nil, snapshot: statusSnapshot, readyAt: nil)
                        if let onUpdate {
                            await onUpdate(statusSnapshot)
                        }
                    }
                } catch is CancellationError {
                    throw PreparationError.cancelled
                } catch PreparationError.brokerSessionNotFound {
                    cache.removeValue(forKey: context.cid)
                    broker = try await createBrokerSession(context)
                    let refreshedSnapshot = SessionSnapshot(
                        cid: context.cid,
                        sessionID: broker.sessionID,
                        playbackURL: broker.playbackURL,
                        statusURL: broker.statusURL,
                        state: .starting,
                        status: latestStatus,
                        expiresAt: latestStatus?.expiresAt ?? broker.expiresAt,
                        updatedAt: Date()
                    )
                    cache[context.cid] = CachedSession(prepared: nil, snapshot: refreshedSnapshot, readyAt: nil)
                    if let onUpdate {
                        await onUpdate(refreshedSnapshot)
                    }
                } catch {
                    NSLog("[Fotty] fetchStatus Decoding/Network Error: %@", error.localizedDescription)
                    print("Fetch Status Error: \(error)")
                    // Status is telemetry, not the source of truth. Keep warming and let the
                    // manifest/segment probe decide when the stream is truly playable.
                }

                let shouldProbe = attempt == 1
                    || attempt % probeEveryAttemptCount == 0
                    || (latestStatus?.firstSegmentReady ?? false)
                    || (latestStatus?.readySegmentCount ?? 0) > 0
                    || (latestStatus?.peerCount ?? 0) > 0

                if shouldProbe {
                    let probeSnapshot = SessionSnapshot(
                        cid: context.cid,
                        sessionID: broker.sessionID,
                        playbackURL: broker.playbackURL,
                        statusURL: broker.statusURL,
                        state: .validatingManifest,
                        status: latestStatus,
                        expiresAt: latestStatus?.expiresAt ?? broker.expiresAt,
                        updatedAt: Date()
                    )
                    cache[context.cid] = CachedSession(prepared: nil, snapshot: probeSnapshot, readyAt: nil)
                    if let onUpdate {
                        await onUpdate(probeSnapshot)
                    }

                    let isReady: Bool
                    do {
                        isReady = try await probePlaybackURL(broker)
                    } catch is CancellationError {
                        throw PreparationError.cancelled
                    } catch PreparationError.brokerSessionNotFound {
                        // The broker session may have been evicted (e.g. server restart). Recreate and continue.
                        broker = try await createBrokerSession(context)
                        let refreshedSnapshot = SessionSnapshot(
                            cid: context.cid,
                            sessionID: broker.sessionID,
                            playbackURL: broker.playbackURL,
                            statusURL: broker.statusURL,
                            state: .starting,
                            status: latestStatus,
                            expiresAt: latestStatus?.expiresAt ?? broker.expiresAt,
                            updatedAt: Date()
                        )
                        cache[context.cid] = CachedSession(prepared: nil, snapshot: refreshedSnapshot, readyAt: nil)
                        if let onUpdate {
                            await onUpdate(refreshedSnapshot)
                        }
                        isReady = false
                    } catch {
                        isReady = false
                    }

                    if isReady {
                        let prepared = PreparedSession(
                            cid: context.cid,
                            sessionID: broker.sessionID,
                            playbackURL: broker.playbackURL,
                            statusURL: broker.statusURL,
                            preparedAt: Date(),
                            expiresAt: latestStatus?.expiresAt ?? broker.expiresAt,
                            lastStatus: latestStatus,
                            headers: broker.headers
                        )
                        let readySnapshot = SessionSnapshot(
                            cid: context.cid,
                            sessionID: broker.sessionID,
                            playbackURL: prepared.playbackURL,
                            statusURL: prepared.statusURL,
                            state: .ready,
                            status: latestStatus,
                            expiresAt: prepared.expiresAt,
                            updatedAt: prepared.preparedAt
                        )
                        cache[context.cid] = CachedSession(prepared: prepared, snapshot: readySnapshot, readyAt: prepared.preparedAt)
                        if let onUpdate {
                            await onUpdate(readySnapshot)
                        }
                        return prepared
                    }
                }

                try await Task.sleep(for: .seconds(config.pollingIntervalSeconds))
            }
        } catch is CancellationError {
            throw PreparationError.cancelled
        } catch let error as PreparationError {
            let failedSnapshot = SessionSnapshot(
                cid: context.cid,
                sessionID: broker.sessionID,
                playbackURL: broker.playbackURL,
                statusURL: broker.statusURL,
                state: .failed(reason: error.errorDescription ?? "P2P session failed."),
                status: latestStatus,
                expiresAt: latestStatus?.expiresAt ?? broker.expiresAt,
                updatedAt: Date()
            )
            cache[context.cid] = CachedSession(prepared: nil, snapshot: failedSnapshot, readyAt: nil)
            if let onUpdate {
                await onUpdate(failedSnapshot)
            }
            throw error
        } catch {
            let failedSnapshot = SessionSnapshot(
                cid: context.cid,
                sessionID: broker.sessionID,
                playbackURL: broker.playbackURL,
                statusURL: broker.statusURL,
                state: .failed(reason: error.localizedDescription),
                status: latestStatus,
                expiresAt: latestStatus?.expiresAt ?? broker.expiresAt,
                updatedAt: Date()
            )
            cache[context.cid] = CachedSession(prepared: nil, snapshot: failedSnapshot, readyAt: nil)
            if let onUpdate {
                await onUpdate(failedSnapshot)
            }
            throw PreparationError.failed(reason: error.localizedDescription)
        }

        let timedOutSnapshot = SessionSnapshot(
            cid: context.cid,
            sessionID: broker.sessionID,
            playbackURL: broker.playbackURL,
            statusURL: broker.statusURL,
            state: .timedOut,
            status: latestStatus,
            expiresAt: latestStatus?.expiresAt ?? broker.expiresAt,
            updatedAt: Date()
        )
        cache[context.cid] = CachedSession(prepared: nil, snapshot: timedOutSnapshot, readyAt: nil)
        if let onUpdate {
            await onUpdate(timedOutSnapshot)
        }
        throw PreparationError.timedOut
    }

    private func cachedPreparedSession(
        forCID cid: String,
        minimumRemainingLifetime: TimeInterval
    ) -> PreparedSession? {
        guard let cached = cache[cid],
              let prepared = cached.prepared,
              let readyAt = cached.readyAt else {
            return nil
        }

        let age = Date().timeIntervalSince(readyAt)
        let leaseRemaining = prepared.expiresAt?.timeIntervalSinceNow ?? readyReuseWindowSeconds
        let remainingLifetime = min(leaseRemaining, readyReuseWindowSeconds - age)
        guard remainingLifetime >= minimumRemainingLifetime else {
            return nil
        }

        return prepared
    }

    func snapshot(for source: StreamSource) -> SessionSnapshot? {
        guard let cid = extractCID(from: source) else { return nil }
        return cache[cid]?.snapshot
    }

    func invalidateSession(for source: StreamSource) {
        guard let cid = extractCID(from: source) else { return }
        cache.removeValue(forKey: cid)
    }

    func invalidateAllSessions() {
        cache.removeAll()
    }

    private func lifecycleState(from status: MediaFlowStatus) -> LifecycleState {
        switch status.state.lowercased() {
        case "failed":
            return .failed(reason: status.lastError ?? "P2P session failed.")
        case "refreshing":
            if status.firstSegmentReady || status.readySegmentCount > 0 {
                return .validatingManifest
            }
        default:
            break
        }

        if status.firstSegmentReady || status.readySegmentCount > 0 {
            return .validatingManifest
        }
        if status.peerCount > 0 || status.downloadSpeedKbps > 0 || status.bufferSeconds > 0 {
            return .warming(
                peerCount: status.peerCount,
                speedKbps: status.downloadSpeedKbps,
                bufferSeconds: status.bufferSeconds
            )
        }
        return .resolving
    }

    private func makeContext(from source: StreamSource) throws -> SourceContext {
        guard let cid = extractCID(from: source) else {
            throw PreparationError.invalidSource
        }

        let apiPassword = extractAPIPassword(from: source)
        guard let brokerCreateURL = P2PDataService.brokerSessionCreateURL() else {
            throw PreparationError.invalidSource
        }

        return SourceContext(
            cid: cid,
            seedPlaybackURL: source.url,
            brokerCreateURL: brokerCreateURL,
            apiPassword: apiPassword,
            headers: source.headers,
            sourceTitle: source.title,
            metadata: brokerMetadata(from: source)
        )
    }

    private func extractCID(from source: StreamSource) -> String? {
        let components = URLComponents(url: source.url, resolvingAgainstBaseURL: false)
        if let q = components?.queryItems?.first(where: {
            $0.name == "id" || $0.name == "infohash"
        })?.value?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            return q
        }
        // Broker handoff URLs use /session/<id>/manifest.m3u8 (no infohash query). CID is in headers.
        if let h = source.headers["X-Fotty-P2P-Cid"]?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty {
            return h
        }
        return nil
    }

    private func extractAPIPassword(from source: StreamSource) -> String {
        let components = URLComponents(url: source.url, resolvingAgainstBaseURL: false)
        let password = components?.queryItems?.first(where: { $0.name == "api_password" })?.value
        return password?.isEmpty == false ? password! : P2PDataService.decodedAPIPassword
    }

    private func brokerMetadata(from source: StreamSource) -> [String: String] {
        source.headers.reduce(into: [String: String]()) { partialResult, element in
            let (key, value) = element
            guard key.lowercased().hasPrefix("x-fotty-p2p-") else { return }
            partialResult[key] = value
        }
    }

    private func createBrokerSession(_ context: SourceContext) async throws -> BrokerContext {
        NSLog("[Fotty] createBrokerSession called for CID: %@", context.cid)
        var request = URLRequest(url: context.brokerCreateURL)
        request.httpMethod = "POST"
        request.timeoutInterval = manifestProbeTimeoutSeconds
        applyProbeHeaders(to: &request, sourceHeaders: context.headers, apiPassword: context.apiPassword)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var payload: [String: Any] = [
            "cid": context.cid,
            "api_password": context.apiPassword
        ]
        if let title = context.sourceTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            payload["title"] = title
        }
        if let category = context.metadata["X-Fotty-P2P-Category"], !category.isEmpty {
            payload["category"] = category
        }
        if let availability = context.metadata["X-Fotty-P2P-Availability"], let parsed = Double(availability) {
            payload["availability"] = parsed
        }
        if let bitrate = context.metadata["X-Fotty-P2P-Bitrate-Kbps"], let parsed = Int(bitrate) {
            payload["bitrate_kbps"] = parsed
        }
        if let categories = context.metadata["X-Fotty-P2P-Categories"]?
            .split(separator: ",")
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty }),
           !categories.isEmpty {
            payload["categories"] = categories
        }
        if let sourceName = context.metadata["X-Fotty-P2P-Source"], !sourceName.isEmpty {
            payload["source"] = sourceName
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await statusSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PreparationError.failed(reason: "P2P broker did not return an HTTP response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw PreparationError.failed(reason: brokerFailureMessage(from: data, statusCode: httpResponse.statusCode))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(P2PBrokerSessionEnvelope.self, from: data)
        guard let playbackURL = URL(string: envelope.manifestURL),
              let statusURL = URL(string: envelope.statusURL) else {
            throw PreparationError.failed(reason: "P2P broker returned invalid session URLs.")
        }
        logP2PTimeline(
            "broker_session_created_at",
            cid: context.cid,
            sessionID: envelope.sessionId,
            metadata: ["state": envelope.state]
        )

        return BrokerContext(
            cid: context.cid,
            sessionID: envelope.sessionId,
            playbackURL: playbackURL,
            statusURL: statusURL,
            expiresAt: envelope.expiresAt,
            apiPassword: context.apiPassword,
            headers: context.headers
        )
    }

    private func brokerFailureMessage(from data: Data, statusCode: Int) -> String {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "P2P broker session failed with HTTP \(statusCode)."
        }

        let detail = (payload["detail"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = (payload["code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let detail, !detail.isEmpty {
            return detail
        }
        if let code, !code.isEmpty {
            return "P2P broker failed: \(code)."
        }
        return "P2P broker session failed with HTTP \(statusCode)."
    }

    private func fetchStatus(
        from url: URL,
        apiPassword: String,
        sourceHeaders: [String: String]
    ) async throws -> MediaFlowStatus? {
        NSLog("[Fotty] fetchStatus called for URL: %@", url.absoluteString)
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        applyProbeHeaders(to: &request, sourceHeaders: sourceHeaders, apiPassword: apiPassword)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await statusSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return nil }

        if httpResponse.statusCode == 404 {
            throw PreparationError.brokerSessionNotFound
        }

        if !(200...299).contains(httpResponse.statusCode) {
            NSLog("[Fotty] fetchStatus HTTP Error: %ld for URL: %@", httpResponse.statusCode, url.absoluteString)
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }
            
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
        }
        let status = try decoder.decode(MediaFlowStatus.self, from: data)
        if let sessionID = status.sessionId, !timelineLoggedStatusSessions.contains(sessionID) {
            timelineLoggedStatusSessions.insert(sessionID)
            logP2PTimeline(
                "first_status_received_at",
                cid: status.sourceId,
                sessionID: sessionID,
                metadata: ["state": status.state]
            )
        }
        return status
    }

    /// True if the broker still serves this session manifest (avoids reusing evicted `session_id`s).
    private func brokerManifestStillValid(
        playbackURL: URL,
        sourceHeaders: [String: String],
        apiPassword: String
    ) async -> Bool {
        var headRequest = URLRequest(url: playbackURL)
        headRequest.httpMethod = "HEAD"
        headRequest.timeoutInterval = min(8, manifestProbeTimeoutSeconds)
        applyProbeHeaders(to: &headRequest, sourceHeaders: sourceHeaders, apiPassword: apiPassword)
        headRequest.setValue(
            "application/vnd.apple.mpegurl, application/x-mpegurl;q=0.9, */*;q=0.8",
            forHTTPHeaderField: "Accept"
        )

        if let code = await manifestStatusCode(for: headRequest), code != 405, code != 501 {
            return (200...299).contains(code)
        }

        var getRequest = URLRequest(url: playbackURL)
        getRequest.timeoutInterval = min(8, manifestProbeTimeoutSeconds)
        applyProbeHeaders(to: &getRequest, sourceHeaders: sourceHeaders, apiPassword: apiPassword)
        getRequest.setValue(
            "application/vnd.apple.mpegurl, application/x-mpegurl;q=0.9, */*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        guard let code = await manifestStatusCode(for: getRequest) else { return false }
        return code != 404 && (200...299).contains(code)
    }

    private func manifestStatusCode(for request: URLRequest) async -> Int? {
        do {
            let (_, response) = try await probeSession.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode
        } catch {
            return nil
        }
    }

    private func probePlaybackURL(_ context: BrokerContext) async throws -> Bool {
        var manifestRequest = URLRequest(url: context.playbackURL)
        manifestRequest.timeoutInterval = manifestProbeTimeoutSeconds
        applyProbeHeaders(to: &manifestRequest, sourceHeaders: context.headers, apiPassword: context.apiPassword)
        manifestRequest.setValue("application/vnd.apple.mpegurl, application/x-mpegurl;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")

        let (manifestBytes, response) = try await probeSession.bytes(for: manifestRequest)
        guard let manifestResponse = response as? HTTPURLResponse else {
            return false
        }

        // If the session ID is unknown (commonly after a server restart), recreate the session.
        if manifestResponse.statusCode == 404 {
            throw PreparationError.brokerSessionNotFound
        }

        guard (200...299).contains(manifestResponse.statusCode) else {
            return false
        }

        let contentType = manifestResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        let manifestData = try await readPrefix(
            from: manifestBytes,
            limit: 4096,
            minimumBytes: contentType.contains("video/") || contentType.contains("octet-stream")
                ? minimumSegmentBytes
                : 4096
        )

        if isDirectTransportStream(contentType: contentType, data: manifestData) {
            return true
        }

        guard let manifest = String(data: manifestData, encoding: .utf8),
              manifest.contains("#EXTM3U"),
              let segmentURL = firstSegmentURL(in: manifest, relativeTo: context.playbackURL) else {
            return false
        }

        var segmentRequest = URLRequest(url: segmentURL)
        segmentRequest.timeoutInterval = segmentProbeTimeoutSeconds
        applyProbeHeaders(to: &segmentRequest, sourceHeaders: context.headers, apiPassword: context.apiPassword)
        segmentRequest.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        segmentRequest.setValue("*/*", forHTTPHeaderField: "Accept")

        let (bytes, segmentResponse) = try await probeSession.bytes(for: segmentRequest)
        guard let segmentHTTPResponse = segmentResponse as? HTTPURLResponse,
              (200...299).contains(segmentHTTPResponse.statusCode) else {
            return false
        }

        var received = Data()
        received.reserveCapacity(minimumSegmentBytes)
        var iterator = bytes.makeAsyncIterator()
        while received.count < minimumSegmentBytes,
              let byte = try await iterator.next() {
            received.append(byte)
        }

        let validated = received.count >= minimumSegmentBytes
        if validated, !timelineLoggedManifestSessions.contains(context.sessionID) {
            timelineLoggedManifestSessions.insert(context.sessionID)
            logP2PTimeline(
                "first_manifest_validated_at",
                cid: context.cid,
                sessionID: context.sessionID,
                metadata: ["segment_bytes": "\(received.count)"]
            )
        }

        return validated
    }

    private func readPrefix(
        from bytes: URLSession.AsyncBytes,
        limit: Int,
        minimumBytes: Int
    ) async throws -> Data {
        var data = Data()
        data.reserveCapacity(limit)
        var iterator = bytes.makeAsyncIterator()
        while data.count < limit,
              let byte = try await iterator.next() {
            data.append(byte)
            if data.count >= minimumBytes {
                break
            }
        }
        return data
    }

    private func isDirectTransportStream(contentType: String, data: Data) -> Bool {
        if contentType.contains("video/mp2t") ||
            contentType.contains("video/vnd.dlna.mpeg-tts") ||
            contentType.contains("application/octet-stream") {
            return data.count >= minimumSegmentBytes
        }

        return false
    }

    private func applyProbeHeaders(
        to request: inout URLRequest,
        sourceHeaders: [String: String],
        apiPassword: String
    ) {
        for (key, value) in sourceHeaders where !key.lowercased().hasPrefix("x-fotty-") {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("Bearer \(apiPassword)", forHTTPHeaderField: "Authorization")
        request.setValue(apiPassword, forHTTPHeaderField: "api-password")
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        }
        if request.value(forHTTPHeaderField: "Referer") == nil {
            request.setValue("https://p2p.pixel-invoice.com/", forHTTPHeaderField: "Referer")
        }
    }

    private func firstSegmentURL(in manifest: String, relativeTo manifestURL: URL) -> URL? {
        for rawLine in manifest.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if let absoluteURL = URL(string: line, relativeTo: manifestURL)?.absoluteURL {
                return absoluteURL
            }
        }
        return nil
    }

    private func logP2PTimeline(
        _ label: String,
        cid: String?,
        sessionID: String? = nil,
        failureCode: String? = nil,
        metadata: [String: String] = [:]
    ) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let metadataText = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        NSLog(
            "[Fotty][P2P_TIMELINE] %@=%@ cid=%@ session_id=%@ failure_code=%@ %@",
            label,
            timestamp,
            cid ?? "unknown",
            sessionID ?? "none",
            failureCode ?? "none",
            metadataText
        )
    }
}

/// Compatibility wrapper for the existing warmup UI.
@Observable
@MainActor
class PlaybackWarmupService {

    enum WarmupState: Equatable {
        case idle
        case starting
        case resolving
        case warming(peerCount: Int, speedKbps: Double, bufferSeconds: Double)
        case peersFound(count: Int)
        case bufferingOnServer(seconds: Double)
        case firstSegmentReady
        case readyForPlayback(manifestURL: URL)
        case failed(reason: String)
        case timedOut

        var message: String {
            switch self {
            case .idle: return "Ready"
            case .starting: return "Starting warmup..."
            case .resolving: return "Resolving stream identity..."
            case .warming(let peers, let speed, let buffer):
                return "Warming swarm (\(peers) peers, \(Int(speed)) kbps, \(Int(buffer))s buffer)"
            case .peersFound(let count): return "Found \(count) peers, starting buffer..."
            case .bufferingOnServer(let seconds): return "Building server buffer (\(Int(seconds))s)..."
            case .firstSegmentReady: return "First segment ready, verifying..."
            case .readyForPlayback: return "Stream ready! Starting playback..."
            case .failed(let reason): return "Failed: \(reason)"
            case .timedOut: return "Warmup timed out. Swarm is too cold."
            }
        }
    }

    private(set) var state: WarmupState = .idle
    private(set) var currentStatus: MediaFlowStatus?
    private(set) var diagnosticHistory: [MediaFlowStatus] = []

    var userFacingStatusMessage: String {
        guard let currentStatus else {
            return state.message
        }

        if let message = currentStatus.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
        }

        switch currentStatus.state.lowercased() {
        case "ready":
            if let manifestTTFBMs = currentStatus.manifestTTFBMs {
                return "Playable stream verified in \(max(1, manifestTTFBMs / 1000))s."
            }
            return "Playable stream verified."
        case "refreshing":
            return "Refreshing playable session..."
        case "warming", "starting":
            return "Preparing stream on the broker..."
        case "failed":
            return currentStatus.lastError ?? "No playable stream is available right now."
        default:
            if currentStatus.readySegmentCount > 0 || currentStatus.firstSegmentReady {
                return "Segment health verified."
            }
            return state.message
        }
    }

    private let config: PlaybackReadinessConfig
    private var warmupTask: Task<Void, Never>?
    private var warmupStartedAt = Date()

    init(config: PlaybackReadinessConfig = .default) {
        self.config = config
    }

    var warmupElapsedSeconds: TimeInterval {
        Date().timeIntervalSince(warmupStartedAt)
    }

    func startWarmup(for source: StreamSource) async {
        NSLog("[Fotty] startWarmup for source: %@", source.url.absoluteString)
        stopWarmup()
        warmupStartedAt = Date()
        state = .starting
        currentStatus = nil
        diagnosticHistory = []

        warmupTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let prepared = try await AceSessionEngine.shared.prepareSession(for: source, forceRestart: false) { snapshot in
                    await MainActor.run {
                        self.apply(snapshot: snapshot)
                    }
                }

                guard !Task.isCancelled else { return }
                self.state = .readyForPlayback(manifestURL: prepared.playbackURL)
            } catch let error as AceSessionEngine.PreparationError {
                guard !Task.isCancelled else { return }
                switch error {
                case .timedOut:
                    self.state = .timedOut
                case .brokerSessionNotFound:
                    self.state = .starting
                case .cancelled:
                    self.state = .idle
                case .invalidSource, .failed:
                    self.state = .failed(reason: error.errorDescription ?? "Warmup failed.")
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.state = .failed(reason: error.localizedDescription)
            }

            self.warmupTask = nil
        }
    }

    func stopWarmup() {
        warmupTask?.cancel()
        warmupTask = nil
        state = .idle
    }

    private func apply(snapshot: AceSessionEngine.SessionSnapshot) {
        if let status = snapshot.status {
            currentStatus = status
            if diagnosticHistory.last != status {
                diagnosticHistory.append(status)
            }
        }

        switch snapshot.state {
        case .idle:
            state = .idle
        case .starting:
            state = .starting
        case .resolving:
            state = .resolving
        case .warming(let peerCount, let speedKbps, let bufferSeconds):
            if peerCount > 0 && bufferSeconds <= 0 {
                state = .peersFound(count: peerCount)
            } else {
                state = .warming(peerCount: peerCount, speedKbps: speedKbps, bufferSeconds: bufferSeconds)
            }
        case .validatingManifest:
            if snapshot.status?.firstSegmentReady == true {
                state = .firstSegmentReady
            } else {
                state = .bufferingOnServer(seconds: snapshot.status?.bufferSeconds ?? 0)
            }
        case .ready:
            state = .readyForPlayback(manifestURL: snapshot.playbackURL)
        case .failed(let reason):
            state = .failed(reason: reason)
        case .timedOut:
            state = .timedOut
        }
    }

    func generateReport(source: StreamSource) -> PlaybackWarmupDiagnosticReport {
        let end = Date()
        let firstSegmentProbeResult: String
        if case .readyForPlayback = state {
            firstSegmentProbeResult = "Success"
        } else {
            firstSegmentProbeResult = "Failed"
        }
        return PlaybackWarmupDiagnosticReport(
            sourceId: extractCID(from: source.url),
            sourceTitle: source.title ?? "Unknown",
            manifestURL: source.url,
            sessionId: currentStatus?.sessionId,
            warmupStartedAt: warmupStartedAt,
            warmupEndedAt: end,
            totalWarmupSeconds: end.timeIntervalSince(warmupStartedAt),
            peerCountTimeline: diagnosticHistory.map(\.peerCount),
            downloadSpeedTimeline: diagnosticHistory.map(\.downloadSpeedKbps),
            bufferSecondsTimeline: diagnosticHistory.map(\.bufferSeconds),
            firstSegmentReadyAt: diagnosticHistory.first(where: \.firstSegmentReady)?.updatedAt,
            readySegmentCountTimeline: diagnosticHistory.map(\.readySegmentCount),
            firstSegmentProbeResult: firstSegmentProbeResult,
            authValidationResult: source.url.absoluteString.contains("api_password") ? "Valid" : "Missing Auth",
            finalWarmupState: "\(state)",
            failureReason: nil,
            recommendedFix: nil
        )
    }

    private func extractCID(from url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "infohash" || $0.name == "id" })?.value ?? ""
    }

}
