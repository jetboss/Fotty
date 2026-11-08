import AVFoundation
import Observation
import SwiftUI

enum SinglePlaybackAssignmentBasis: String {
    case stationTune = "station_tune", providerBinding = "provider_binding"
    case registryBinding = "registry_binding", publisherHandoff = "publisher_handoff", unknown
}

enum SinglePlaybackProgrammeObservation: String {
    case unobserved, viewerReportedWrong = "viewer_reported_wrong"
}

/// Date mapping supplied by the current AVPlayerItem. It describes the publisher's
/// media clock; the app has no trusted clock at the venue. All samples belong to
/// one item, attempt and uninterrupted, advancing foreground observation.
struct SinglePlaybackMediaClock {
    struct Sample {
        let uptime: TimeInterval
        let wall: Date
        let media: TimeInterval
        let programme: Date?
    }

    private var previous: Sample
    private var coherent = true
    private(set) var advertisedAgeMilliseconds: Int?

    init(first: Sample) { previous = first }

    mutating func observe(_ sample: Sample) {
        defer { previous = sample }
        let elapsed = sample.uptime - previous.uptime
        let advancement = sample.media - previous.media
        guard coherent, elapsed.isFinite, (12...22).contains(elapsed),
              advancement.isFinite, advancement > 0,
              abs(sample.wall.timeIntervalSince(previous.wall) - elapsed) <= 2,
              let earlier = previous.programme, let later = sample.programme,
              abs(later.timeIntervalSince(earlier) - advancement) <= 2 else {
            coherent = false
            advertisedAgeMilliseconds = nil
            return
        }
        // Negative or unusually old ages cannot be used for this live-window
        // measurement. Keep raw timestamps and any resulting uncertainty local.
        let age = sample.wall.timeIntervalSince(later)
        let previousAge = previous.wall.timeIntervalSince(earlier)
        guard (0...86_400).contains(age), (0...86_400).contains(previousAge) else {
            coherent = false
            advertisedAgeMilliseconds = nil
            return
        }
        advertisedAgeMilliseconds = Int((age * 1_000).rounded())
    }

    static func qualityDetails(web: Bool, advertisedAgeMilliseconds: Int? = nil) -> [String: String] {
        var details = ["live_event_delay_evidence": "unmeasured",
                       "media_clock_evidence": web ? "unavailable_web" : "unknown"]
        if !web, let age = advertisedAgeMilliseconds, (0...86_400_000).contains(age) {
            details["media_clock_evidence"] = "advertised_item_date"
            details["advertised_media_age_ms"] = String(age)
        }
        return details
    }
}

/// Access-log counters restart per event, including during a healthy rendition
/// switch. A comparison is meaningful only while the previous events survive.
struct SinglePlaybackAccessEvent: Equatable {
    let began: Date?
    let stalls: Int

    static func uninterrupted(previous: [Self]?, current: [Self]?) -> Bool {
        guard let previous else { return current?.allSatisfy { $0.stalls <= 0 } ?? true }
        guard let current, current.starts(with: previous) else { return false }
        return current.dropFirst(previous.count).allSatisfy { $0.stalls == 0 }
    }
}

enum SinglePlaybackQualityPreference: String, CaseIterable, Identifiable {
    case auto
    case dataSaver

    var id: String { rawValue }
    var title: String { self == .auto ? "Auto" : "Data Saver" }
}

/// HLS variant declarations describe available preferences, not decoded quality.
/// No URL selection, manifest rewriting or claim of a hard data cap belongs here.
enum SinglePlaybackQualityPolicy {
    struct Variant: Equatable, Sendable {
        let peakBitRate: Double
        let averageBitRate: Double
        let width: Double
        let height: Double

        var declaredBitRate: Double? {
            if peakBitRate.isFinite, peakBitRate > 0 { return peakBitRate }
            if averageBitRate.isFinite, averageBitRate > 0 { return averageBitRate }
            return nil
        }

