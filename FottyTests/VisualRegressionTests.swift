import CryptoKit
import SwiftUI
import UIKit
import XCTest
@testable import Fotty

/// A bounded, test-owned UIKit hierarchy for components containing native
/// controls. ImageRenderer substitutes a prohibited-symbol placeholder for
/// UIKit-backed Menu, so it cannot establish that control's real appearance.
/// This remains a static Catalyst/iOS host capture, not physical interaction.
@MainActor
enum FottyHostedViewSnapshot {
    static let methodID = "UIHostingController.drawHierarchy.v1"
    enum Failure: Error {
        case missingWindowScene, invalidSize, hostSizeMismatch, incompleteHierarchy
    }

    static func image<Content: View>(
        _ content: Content, width: CGFloat, scheme: ColorScheme, type: DynamicTypeSize
    ) throws -> UIImage {
        guard width.isFinite, width > 0, width <= 2_000 else { throw Failure.invalidSize }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { throw Failure.missingWindowScene }
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let host = UIHostingController(rootView: content.ignoresSafeArea())
        host.loadViewIfNeeded()
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.traitOverrides.preferredContentSizeCategory = contentSizeCategory(for: type)
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: 4_000)
        host.view.layoutIfNeeded()
        let fittingSize = host.sizeThatFits(in: CGSize(width: width, height: 4_000))
        let size = CGSize(width: width, height: ceil(fittingSize.height))
        guard fittingSize.width.isFinite, size.height.isFinite, size.height > 0,
              size.height <= 4_000, size.width * size.height <= 4_000_000 else { throw Failure.invalidSize }

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.backgroundColor = .clear
        window.rootViewController = host
        defer {
            window.isHidden = true
            window.rootViewController = nil
            if previousKeyWindow?.isHidden == false { previousKeyWindow?.makeKey() }
        }
        UIView.performWithoutAnimation {
            window.makeKeyAndVisible()
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }
        guard abs(host.view.bounds.width - width) < 0.5,
              abs(host.view.bounds.height - size.height) < 0.5 else { throw Failure.hostSizeMismatch }
        CATransaction.flush()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        var complete = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            complete = host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        guard complete else { throw Failure.incompleteHierarchy }
        return image
    }

    private static func contentSizeCategory(for type: DynamicTypeSize) -> UIContentSizeCategory {
        switch type {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

/// Test-only normalized RGBA comparison. PNG compression/metadata is not a
/// visual change; dimensions and visible pixels are. This deliberately does
/// not add a rendering framework to the shipped application.
enum FottyVisualPixelComparison {
    struct Policy {
        var channelTolerance = 1
        var maximumDifferentPixelFraction = 0.0001
        var maximumMeanChannelDifference = 0.02
    }

    struct Pixels {
        let width: Int
        let height: Int
        let rgba: [UInt8]

        init(image: UIImage) throws {
            guard let cgImage = image.cgImage else { throw Failure.noBitmap }
            let width = cgImage.width, height = cgImage.height
            guard width > 0, height > 0, width <= 2_000, height <= 4_000,
                  width * height <= 4_000_000 else { throw Failure.excessiveSize }
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = bytes.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
                else { return false }
                context.interpolationQuality = .none
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { throw Failure.noBitmap }
            self.width = width
            self.height = height
            rgba = bytes
        }

        init(width: Int, height: Int, rgba: [UInt8]) {
            self.width = width; self.height = height; self.rgba = rgba
        }
    }

    enum Failure: Error { case noBitmap, excessiveSize, malformedPixels, invalidPolicy }
    struct Result {
        let matches: Bool
        let differentPixelFraction: Double
        let meanChannelDifference: Double
        let description: String
    }

    static func compare(_ actual: Pixels, _ expected: Pixels, policy: Policy = .init()) throws -> Result {
        guard (0...255).contains(policy.channelTolerance),
              policy.maximumDifferentPixelFraction.isFinite,
              (0...1).contains(policy.maximumDifferentPixelFraction),
              policy.maximumMeanChannelDifference.isFinite,
              (0...255).contains(policy.maximumMeanChannelDifference) else { throw Failure.invalidPolicy }
        for pixels in [actual, expected] {
            guard pixels.width > 0, pixels.height > 0, pixels.width <= 2_000, pixels.height <= 4_000,
                  pixels.width * pixels.height <= 4_000_000,
                  pixels.rgba.count == pixels.width * pixels.height * 4 else { throw Failure.malformedPixels }
        }
        guard actual.width == expected.width, actual.height == expected.height else {
            return Result(matches: false, differentPixelFraction: 1, meanChannelDifference: 255,
                description: "Dimensions changed: \(expected.width)×\(expected.height) → \(actual.width)×\(actual.height)")
        }
        var differentPixels = 0
        var totalDifference: UInt64 = 0
        for offset in stride(from: 0, to: actual.rgba.count, by: 4) {
            var differs = false
            for channel in 0..<4 {
                let delta = abs(Int(actual.rgba[offset + channel]) - Int(expected.rgba[offset + channel]))
                totalDifference += UInt64(delta)
                if delta > policy.channelTolerance { differs = true }
            }
            if differs { differentPixels += 1 }
        }
        let fraction = Double(differentPixels) / Double(actual.width * actual.height)
        let mean = Double(totalDifference) / Double(actual.rgba.count)
        return Result(matches: fraction <= policy.maximumDifferentPixelFraction && mean <= policy.maximumMeanChannelDifference,
            differentPixelFraction: fraction, meanChannelDifference: mean,
            description: String(format: "Different pixels %.5f%%; mean RGBA difference %.5f/255", fraction * 100, mean))
    }
}

final class VisualPixelComparisonTests: XCTestCase {
    private let black = FottyVisualPixelComparison.Pixels(width: 2, height: 2,
        rgba: Array(repeating: [UInt8(0), 0, 0, 255], count: 4).flatMap { $0 })

    func testIdenticalNormalizedPixelsPass() throws {
        XCTAssertTrue(try FottyVisualPixelComparison.compare(black, black).matches)
    }

    func testDimensionChangeFailsEvenWhenByteCountMatches() throws {
        let changed = FottyVisualPixelComparison.Pixels(width: 1, height: 4, rgba: black.rgba)
        XCTAssertFalse(try FottyVisualPixelComparison.compare(changed, black).matches)
    }

    func testSmallButVisibleArtworkChangeFails() throws {
        var changed = black.rgba; changed[0] = 255
        XCTAssertFalse(try FottyVisualPixelComparison.compare(.init(width: 2, height: 2, rgba: changed), black).matches)
    }

    func testSubToleranceRoundingIsStillBoundedByMeanDifference() throws {
        var changed = black.rgba
        for offset in stride(from: 0, to: changed.count, by: 4) { changed[offset] = 1 }
        let result = try FottyVisualPixelComparison.compare(.init(width: 2, height: 2, rgba: changed), black)
        XCTAssertEqual(result.differentPixelFraction, 0)
        XCTAssertFalse(result.matches, "A low-frequency whole-image change cannot bypass the mean-difference limit")
    }

    func testShiftedPixelsAndTransparencyChangesFail() throws {
        let first = FottyVisualPixelComparison.Pixels(width: 2, height: 1, rgba: [255, 0, 0, 255, 0, 0, 0, 255])
        let shifted = FottyVisualPixelComparison.Pixels(width: 2, height: 1, rgba: [0, 0, 0, 255, 255, 0, 0, 255])
        let transparent = FottyVisualPixelComparison.Pixels(width: 2, height: 1, rgba: [255, 0, 0, 0, 0, 0, 0, 255])
        XCTAssertFalse(try FottyVisualPixelComparison.compare(first, shifted).matches)
        XCTAssertFalse(try FottyVisualPixelComparison.compare(first, transparent).matches)
    }

    func testMalformedAndOversizedBuffersAreRejected() {
        for invalid in [FottyVisualPixelComparison.Pixels(width: 2, height: 2, rgba: []),
                        .init(width: 0, height: 2, rgba: []), .init(width: 2_001, height: 1, rgba: [])] {
            XCTAssertThrowsError(try FottyVisualPixelComparison.compare(invalid, black))
        }
    }

    func testInvalidToleranceCannotTurnOffTheGate() {
        XCTAssertThrowsError(try FottyVisualPixelComparison.compare(black, black,
            policy: .init(channelTolerance: -1)))
        XCTAssertThrowsError(try FottyVisualPixelComparison.compare(black, black,
            policy: .init(maximumDifferentPixelFraction: .nan)))
    }

    @MainActor
    func testPNGEncodingRoundTripNormalizesToTheSamePixels() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let decoded = try XCTUnwrap(UIImage(data: XCTUnwrap(image.pngData())))
        XCTAssertTrue(try FottyVisualPixelComparison.compare(.init(image: image), .init(image: decoded)).matches)
    }
}

/// Pinned Catalyst component captures, not proof of complete UIKit/WebKit
/// journeys, system glass, touch behaviour, sound or physical-device layout.
/// Native-control appearance can be hosted; interaction retains its iPad gate.
@MainActor
final class VisualRegressionTests: XCTestCase {
    private struct Spec {
        let id: String
        let width: CGFloat
        let scheme: ColorScheme
        let type: DynamicTypeSize
        let surface: String
    }
    private struct Record: Codable {
        let id: String
        let file: String
        let sha256: String
        let width: Int
        let height: Int
        let surface: String
        let appearance: String
        let textSize: String
    }
    private struct Manifest: Codable {
        let schema: Int
        let fixtureRevision: String
        let renderer: [String: String]
        let records: [Record]
        let reviewedBy: String?
        let reviewedAt: String?
        let sourceReceipt: String?
    }
    private static let fixtureRevision = "fotty-components-20261010-v1"
    private static let now = Date(timeIntervalSince1970: 4_000_000_000)
    private static let loadedURL = URL(string: "https://visual-fixture.invalid/alpha-badge.png")!
    private static let specs: [Spec] = [
        .init(id: "home-phone-dark", width: 375, scheme: .dark, type: .large, surface: "home"),
        .init(id: "home-phone-light", width: 375, scheme: .light, type: .large, surface: "home"),
        .init(id: "home-phone-large-text", width: 375, scheme: .dark, type: .accessibility2, surface: "home"),
        .init(id: "home-ipad-landscape", width: 1_180, scheme: .dark, type: .large, surface: "home"),
        .init(id: "home-ipad-narrow", width: 650, scheme: .light, type: .large, surface: "home"),
        .init(id: "sources-phone-dark", width: 375, scheme: .dark, type: .large, surface: "sources"),
        .init(id: "sources-phone-large-text", width: 320, scheme: .light, type: .accessibility3, surface: "sources"),
        .init(id: "controls-dark", width: 375, scheme: .dark, type: .large, surface: "controls"),
        .init(id: "controls-light", width: 375, scheme: .light, type: .large, surface: "controls"),
        .init(id: "badges-loaded-and-missing", width: 375, scheme: .light, type: .large, surface: "badges")
    ]
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
    private var rendererIdentity: [String: String] {
        ["platform": "macCatalyst", "os": ProcessInfo.processInfo.operatingSystemVersionString,
         "sdk": Bundle.main.object(forInfoDictionaryKey: "DTSDKName") as? String ?? "unknown",
         "xcode": Bundle.main.object(forInfoDictionaryKey: "DTXcodeBuild") as? String ?? "unknown",
         "locale": Locale.current.identifier, "scale": "1", "fixtureClock": "4000000000",
         "fixtureTimeZone": "UTC", "motion": String(UIAccessibility.isReduceMotionEnabled),
         "transparency": String(UIAccessibility.isReduceTransparencyEnabled), "animations": "disabled",
         "homeCapture": FottyHostedViewSnapshot.methodID, "otherCapture": "SwiftUI.ImageRenderer.v1"]
    }

    func testApprovedComponentVisualBaselines() throws {
        #if !targetEnvironment(macCatalyst)
        throw XCTSkip("These approved component PNGs are pinned to Catalyst. Physical iPad visual/interaction acceptance is a separate gate.")
        #else
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let artwork = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { context in
            UIColor(red: 0.10, green: 0.30, blue: 0.70, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 3, y: 3, width: 58, height: 58), cornerRadius: 12).fill()
            UIColor.white.setStroke()
            let diagonal = UIBezierPath(); diagonal.move(to: CGPoint(x: 12, y: 50)); diagonal.addLine(to: CGPoint(x: 50, y: 12))
            diagonal.lineWidth = 8; diagonal.stroke()
            UIColor.systemYellow.setFill(); context.fill(CGRect(x: 15, y: 15, width: 12, height: 12))
        }
        // The fixture's name is synthetic and never mapped to a real club. Warm
        // the highest-priority URL before rendering so no task/network timing
        // chooses a placeholder instead of the loaded image.
        FottyImageCache.shared.insert(artwork, for: Self.loadedURL)
        XCTAssertNotNil(FottyImageCache.shared.image(for: Self.loadedURL))
        XCTAssertEqual(TeamBadgeWindow.fallbackInitials(for: "Visual Missing Club"), "VM")
        for event in Self.events {
            for name in [event.homeName, event.awayName] {
                XCTAssertNil(TeamBadgeWindow.countryFlagURL(for: name), "Synthetic fixture must not borrow country artwork")
                XCTAssertNil(TeamBrandService.shared.badgeURL(for: name), "Synthetic fixture must not borrow a real club's artwork")
            }
        }
        let previousTimeZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
        defer { NSTimeZone.default = previousTimeZone }

        let candidatePath = ProcessInfo.processInfo.environment["FOTTY_VISUAL_CANDIDATE_DIR"]
        if let candidatePath {
            let directory = try candidateDirectory(candidatePath)
            var records: [Record] = []
            for spec in Self.specs {
                let image = try render(spec)
                let data = try XCTUnwrap(image.pngData())
                XCTAssertLessThan(data.count, 2 * 1_024 * 1_024)
                try data.write(to: directory.appendingPathComponent("\(spec.id).png"), options: .atomic)
                let pixels = try FottyVisualPixelComparison.Pixels(image: image)
                records.append(.init(id: spec.id, file: "\(spec.id).png", sha256: Self.digest(data),
                    width: pixels.width, height: pixels.height, surface: spec.surface,
                    appearance: spec.scheme == .dark ? "dark" : "light", textSize: String(describing: spec.type)))
                attach(image, name: "candidate-\(spec.id)")
            }
            let manifest = Manifest(schema: 1, fixtureRevision: Self.fixtureRevision, renderer: rendererIdentity,
                records: records, reviewedBy: nil, reviewedAt: nil, sourceReceipt: nil)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: directory.appendingPathComponent("candidates.json"), options: .atomic)
            XCTFail("Captured \(records.count) candidates for explicit visual review at \(directory.path). A recording run is NOT acceptance; approve with tools/review-visual-baselines.mjs, then run without FOTTY_VISUAL_CANDIDATE_DIR.")
            return
        }

        let directory = root.appendingPathComponent("FottyTests/Fixtures/VisualBaselines")
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            XCTFail("No approved visual manifest. Capture and inspect candidates; never auto-record a passing baseline.")
            return
        }
        let manifestData = try Data(contentsOf: manifestURL)
        guard manifestData.count <= 32_768 else { throw FottyVisualPixelComparison.Failure.excessiveSize }
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        XCTAssertEqual(manifest.schema, 1)
        XCTAssertEqual(manifest.fixtureRevision, Self.fixtureRevision)
        XCTAssertEqual(manifest.renderer, rendererIdentity, "Renderer/OS changed: review fresh candidates; do not loosen thresholds or silently rebaseline")
        guard manifest.schema == 1, manifest.fixtureRevision == Self.fixtureRevision,
              manifest.renderer == rendererIdentity, !(manifest.reviewedBy ?? "").isEmpty,
              !(manifest.reviewedAt ?? "").isEmpty,
              manifest.sourceReceipt?.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            XCTFail("Missing approval or incompatible pinned renderer manifest")
            return
        }
        XCTAssertEqual(manifest.records.map(\.id).sorted(), Self.specs.map(\.id).sorted())
        guard Set(manifest.records.map(\.id)).count == Self.specs.count,
              manifest.records.count == Self.specs.count else { return }
        for spec in Self.specs {
            let record = try XCTUnwrap(manifest.records.first { $0.id == spec.id })
            XCTAssertEqual(record.file, "\(spec.id).png")
            XCTAssertEqual(record.surface, spec.surface)
            XCTAssertEqual(record.appearance, spec.scheme == .dark ? "dark" : "light")
            XCTAssertEqual(record.textSize, String(describing: spec.type))
            guard record.file == "\(spec.id).png" else { continue }
            let data = try Data(contentsOf: directory.appendingPathComponent(record.file))
            XCTAssertLessThan(data.count, 2 * 1_024 * 1_024)
            XCTAssertEqual(Self.digest(data), record.sha256, "Baseline bytes changed without reviewed manifest: \(spec.id)")
            let expectedImage = try XCTUnwrap(UIImage(data: data), spec.id)
            let expected = try FottyVisualPixelComparison.Pixels(image: expectedImage)
            XCTAssertEqual(expected.width, record.width); XCTAssertEqual(expected.height, record.height)
            let actualImage = try render(spec)
            let actual = try FottyVisualPixelComparison.Pixels(image: actualImage)
            let result = try FottyVisualPixelComparison.compare(actual, expected)
            if !result.matches {
                attach(expectedImage, name: "expected-\(spec.id)")
                attach(actualImage, name: "actual-\(spec.id)")
            }
            XCTAssertTrue(result.matches, "\(spec.id): \(result.description)")
        }
        #endif
    }

    private func candidateDirectory(_ path: String) throws -> URL {
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        // Foundation canonicalizes macOS /private/tmp to its /tmp alias when
        // standardizing. Validate the requested owned prefix separately, then
        // compare normalized paths to reject additional symlink traversal.
        let normalized = directory.standardizedFileURL
        let fm = FileManager.default
        let attributes = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directory.path.hasPrefix("/private/tmp/FottyVisual."),
              normalized.path.hasPrefix("/tmp/FottyVisual."),
              normalized.resolvingSymlinksInPath().path == normalized.path,
              attributes.isDirectory == true, attributes.isSymbolicLink == false,
              try fm.contentsOfDirectory(atPath: directory.path).isEmpty else {
            throw NSError(domain: "FottyVisualCandidates", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Use a fresh owned mktemp directory /private/tmp/FottyVisual.XXXXXX; never write candidates into approved baselines"])
        }
        return directory
    }

    private func render(_ spec: Spec) throws -> UIImage {
        let content = surface(spec)
            .padding(16)
            .frame(width: spec.width)
            .background(FottyTheme.background)
            .environment(\.colorScheme, spec.scheme)
            .environment(\.dynamicTypeSize, spec.type)
            .environment(\.horizontalSizeClass, spec.width > 600 ? .regular : .compact)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            // Apple's accessibility environment flags are read-only. Preserve
            // the owner's system settings and fingerprint them in the manifest;
            // a setting change requires review rather than a silent rebaseline.
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
        let image: UIImage
        if spec.surface == "home" {
            image = try FottyHostedViewSnapshot.image(content, width: spec.width, scheme: spec.scheme, type: spec.type)
        } else {
            let renderer = ImageRenderer(content: content); renderer.scale = 1
            image = try XCTUnwrap(renderer.uiImage, spec.id)
        }
        XCTAssertEqual(image.size.width, spec.width, accuracy: 0.5)
        let pixels = try FottyVisualPixelComparison.Pixels(image: image)
        XCTAssertGreaterThan(Set(pixels.rgba).count, 16, "Reject empty/background-only render: \(spec.id)")
        return image
    }

    @ViewBuilder
    private func surface(_ spec: Spec) -> some View {
        switch spec.surface {
        case "home":
            let events = Self.events
            let discovery = HomeSportsDiscovery(events: events, now: Self.now,
                status: { $0.id == "visual-live" ? .inPlay : nil })
            VStack(alignment: .leading, spacing: 16) {
                Text("Home").font(FottyTheme.typeScreenTitle).foregroundStyle(FottyTheme.textPrimary)
                SportActivityGrid(discovery: discovery, selectedSport: .constant("football"),
                    activities: Self.activities, isPad: spec.width > 600)
                Text("Live now").font(FottyTheme.typeSectionTitle).foregroundStyle(FottyTheme.textPrimary)
                if let item = discovery.items.first(where: { $0.id == "visual-live" }) {
                    HomeLiveSpotlight(item: item, presentation: .init(item: item), now: Self.now,
                        isSaved: false, onOpen: {}, onSave: {})
                }
                Text("Up Next").font(FottyTheme.typeSectionTitle).foregroundStyle(FottyTheme.textPrimary)
                if let item = discovery.items.first(where: { $0.id == "visual-future" }) {
                    HomeScheduleRow(item: item, presentation: .init(item: item), now: Self.now,
                        isSaved: false, onOpen: {}, onSave: {})
                }
            }
        case "sources":
            let session = StreamSession(matchID: "visual-source", title: "Live cricket with a long broadcast description",
                playableURL: URL(string: "https://visual-fixture.invalid/stream.m3u8")!, streamType: .hls, providerName: "CS2")
            VStack(alignment: .leading, spacing: 12) {
                Text("Sources").font(FottyTheme.typeSectionTitle).foregroundStyle(FottyTheme.textPrimary)
                SessionRow(session: session, displayNumber: 2, isActive: true, isFailed: false, action: {})
                SessionRow(session: session, displayNumber: 2, isActive: true, isFailed: true, action: {})
                SessionRow(session: session, displayNumber: 2, isActive: false, isFailed: false, action: {})
                SessionRow(session: session, displayNumber: 2, isActive: false, isFailed: false, isCoolingDown: true, action: {})
            }
        case "controls":
            VStack(alignment: .leading, spacing: 12) {
                Text("Watch feedback").font(FottyTheme.typeSectionTitle).foregroundStyle(FottyTheme.textPrimary)
                control(title: "Resting", pressed: false, enabled: true)
                control(title: "Pressed", pressed: true, enabled: true)
                control(title: "Disabled", pressed: false, enabled: false)
            }
        default:
            VStack(alignment: .leading, spacing: 16) {
                Text("Illustrative badge fixtures").font(FottyTheme.typeSectionTitle).foregroundStyle(FottyTheme.textPrimary)
                Text("Synthetic loaded artwork; honest initials when artwork is missing.")
                    .font(FottyTheme.typeBody).foregroundStyle(FottyTheme.textSecondary)
                HStack(spacing: 16) {
                    TeamBadgeWindow(teamName: "Visual Alpha Club", badgeURL: Self.loadedURL,
                        brandLookupResolved: true, size: 50)
                    TeamBadgeWindow(teamName: "Visual Missing Club", brandLookupResolved: true, size: 50)
                }
                HStack(spacing: 16) {
                    TeamBadgeWindow(teamName: "Visual Alpha Club", badgeURL: Self.loadedURL,
                        brandLookupResolved: true, size: 27, showsFrame: false)
                    TeamBadgeWindow(teamName: "Visual Missing Club", brandLookupResolved: true,
                        size: 27, showsFrame: false)
                }
            }
        }
    }

    private func control(title: String, pressed: Bool, enabled: Bool) -> some View {
        HStack {
            Text(title).font(FottyTheme.typeBody).foregroundStyle(FottyTheme.textPrimary)
            Spacer()
            Label("Watch", systemImage: "play.fill")
                .font(FottyTheme.typeMeta.weight(.semibold)).foregroundStyle(FottyTheme.textOnAccent)
                .padding(.horizontal, 12).frame(minHeight: 44)
                .background(FottyTheme.accent, in: RoundedRectangle(cornerRadius: FottyTheme.radiusSM))
                .modifier(FottyPressFeedback(isPressed: pressed)).environment(\.isEnabled, enabled)
        }
    }

    private static var events: [AnalyticalDataEngine.EventReference] {
        [event(id: "visual-live", home: "Visual Alpha Club", away: "Visual Missing Club",
             sport: "football", offset: -1_800, loaded: true),
         event(id: "visual-future", home: "Visual Women's International Representative Team",
             away: "Visual Visiting International Representative Team", sport: "cricket", offset: 17 * 3_600, loaded: false)]
    }

    private static func event(id: String, home: String, away: String, sport: String,
                              offset: TimeInterval, loaded: Bool) -> AnalyticalDataEngine.EventReference {
        .init(id: id, title: "\(home) vs \(away)", category: sport,
            date: Int64(now.addingTimeInterval(offset).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: home, badge: loaded ? loadedURL.absoluteString : nil),
                         away: .init(name: away, badge: nil)))
    }

    private static var activities: [HomeSportsDiscovery.SportActivity] {
        ["football", "cricket", "baseball", "hockey", "basketball", "american-football", "tennis", "fight"].map {
            .init(id: $0, onNow: $0 == "football" ? 1 : 0, confirmedLive: $0 == "football" ? 1 : 0,
                nextStart: nil, channels: 0, unconfirmed: $0 == "football" ? 0 : 1)
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
