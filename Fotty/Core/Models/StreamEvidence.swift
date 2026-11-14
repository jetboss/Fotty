import Foundation

/// An opaque, device-keyed SHA-256 HMAC. Only the device-local factory creates
/// production values; raw source identity and delivery contracts stay transient.
struct DeviceHMAC: Hashable, Codable, Sendable {
    let bytes: Data

    init(bytes: Data) { self.bytes = bytes }

    var isValid: Bool { bytes.count == 32 }

    private enum CodingKeys: String, CodingKey { case bytes }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bytes = try container.decode(Data.self, forKey: .bytes)
        guard isValid else {
            throw DecodingError.dataCorruptedError(forKey: .bytes, in: container,
                debugDescription: "Invalid device digest length")
        }
    }
}

typealias EvidenceProvider = CuratedStreamSourceCatalog.Provider

enum ProgrammeScope: Hashable, Codable, Sendable {
    case fixture(DeviceHMAC)
    case channelProgramme(channel: DeviceHMAC, programme: DeviceHMAC)

    fileprivate var isValid: Bool {
        switch self {
        case .fixture(let fixture): return fixture.isValid
        case .channelProgramme(let channel, let programme): return channel.isValid && programme.isValid
        }
    }
}

struct DeliveryProvenance: Equatable, Codable, Sendable {
    let schemaVersion: Int
    let scope: ProgrammeScope
    let provider: EvidenceProvider
    let listing: DeviceHMAC
    let contract: DeviceHMAC
    let lookupID, configurationGeneration: UUID
    let watchID: UUID?
    let observedAt: Date

    init(schemaVersion: Int, scope: ProgrammeScope, provider: EvidenceProvider, listing: DeviceHMAC,
         contract: DeviceHMAC, lookupID: UUID, configurationGeneration: UUID, watchID: UUID?, observedAt: Date) {
        self.schemaVersion = schemaVersion
        self.scope = scope
        self.provider = provider
        self.listing = listing
        self.contract = contract
        self.lookupID = lookupID
        self.configurationGeneration = configurationGeneration
        self.watchID = watchID
        self.observedAt = observedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, scope, provider, listing, contract, lookupID, configurationGeneration, watchID, observedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        scope = try container.decode(ProgrammeScope.self, forKey: .scope)
        let rawProvider = try container.decode(String.self, forKey: .provider)
        guard let provider = EvidenceProvider(rawValue: rawProvider) else {
            throw DecodingError.dataCorruptedError(forKey: .provider, in: container,
                debugDescription: "Unknown evidence provider")
        }
        self.provider = provider
        listing = try container.decode(DeviceHMAC.self, forKey: .listing)
        contract = try container.decode(DeviceHMAC.self, forKey: .contract)
        lookupID = try container.decode(UUID.self, forKey: .lookupID)
        configurationGeneration = try container.decode(UUID.self, forKey: .configurationGeneration)
        watchID = try container.decodeIfPresent(UUID.self, forKey: .watchID)
        observedAt = try container.decode(Date.self, forKey: .observedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(scope, forKey: .scope)
        try container.encode(provider.rawValue, forKey: .provider)
        try container.encode(listing, forKey: .listing)
        try container.encode(contract, forKey: .contract)
        try container.encode(lookupID, forKey: .lookupID)
        try container.encode(configurationGeneration, forKey: .configurationGeneration)
        try container.encodeIfPresent(watchID, forKey: .watchID)
        try container.encode(observedAt, forKey: .observedAt)
    }
}

enum MetadataComparison: String, Codable, Sendable {
    case agrees, contradicts, noParseableTeams
}

struct DeliveryMetadataReceipt: Equatable, Codable, Sendable {
    let provenance: DeliveryProvenance
    let hasName, hasTitle: Bool
    let comparison: MetadataComparison
    let comparedAt, expiresAt: Date
}

enum ViewerVerdict: String, Codable, Sendable { case confirmed, rejected }

enum ProgrammeCorrectness: String, Codable, Sendable {
    case unknown, metadataAgrees, viewerConfirmed, viewerRejected
}

enum CorrectnessExpiry: Equatable, Codable, Sendable {
    case attemptOnly
    case boundary(Date)
}

struct ProgrammeEvidence: Equatable, Codable, Sendable {
    let provenance: DeliveryProvenance
    let attemptID: UUID
    let verdict: ViewerVerdict
    let observedAt: Date
    let expiry: CorrectnessExpiry
}

struct FixtureLookupCounts: Equatable, Sendable {
    let fixture: DeviceHMAC
    let provider: EvidenceProvider
    let window: DateInterval
    let lookups: Int
    let observedEntries, uniqueObservedContracts: Int
    let readResponses, unreadResponses, knownEmptyResponses: Int
    let webOnlyLookups: Int
    let isTruncated: Bool
}

/// Pure local evidence storage. Playback outcomes have no input here: even an
/// indefinitely decoded picture cannot establish programme correctness. Expired
/// observations remain within the same bounds solely to prevent replay from
/// extending their original expiry; collection size is not active authority.
struct ProgrammeEvidenceLedger: Sendable {
    static let maximumRecords = 256
    static let maximumRetention: TimeInterval = 7 * 24 * 60 * 60

