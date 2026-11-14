I agree with the ownership, ordering and quiet optional confirmation. Two clarifications: stable playback never establishes programme correctness, and ten eligible fixtures across two weeks should trigger owner review—not classify unconfirmed viewing as failure. Metadata and viewer observations should remain separate facts.

Claude’s **Reviewed TV correction does not match this working tree**. [`admitsDelivery(_:channel:)`](/Users/jelani/Documents/Development/Fotty/Fotty/Core/Networking/ReviewedTVPlaylistClient.swift:596) directly calls `StreamDeliveryPolicy.rejection`. Both [JSON](/Users/jelani/Documents/Development/Fotty/Fotty/Core/Networking/ReviewedTVPlaylistClient.swift:210) and [M3U](/Users/jelani/Documents/Development/Fotty/Fotty/Core/Networking/ReviewedTVPlaylistClient.swift:701) parsing use that policy. [Playlist provenance](/Users/jelani/Documents/Development/Fotty/Fotty/Core/Networking/ReviewedTVPlaylistClient.swift:611) and exact station identity remain pinned; delivery hosts, paths, queries and extensions are no longer independently allow-listed. Item 4 should therefore list measured remaining gaps, without another TV migration.

I propose freezing these types. Every `DeviceHMAC` field is a **device-keyed, domain-separated HMAC**, reusing the existing device-local key. Raw identifiers, labels, URLs and headers remain transient.

```swift
struct DeviceHMAC: Hashable, Sendable {
    let bytes: Data
}

typealias EvidenceProvider = CuratedStreamSourceCatalog.Provider

enum ProgrammeScope: Hashable, Sendable {
    case fixture(DeviceHMAC)
    case channelProgramme(channel: DeviceHMAC, programme: DeviceHMAC)
}

struct DeliveryProvenance: Sendable {
    let schemaVersion: Int
    let scope: ProgrammeScope
    let provider: EvidenceProvider
    let listing: DeviceHMAC
    let contract: DeviceHMAC // Full URL/query, effective headers, endpoint/container.
    let lookupID, configurationGeneration: UUID
    let watchID: UUID? // Preflight may precede a Watch.
    let observedAt: Date
}

enum MetadataComparison: Sendable {
    case agrees, contradicts, noParseableTeams
}

struct DeliveryMetadataReceipt: Sendable {
    let provenance: DeliveryProvenance
    let hasName, hasTitle: Bool
    let comparison: MetadataComparison // Any parseable contradiction wins.
    let comparedAt, expiresAt: Date
}

enum ViewerVerdict: Sendable {
    case confirmed, rejected
}

enum ProgrammeCorrectness: Sendable {
    // Derived presentation; never inferred from playback duration.
    case unknown, metadataAgrees, viewerConfirmed, viewerRejected
}

enum CorrectnessExpiry: Sendable {
    case attemptOnly // No authoritative programme boundary.
    case boundary(Date) // Fixture live-window end or programme boundary.
}

struct ProgrammeEvidence: Sendable {
    let provenance: DeliveryProvenance
    let attemptID: UUID
    let verdict: ViewerVerdict // Explicit viewer action only.
    let observedAt: Date
    let expiry: CorrectnessExpiry
    // Contract/configuration/scope changes invalidate immediately.
}

struct FixtureLookupCounts: Sendable {
    let fixture: DeviceHMAC
    let provider: EvidenceProvider
    let window: DateInterval
    let lookups: Int // Distinct lookup UUIDs; repeated searches count.
    let observedEntries, uniqueObservedContracts: Int
    let readResponses, unreadResponses, knownEmptyResponses: Int
    let webOnlyLookups: Int // No invented raw-stream zero.
    let isTruncated: Bool
}
```

Observed counts describe retained evidence, not unseen totals. Metadata ranking waits for representative receipts demonstrating useful team labels.

Land **Codex 1** as the shared base; subsequent tasks are separate passing PRs. Claude handles project-file integration.

- **Codex 1: evidence foundation and expiry.** New `Fotty/Core/Models/StreamEvidence.swift`; update `MediaModels.swift`, `LiveSourceHealthStore.swift`, and `LiveSourceHealthScopeTests.swift`; add `StreamEvidenceTests.swift`. Verify contract distinctions, fixture isolation, explicit-verdict precedence, renewal invalidation, programme boundaries and relaunch expiry. Playback history must never become confirmed correctness.

- **Codex 2: Highfly/PenguPlay receipts and accounting.** Update both `*SportsAddonClient.swift` adapters, `FottyLogger.swift`, their adapter tests and `WatchOutcomeRecordTests.swift`. Verify missing/malformed labels, contradictory fields, multiple listings, duplicate receipts, repeated lookups, unread/partial responses and absence of raw private values. Keep label-based ranking unchanged initially.

- **Claude 1: lifecycle regression coverage.** Update `ViewingSessionCoordinatorTests.swift` and `LivePlayerRetryLifecycleTests.swift`. Exercise pause during renewal, cancelled discovery, replaced attempts and late recovery callbacks against existing ownership. Any required repair stays within `ViewingSessionCoordinator.swift` and `LivePlayerViewModel.swift`.

- **Claude 2: feedback and evidence presentation.** Update `LivePlayerViewModel.swift`, `LivePlayerView.swift`, `Components/LiveStreamSelectorSheet.swift`, `SettingsSupportViews.swift`, and focused lifecycle/UI tests. Provide separate one-tap Wrong match/Picture blocked actions, quiet optional Right match, and fixture evidence/counts. Verify stale-action fencing, blocked-picture neutrality and mostly-unknown states.

No files changed; no builds or tests run.