        var isVideo: Bool {
            width.isFinite && height.isFinite && width > 0 && height > 0
        }
    }

    struct Limit: Equatable, Sendable {
        let peakBitRate: Double
        let maximumResolution: CGSize
    }

    // Product policy: prefer the highest declared video tier at or below this
    // target, otherwise the lowest tier. Apple treats either limit as a hint.
    static let dataSaverTargetBitRate = 1_500_000.0
    static let inspectionTimeout: Duration = .seconds(5)

    static func dataSaverLimit(variants: [Variant], originalPeakBitRate: Double = 0) -> Limit? {
        let video = variants.filter { $0.isVideo && $0.declaredBitRate != nil }.sorted {
            let left = $0.declaredBitRate ?? .infinity, right = $1.declaredBitRate ?? .infinity
            if left != right { return left < right }
            if $0.width != $1.width { return $0.width < $1.width }
            return $0.height < $1.height
        }
        guard let lowest = video.first, let highest = video.last,
              let lowestRate = lowest.declaredBitRate, let highestRate = highest.declaredBitRate,
              lowestRate < highestRate else { return nil }
        let originalCeiling = originalPeakBitRate.isFinite && originalPeakBitRate > 0 ? originalPeakBitRate : .infinity
        let automaticCeiling = min(highestRate, originalCeiling)
        // Auto is already at or below every declared video tier. Do not offer
        // a second choice that cannot meaningfully lower that existing ceiling.
        guard lowestRate < automaticCeiling else { return nil }
        let selected = video.last {
            guard let rate = $0.declaredBitRate else { return false }
            return rate <= dataSaverTargetBitRate && rate < automaticCeiling
        } ?? lowest
        guard let selectedRate = selected.declaredBitRate, selectedRate < automaticCeiling else { return nil }
        return Limit(peakBitRate: selectedRate, maximumResolution: CGSize(width: selected.width, height: selected.height))
    }

    static func constrainedResolution(_ proposed: CGSize, original: CGSize) -> CGSize {
        guard original.width.isFinite, original.height.isFinite, original.width > 0, original.height > 0 else { return proposed }
        return CGSize(width: min(proposed.width, original.width), height: min(proposed.height, original.height))
    }
}

/// One current native single-player item owns this optional choice. Auto keeps
/// the item's original preferences. Changing a preference never controls rate,
/// seeks, swaps an item or resolves a new source. Nothing is persisted or synced.
@Observable @MainActor
final class SinglePlaybackQualityController {
    typealias VariantLoader = @MainActor (AVURLAsset) async throws -> [SinglePlaybackQualityPolicy.Variant]

    private(set) var preference = SinglePlaybackQualityPreference.auto
    private(set) var dataSaverLimit: SinglePlaybackQualityPolicy.Limit?
    var isAvailable: Bool { dataSaverLimit != nil }

    private struct Identity: Equatable {
        let item: ObjectIdentifier
        let source: UUID
        let request: UUID
    }
    private struct Binding {
        weak var player: AVPlayer?
        weak var item: AVPlayerItem?
        let identity: Identity
        let originalPeakBitRate: Double
        let originalMaximumResolution: CGSize
        let isCurrent: @MainActor () -> Bool
    }

    @ObservationIgnored private let loadVariants: VariantLoader
    @ObservationIgnored private var binding: Binding?
    @ObservationIgnored private var inspectedIdentity: Identity?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var inspectionTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    init(loadVariants: @escaping VariantLoader = SinglePlaybackQualityController.declaredVariants) {
        self.loadVariants = loadVariants
    }

    private static func declaredVariants(_ asset: AVURLAsset) async throws -> [SinglePlaybackQualityPolicy.Variant] {
        let variants = try await asset.load(.variants)
        return variants.compactMap { variant -> SinglePlaybackQualityPolicy.Variant? in
            guard let video = variant.videoAttributes else { return nil }
            return .init(peakBitRate: variant.peakBitRate ?? -1, averageBitRate: variant.averageBitRate ?? -1,
                         width: video.presentationSize.width, height: video.presentationSize.height)
        }
    }