    private(set) var metadataReceipts: [DeliveryMetadataReceipt] = []
    private(set) var viewerEvidence: [ProgrammeEvidence] = []
    var count: Int { metadataReceipts.count + viewerEvidence.count }

    init() {}

    init(snapshot: Snapshot, at now: Date) {
        guard snapshot.schemaVersion == 1, Self.finite(now) else { return }
        for receipt in snapshot.metadataReceipts { retain(receipt, at: now, restoring: true) }
        for evidence in snapshot.viewerEvidence {
            // Even a manually constructed snapshot cannot restore an attempt.
            guard case .boundary = evidence.expiry else { continue }
            retain(evidence, at: now, restoring: true)
        }
    }

    @discardableResult
    mutating func record(_ receipt: DeliveryMetadataReceipt, at now: Date) -> Bool {
        retain(receipt, at: now, restoring: false)
    }

    @discardableResult
    private mutating func retain(_ receipt: DeliveryMetadataReceipt, at now: Date, restoring: Bool) -> Bool {
        guard Self.retainable(receipt, at: now), restoring || Self.valid(receipt, at: now) else { return false }
        if let index = metadataReceipts.firstIndex(where: {
            Self.sameContext($0.provenance, receipt.provenance) && $0.provenance.lookupID == receipt.provenance.lookupID
                && $0.comparedAt == receipt.comparedAt && $0.comparison == receipt.comparison
                && $0.hasName == receipt.hasName && $0.hasTitle == receipt.hasTitle
        }) {
            // Re-emitting an observation cannot give it a later expiry.
            let original = metadataReceipts[index]
            let bounded = DeliveryMetadataReceipt(provenance: original.provenance,
                hasName: original.hasName, hasTitle: original.hasTitle, comparison: original.comparison,
                comparedAt: original.comparedAt, expiresAt: min(original.expiresAt, receipt.expiresAt))
            guard restoring || Self.valid(bounded, at: now) else { prune(at: now); return false }
            metadataReceipts[index] = bounded
            prune(at: now)
        } else {
            prune(at: now)
            metadataReceipts.append(receipt)
        }
        enforceLimit()
        return true
    }

    @discardableResult
    mutating func record(_ evidence: ProgrammeEvidence, at now: Date) -> Bool {
        retain(evidence, at: now, restoring: false)
    }

