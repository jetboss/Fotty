import Foundation

/// Backup freshness for the single player (player shrink slice 2, 9 Nov 2026).
///
/// While a match plays, its backup deliveries age: event bindings last 90 s
/// and upstream tokens rotate. Jet, 8 Nov 16:06 UTC: three hour-old backups
/// failed in 35 s and the session ended. The policy here is pure; the player
/// supplies its state and applies the result.
enum BackupFreshnessPolicy {
    /// Provider family used to decide which older backups a fresh lookup replaces.
    static func family(_ session: StreamSession) -> String {
        StreamEventBinding.providerCode(forSessionProviderName: session.providerName) ?? session.providerName.lowercased()
    }

    /// Replace older backups of every family present in `fresh`, keeping the
    /// playing session at its index so no transport state resets. Returns nil
    /// when nothing should change (no usable fresh choice, or the playing
    /// session could not keep its index).
    static func replacingBackups(in sessions: [StreamSession], with fresh: [StreamSession],
                                 active: StreamSession, matchID: String,
                                 isPlayable: (StreamSession) -> Bool,
                                 now: Date = Date()) -> [StreamSession]? {
        var seen: Set<StreamDeliveryIdentity> = [StreamDeliveryIdentity(url: active.playableURL, headers: active.requiredHeaders)]
        let incoming = fresh.filter { session in
            session.matchID == matchID && isPlayable(session) && !session.hasExpiredMediaLease(at: now)
                && seen.insert(StreamDeliveryIdentity(url: session.playableURL, headers: session.requiredHeaders)).inserted
        }
        guard !incoming.isEmpty, let activeIndex = sessions.firstIndex(where: { $0.id == active.id }) else { return nil }
        let refreshed = Set(incoming.map(family))
        var pending = incoming[...]
        var rebuilt: [StreamSession] = []
        for (offset, session) in sessions.enumerated() {
            let stale = session.id != active.id && refreshed.contains(family(session))
            if !stale { rebuilt.append(session); continue }
            if offset < activeIndex {
                // Refill in place so the playing session keeps its index; keep
                // the older entry only when no fresh replacement remains.
                rebuilt.append(pending.popFirst() ?? session)
            }
        }
        rebuilt.append(contentsOf: pending)
        // Defensive: never move the playing session; skip this refresh instead.
        guard rebuilt.indices.contains(activeIndex), rebuilt[activeIndex].id == active.id else { return nil }
        return rebuilt
    }

    /// Backups whose descriptor has lapsed and may be renewed now, in list
    /// order, up to `capacity`. Excludes the chosen backup (it renews on its own
    /// serial path), failed or already-renewed sources, and in-flight renewals.
    static func renewalCandidates(in sessions: [StreamSession], chosen: UUID, failed: Set<UUID>,
                                  alreadyRenewed: Set<UUID>, inFlight: Set<UUID>, capacity: Int,
                                  supportsRenewal: (StreamSession) -> Bool,
                                  now: Date = Date()) -> [StreamSession] {
        guard capacity > 0 else { return [] }
        return Array(sessions.filter { session in
            session.id != chosen && !failed.contains(session.id)
                && !alreadyRenewed.contains(session.id) && !inFlight.contains(session.id)
                && supportsRenewal(session)
                && (session.eventBinding?.isCurrent(at: now) == false || session.hasExpiredMediaLease(at: now))
        }.prefix(capacity))
    }
}

/// Owns the repeating backup-refresh task. The tick closure should capture its
/// owner weakly; stopping cancels the loop.
@MainActor
final class BackupRefreshScheduler {
    private var task: Task<Void, Never>?
    var isRunning: Bool { task != nil }

    func start(every interval: Duration, timing: FottyAsyncTiming,
               tick: @escaping @MainActor () async -> Bool) {
        guard task == nil else { return }
        task = Task {
            while !Task.isCancelled {
                do { try await timing.wait(for: interval) } catch { return }
                guard !Task.isCancelled, await tick() else { return }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

/// Accumulates incremental resolver choices for one backup refresh.
@MainActor
final class BackupChoiceCollector {
    private(set) var choices: [StreamSession] = []
    func add(_ sessions: [StreamSession]) { choices.append(contentsOf: sessions) }
}