    func inspect(player: AVPlayer, item: AVPlayerItem, sourceID: UUID, requestID: UUID,
                 isCurrent: @escaping @MainActor () -> Bool) {
        let identity = Identity(item: ObjectIdentifier(item), source: sourceID, request: requestID)
        guard inspectedIdentity != identity else { return }
        invalidate()
        inspectedIdentity = identity
        guard player.currentItem === item, let asset = item.asset as? AVURLAsset, isCurrent() else { return }
        binding = Binding(player: player, item: item, identity: identity,
            originalPeakBitRate: item.preferredPeakBitRate, originalMaximumResolution: item.preferredMaximumResolution,
            isCurrent: isCurrent)
        let expectedGeneration = generation
        let loader = loadVariants
        inspectionTask = Task { @MainActor [weak self] in
            let variants = try? await loader(asset)
            guard let self, !Task.isCancelled, self.generation == expectedGeneration,
                  let current = self.binding, current.identity == identity, current.isCurrent(),
                  current.player?.currentItem === current.item else { return }
            self.timeoutTask?.cancel()
            self.timeoutTask = nil
            self.inspectionTask = nil
            if let variants {
                self.dataSaverLimit = SinglePlaybackQualityPolicy.dataSaverLimit(variants: variants,
                    originalPeakBitRate: current.originalPeakBitRate)
            }
        }
        timeoutTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: SinglePlaybackQualityPolicy.inspectionTimeout) }
            catch { return }
            guard let self, self.generation == expectedGeneration else { return }
            // Never call asset.cancelLoading(): the same asset owns playback.
            self.generation = UUID()
            self.inspectionTask?.cancel()
            self.inspectionTask = nil
            self.timeoutTask = nil
            self.binding = nil
            self.dataSaverLimit = nil
        }
    }

    func matches(player: AVPlayer, item: AVPlayerItem, sourceID: UUID, requestID: UUID) -> Bool {
        guard let binding, binding.player === player, binding.item === item,
              player.currentItem === item, binding.identity.source == sourceID,
              binding.identity.request == requestID, binding.isCurrent() else { return false }
        return isAvailable
    }

    @discardableResult
    func select(_ choice: SinglePlaybackQualityPreference) -> Bool {
        guard let binding, let item = binding.item, let limit = dataSaverLimit,
              binding.player?.currentItem === item, binding.isCurrent() else { return false }
        switch choice {
        case .auto:
            item.preferredPeakBitRate = binding.originalPeakBitRate
            item.preferredMaximumResolution = binding.originalMaximumResolution
        case .dataSaver:
            item.preferredPeakBitRate = limit.peakBitRate
            item.preferredMaximumResolution = SinglePlaybackQualityPolicy.constrainedResolution(
                limit.maximumResolution, original: binding.originalMaximumResolution)
        }
        preference = choice
        return true
    }

    func invalidate() {
        generation = UUID()
        inspectionTask?.cancel(); inspectionTask = nil
        timeoutTask?.cancel(); timeoutTask = nil
        if preference == .dataSaver, let binding, let item = binding.item {
            item.preferredPeakBitRate = binding.originalPeakBitRate
            item.preferredMaximumResolution = binding.originalMaximumResolution
        }
        binding = nil
        inspectedIdentity = nil
        dataSaverLimit = nil
        preference = .auto
    }
}

struct SinglePlaybackQualityMenu: View {
    @Binding var selection: SinglePlaybackQualityPreference

    var body: some View {
        Picker(selection: $selection) {
            ForEach(SinglePlaybackQualityPreference.allCases) { choice in
                Text(choice.title).tag(choice)
            }
        } label: {
            Label("Quality", systemImage: "slider.horizontal.3")
        }
        .accessibilityValue(selection.title)
        .accessibilityHint("Data Saver prefers a lower-bandwidth rendition when the stream supports it")
        .accessibilityIdentifier("single-playback-quality")
    }
}