    @discardableResult
    private mutating func retain(_ evidence: ProgrammeEvidence, at now: Date, restoring: Bool) -> Bool {
        guard Self.retainable(evidence, at: now), restoring || Self.valid(evidence, at: now) else { return false }
        if let index = viewerEvidence.firstIndex(where: {
            Self.sameContext($0.provenance, evidence.provenance) && $0.attemptID == evidence.attemptID
                && $0.observedAt == evidence.observedAt && $0.verdict == evidence.verdict
        }) {
            let original = viewerEvidence[index]
            let expiry: CorrectnessExpiry
            switch (original.expiry, evidence.expiry) {
            case (.boundary(let first), .boundary(let second)): expiry = .boundary(min(first, second))
            case (.attemptOnly, .attemptOnly): expiry = .attemptOnly
            // Changing expiry kind is not a new viewer action. In particular,
            // attemptOnly must not revive an already-ended boundary, or gain
            // persistence by being re-emitted with a boundary.
            default: prune(at: now); return false
            }
            let bounded = ProgrammeEvidence(provenance: original.provenance, attemptID: original.attemptID,
                verdict: original.verdict, observedAt: original.observedAt, expiry: expiry)
            guard restoring || Self.valid(bounded, at: now) else { prune(at: now); return false }
            viewerEvidence[index] = bounded
            prune(at: now)
        } else {
            prune(at: now)
            viewerEvidence.append(evidence)
        }
        enforceLimit()
        return true
    }

    func correctness(for provenance: DeliveryProvenance, attemptID: UUID?, expiry: CorrectnessExpiry,
                     at now: Date) -> ProgrammeCorrectness {
        guard Self.valid(provenance, at: now), Self.current(expiry, at: now) else { return .unknown }
        let explicit = viewerEvidence.filter { evidence in
            guard Self.valid(evidence, at: now), Self.sameContext(evidence.provenance, provenance) else { return false }
            if case .attemptOnly = expiry { return evidence.attemptID == attemptID }
            if case .attemptOnly = evidence.expiry { return evidence.attemptID == attemptID }
            return true
        }.max { left, right in
            if left.observedAt != right.observedAt { return left.observedAt < right.observedAt }
            return left.verdict == .confirmed && right.verdict == .rejected
        }
        if let explicit { return explicit.verdict == .confirmed ? .viewerConfirmed : .viewerRejected }

        let metadata = metadataReceipts.filter { receipt in
            guard Self.valid(receipt, at: now), Self.sameContext(receipt.provenance, provenance) else { return false }
            if case .attemptOnly = expiry {
                return receipt.provenance.lookupID == provenance.lookupID && receipt.provenance.watchID == provenance.watchID
            }
            return true
        }
        // Contradictory metadata is a separate fact, never a viewer verdict.
        guard !metadata.contains(where: { $0.comparison == .contradicts }) else { return .unknown }
        return metadata.contains(where: { $0.comparison == .agrees }) ? .metadataAgrees : .unknown
    }

    mutating func prune(at now: Date) {
        guard Self.finite(now) else { return }
        metadataReceipts.removeAll { !Self.retainable($0, at: now) }
        viewerEvidence.removeAll { !Self.retainable($0, at: now) }
    }

    mutating func endAttempt(_ attemptID: UUID) {
        viewerEvidence.removeAll {
            guard $0.attemptID == attemptID, case .attemptOnly = $0.expiry else { return false }
            return true
        }
    }

    func persisted(at now: Date) -> Snapshot {
        Snapshot(metadataReceipts: metadataReceipts.filter { Self.retainable($0, at: now) },
                 viewerEvidence: viewerEvidence.filter {
                     guard case .boundary = $0.expiry else { return false }
                     return Self.retainable($0, at: now)
                 })
    }

    private mutating func enforceLimit() {
        while count > Self.maximumRecords {
            let metadata = metadataReceipts.indices.min { metadataReceipts[$0].comparedAt < metadataReceipts[$1].comparedAt }
            let viewer = viewerEvidence.indices.min { viewerEvidence[$0].observedAt < viewerEvidence[$1].observedAt }
            if let metadata, viewer == nil || metadataReceipts[metadata].comparedAt <= viewerEvidence[viewer!].observedAt {
                metadataReceipts.remove(at: metadata)
            } else if let viewer { viewerEvidence.remove(at: viewer) }
        }
    }

    private static func finite(_ date: Date) -> Bool { date.timeIntervalSinceReferenceDate.isFinite }

    private static func retained(_ observed: Date, at now: Date) -> Bool {
        finite(now) && finite(observed) && observed <= now && now.timeIntervalSince(observed) < maximumRetention
    }

    private static func current(_ expiry: CorrectnessExpiry, at now: Date) -> Bool {
        guard finite(now) else { return false }
        switch expiry {
        case .attemptOnly: return true
        case .boundary(let end): return finite(end) && now < end
        }
    }

    private static func valid(_ provenance: DeliveryProvenance, at now: Date) -> Bool {
        provenance.schemaVersion == 1 && provenance.scope.isValid && provenance.listing.isValid
            && provenance.contract.isValid && retained(provenance.observedAt, at: now)
    }

    private static func valid(_ receipt: DeliveryMetadataReceipt, at now: Date) -> Bool {
        retainable(receipt, at: now) && now < receipt.expiresAt
    }

    private static func retainable(_ receipt: DeliveryMetadataReceipt, at now: Date) -> Bool {
        valid(receipt.provenance, at: now) && retained(receipt.comparedAt, at: now)
            && receipt.provenance.observedAt <= receipt.comparedAt
            && finite(receipt.expiresAt) && receipt.comparedAt < receipt.expiresAt
            && (receipt.comparison == .noParseableTeams || receipt.hasName || receipt.hasTitle)
    }

    private static func valid(_ evidence: ProgrammeEvidence, at now: Date) -> Bool {
        retainable(evidence, at: now) && current(evidence.expiry, at: now)
    }

    private static func retainable(_ evidence: ProgrammeEvidence, at now: Date) -> Bool {
        guard valid(evidence.provenance, at: now), retained(evidence.observedAt, at: now),
              evidence.provenance.observedAt <= evidence.observedAt else { return false }
        switch evidence.expiry {
        case .attemptOnly: return true
        case .boundary(let end): return finite(end) && evidence.observedAt < end
        }
    }

    private static func sameContext(_ left: DeliveryProvenance, _ right: DeliveryProvenance) -> Bool {
        left.scope == right.scope && left.provider == right.provider && left.contract == right.contract
            && left.configurationGeneration == right.configurationGeneration
    }

    struct Snapshot: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let metadataReceipts: [DeliveryMetadataReceipt]
        let viewerEvidence: [ProgrammeEvidence]

        init(schemaVersion: Int = 1, metadataReceipts: [DeliveryMetadataReceipt], viewerEvidence: [ProgrammeEvidence]) {
            self.schemaVersion = schemaVersion
            self.metadataReceipts = metadataReceipts
            self.viewerEvidence = viewerEvidence
        }

        private enum CodingKeys: String, CodingKey { case schemaVersion, metadataReceipts, viewerEvidence }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            guard schemaVersion == 1 else {
                throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: container,
                    debugDescription: "Unknown evidence snapshot version")
            }
            var metadata = try container.nestedUnkeyedContainer(forKey: .metadataReceipts)
            var receipts: [DeliveryMetadataReceipt] = []
            while !metadata.isAtEnd {
                guard receipts.count < ProgrammeEvidenceLedger.maximumRecords else {
                    throw DecodingError.dataCorruptedError(in: metadata, debugDescription: "Evidence limit exceeded")
                }
                receipts.append(try metadata.decode(DeliveryMetadataReceipt.self))
            }
            var viewer = try container.nestedUnkeyedContainer(forKey: .viewerEvidence)
            var evidence: [ProgrammeEvidence] = []
            while !viewer.isAtEnd {
                guard receipts.count + evidence.count < ProgrammeEvidenceLedger.maximumRecords else {
                    throw DecodingError.dataCorruptedError(in: viewer, debugDescription: "Evidence limit exceeded")
                }
                evidence.append(try viewer.decode(ProgrammeEvidence.self))
            }
            metadataReceipts = receipts
            viewerEvidence = evidence
        }
    }
}
