//
//  StreamPlugin.swift
//  Fotty
//
//  Created for Stream Plugin Engine Architecture
//

import Foundation
import Security

/// Represents metadata and configuration state for a stream provider plugin.
struct StreamPlugin: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let name: String
    let providerCode: String
    let version: String
    let author: String
    let description: String
    let isBuiltIn: Bool
    let allowedDomains: [String]
    let manifestURL: URL?
    var isEnabled: Bool

    init(
        id: String,
        name: String,
        providerCode: String,
        version: String = "1.0.0",
        author: String = "Fotty Core",
        description: String = "",
        isBuiltIn: Bool = false,
        allowedDomains: [String] = [],
        manifestURL: URL? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.providerCode = providerCode
        self.version = version
        self.author = author
        self.description = description
        self.isBuiltIn = isBuiltIn
        self.allowedDomains = allowedDomains
        self.manifestURL = manifestURL
        self.isEnabled = isEnabled
    }
}

enum StreamPluginBundle {
    /// Manifests ship in the app bundle under `Manifests/` (folder resource).
    static func url(named filename: String) -> URL? {
        if let url = Bundle.main.url(
            forResource: filename,
            withExtension: "json",
            subdirectory: "Manifests"
        ) {
            return url
        }
        // Fallback if Xcode flattens resources in some build configs.
        return Bundle.main.url(forResource: filename, withExtension: "json")
    }

    static func loadManifest(named filename: String) throws -> (StreamPluginManifest, URL) {
        guard let url = url(named: filename) else {
            throw URLError(.fileDoesNotExist)
        }
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(StreamPluginManifest.self, from: data)
        return (manifest, url)
    }
}

/// JSON metadata for the built-in stream modules shipped with this app.
struct StreamPluginManifest: Codable, Sendable {
    let id: String
    let name: String
    let providerCode: String
    let version: String
    let author: String
    let description: String
    let allowedDomains: [String]
    let iconName: String?

    init(
        id: String,
        name: String,
        providerCode: String,
        version: String,
        author: String,
        description: String,
        allowedDomains: [String],
        iconName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.providerCode = providerCode
        self.version = version
        self.author = author
        self.description = description
        self.allowedDomains = allowedDomains
        self.iconName = iconName
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, providerCode, version, author, description
        case allowedDomains, iconName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? "Community"
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        allowedDomains = try container.decodeIfPresent([String].self, forKey: .allowedDomains) ?? []
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName)

        if let code = try container.decodeIfPresent(String.self, forKey: .providerCode), !code.isEmpty {
            providerCode = code
        } else if id.contains("score808") {
            providerCode = "score808"
        } else if id.contains("vipleague") {
            providerCode = "echo"
        } else {
            providerCode = id
        }

    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(providerCode, forKey: .providerCode)
        try container.encode(version, forKey: .version)
        try container.encode(author, forKey: .author)
        try container.encode(description, forKey: .description)
        try container.encode(allowedDomains, forKey: .allowedDomains)
        try container.encodeIfPresent(iconName, forKey: .iconName)
    }
}

/// The finite, reviewed source inventory. This is registration and dispatch
/// metadata, not an add-on installer or permission to accept a delivery. Each
/// adapter still owns its exact fixture schema, transport and admission checks.
enum CuratedStreamSourceCatalog {
    enum Provider: String, CaseIterable, Sendable {
        case score808 = "score808"
        case communitySports = "communitysports"
        case plavioSports = "plaviosports"
        case cncSports = "cncsports"
        case flixStreams = "flixstreams"
        case reviewedTV = "reviewedtv"
        case highfly = "highfly"
    }

    /// Typed routing identity; it never carries an arbitrary URL or closure
    /// capable of bypassing the reviewed adapter's authority.
    enum Dispatch: CaseIterable, Equatable, Sendable {
        case score808, communitySports, plavioSports, cncSports, flixStreams, reviewedTV, highfly
    }

    struct Definition: Sendable, Equatable, Identifiable {
        let provider: Provider
        let manifestFilename: String
        let manifestID: String
        let defaultEnabled: Bool
        let opaqueLabelPrefix: String?

        var id: String { provider.rawValue }
        var providerCode: String { provider.rawValue }
        var discoveryName: String { opaqueLabelPrefix ?? providerCode }
        var dispatch: Dispatch {
            switch provider {
            case .score808: return .score808
            case .communitySports: return .communitySports
            case .plavioSports: return .plavioSports
            case .cncSports: return .cncSports
            case .flixStreams: return .flixStreams
            case .reviewedTV: return .reviewedTV
            case .highfly: return .highfly
            }
        }
        var isOptional: Bool { opaqueLabelPrefix != nil }

        /// These are the existing lane gates, not fixture or playback proof.
        /// CS keeps its reviewed Live fallback; other adapters keep their own
        /// existing category boundaries rather than a second copied sport list.
        func supportsDiscovery(category: String) -> Bool {
            switch dispatch {
            case .score808, .reviewedTV: return false
            case .communitySports: return true
            case .plavioSports: return PlavioSportsAddonClient.supports(category: category)
            case .cncSports: return CNCSportsAddonClient.supports(category: category)
            case .flixStreams: return FlixStreamsAddonClient.supports(category: category)
            case .highfly: return HighflySportsAddonClient.supports(category: category)
            }
        }

        @MainActor func supportsOptionalFixture(event: EventReference) -> Bool {
            if dispatch == .reviewedTV {
                return ReviewedTVPlaylistClient.programmeLookupRequest(for: StreamPlaybackRequest(event: event)) != nil
            }
            if dispatch == .cncSports && ReviewedSportsFixtureMatcher.sportKey(event.normalizedCategory) == "cricket" {
                return CNCSportsAddonClient.supportsReviewedCricket(StreamPlaybackRequest(event: event))
            }
            if dispatch == .flixStreams { return FlixStreamsAddonClient.supports(event: event) }
            return isOptional && supportsDiscovery(category: event.normalizedCategory)
        }

        func matchesOpaqueLabel(_ raw: String) -> Bool {
            guard let prefix = opaqueLabelPrefix else { return false }
            let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if provider == .reviewedTV {
                return ReviewedTVPlaylistClient.channel(forProviderName: label) != nil
            }
            guard label.hasPrefix(prefix) else { return false }
            let suffix = String(label.dropFirst(prefix.count))
            return suffix.count == 1 && ["1", "2", "3", "4", "5", "6"].contains(suffix)
        }

        func sourceLabel(choice: Int) -> String? {
            if provider == .reviewedTV {
                return ReviewedTVPlaylistClient.channels.first { $0.providerName == "TV" + String(choice) }?.providerName
            }
            guard let prefix = opaqueLabelPrefix, (1...6).contains(choice) else { return nil }
            return prefix + String(choice)
        }

        /// Historical CS-labelled sources also use the existing CS-digit
        /// alias path. Keep it unchanged; only CS1–CS6 is an opaque family.
        func matchesLegacyLabel(_ raw: String) -> Bool {
            guard provider == .communitySports, let prefix = opaqueLabelPrefix else { return false }
            let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return label.range(of: "^" + NSRegularExpression.escapedPattern(for: prefix) + #"\d+$"#,
                               options: .regularExpression) != nil
        }

        func accepts(manifest: StreamPluginManifest) -> Bool {
            manifest.id == manifestID && manifest.providerCode == providerCode
        }
    }

    // Keep the established order, IDs, labels and default choices. Remote
    // manifests cannot append definitions or change any of these identities.
    static let all: [Definition] = [
        .init(provider: .score808, manifestFilename: "score808_manifest", manifestID: "score808-extension",
              defaultEnabled: true, opaqueLabelPrefix: nil),
        .init(provider: .communitySports, manifestFilename: "community_sports_manifest", manifestID: "community-sports-extension",
              defaultEnabled: false, opaqueLabelPrefix: "CS"),
        .init(provider: .plavioSports, manifestFilename: "additional_sports_manifest", manifestID: "additional-sports-extension",
              defaultEnabled: false, opaqueLabelPrefix: "AS"),
        .init(provider: .cncSports, manifestFilename: "cnc_sports_manifest", manifestID: "cnc-sports-extension",
              defaultEnabled: false, opaqueLabelPrefix: "LS"),
        .init(provider: .flixStreams, manifestFilename: "flix_streams_manifest", manifestID: "flix-streams-extension",
              defaultEnabled: false, opaqueLabelPrefix: "FS"),
        .init(provider: .reviewedTV, manifestFilename: "reviewed_tv_manifest", manifestID: "reviewed-tv-extension",
              defaultEnabled: false, opaqueLabelPrefix: "TV"),
        .init(provider: .highfly, manifestFilename: "highfly_manifest", manifestID: "highfly-extension",
              defaultEnabled: false, opaqueLabelPrefix: "HF")
    ]

    static var optionalSources: [Definition] { all.filter(\.isOptional) }

    struct DiscoveryPlan: Sendable, Equatable {
        let score808SiteEligible: Bool
        let optionalSources: [Definition]
    }

    /// Build lanes from enabled reviewed capabilities and the exact request.
    /// A master catalog's source array is deliberately not an input: its loss
    /// must not prevent another adapter from checking the requested fixture.
    @MainActor static func discoveryPlan(
        for request: StreamPlaybackRequest,
        enabledProviderCodes: Set<String>,
        allowDeferredTVLookup: Bool = false,
        at now: Date = Date()
    ) -> DiscoveryPlan {
        guard !request.matchID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.preferredEvent?.hasCatalogIdentityConflict != true else {
            return .init(score808SiteEligible: false, optionalSources: [])
        }
        let enabled = Set(enabledProviderCodes.compactMap { definition(forProviderCode: $0)?.providerCode })
        let hasExactFixture = ReviewedSportsFixtureMatcher.requestIdentity(for: request) != nil
        let television = SportsTVStation.identifying(request)
        let isReviewedChannel = CricketBroadcastChannel.identifying(request: request) != nil || television != nil
        let optional = optionalSources.filter { definition in
            guard enabled.contains(definition.providerCode) else { return false }
            if television != nil {
                return definition.provider == .reviewedTV && ReviewedTVPlaylistClient.supports(request)
                    || definition.provider == .communitySports && CommunitySportsAddonClient.supportsSportsTVChannel(request)
            }
            if isReviewedChannel {
                return definition.provider == .communitySports
                    || definition.provider == .reviewedTV && ReviewedTVPlaylistClient.supports(request)
            }
            if definition.provider == .reviewedTV {
                return hasExactFixture && (ReviewedTVPlaylistClient.programmeLookupRequest(for: request, at: now) != nil
                    || allowDeferredTVLookup && supportsDeferredTVFixture(request))
            }
            guard definition.supportsDiscovery(category: request.category) else { return false }
            guard hasExactFixture else { return false }
            if definition.provider == .cncSports && ReviewedSportsFixtureMatcher.sportKey(request.category) == "cricket" {
                return CNCSportsAddonClient.supportsReviewedCricket(request)
            }
            if definition.provider == .flixStreams, let event = request.preferredEvent {
                return definition.supportsOptionalFixture(event: event)
            }
            return true
        }
        return .init(
            score808SiteEligible: enabled.contains(Provider.score808.rawValue)
                && Score808LateDiscoveryPolicy.isLookupWindow(
                    kickoffDate: request.kickoffDate ?? request.preferredEvent?.kickoffDate,
                    category: request.category, at: now),
            optionalSources: optional)
    }

    /// Capability to check the registry, not a station/programme assignment.
    /// The foreground lane still needs a fresh exact association before it can
    /// read a playlist. Aggregate and preflight callers retain the cached gate.
    private static func supportsDeferredTVFixture(_ request: StreamPlaybackRequest) -> Bool {
        guard request.registryMatch == nil, let event = request.preferredEvent, request.matchID == event.id,
              !event.hasCatalogIdentityConflict, !event.isBroadcastChannel else { return false }
        if let cricket = event.cricketFixture {
            return request.category == "cricket" && CricketFixtureCatalog.fixtureIDPrefix + cricket.fixtureID == event.id && cricket.verified
                && !cricket.status.stopsPlayback && [.test, .odi, .t20].contains(cricket.format)
        }
        guard let sports = event.sportsFixture, sports.fixtureID == event.id, sports.verified,
              sports.eventKind == .match, sports.sport == request.category, !sports.status.stopsPlayback else { return false }
        return sports.sport == "football" || sports.sport == "baseball" && sports.competitionID == "mlb"
            || sports.sport == "hockey" && sports.competitionID == "nhl"
    }

    static func definition(forProviderCode code: String) -> Definition? {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return all.first { $0.providerCode == normalized }
    }

    static func opaqueDefinition(for label: String) -> Definition? {
        all.first { $0.matchesOpaqueLabel(label) }
    }

    @MainActor static func hasOptionalFixtureSupport(event: EventReference, enabledProviderCodes: Set<String>) -> Bool {
        let enabled = Set(enabledProviderCodes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return optionalSources.contains { enabled.contains($0.providerCode) && $0.supportsOptionalFixture(event: event) }
    }
}

/// Shared provider-family matching for Settings modules and Nexus catalog rows.
enum StreamPluginProviderMatching {
    static let communitySportsProviderCode = CuratedStreamSourceCatalog.Provider.communitySports.rawValue
    static let plavioSportsProviderCode = CuratedStreamSourceCatalog.Provider.plavioSports.rawValue
    static let cncSportsProviderCode = CuratedStreamSourceCatalog.Provider.cncSports.rawValue
    static let flixStreamsProviderCode = CuratedStreamSourceCatalog.Provider.flixStreams.rawValue
    static let activePlayerProviderCodes = CuratedStreamSourceCatalog.all.map(\.providerCode)
    /// Provider catalog data is remote and therefore untrusted. Keep every
    /// shared embed inside the reviewed HTTPS origins that Fotty supports.
    static let approvedSharedPlaybackDomains = [
        "embedhd.st", "exposestrat.com", "embedsports.top",
        "pooembed.eu", "score808live.tv", "strmd.st"
    ]

    static func allowedPlayerProviderCodes(enabledCodes: [String]) -> [String] {
        let enabled = Set(enabledCodes.map { $0.lowercased() })
        return activePlayerProviderCodes.filter(enabled.contains)
    }

    static func isActivePlayerSource(_ source: StreamSource) -> Bool {
        if isP2PLike(source) { return false }
        return activePlayerProviderCodes.contains { matches(source, code: $0) }
    }

    static func isActivePlayerSession(_ session: StreamSession) -> Bool {
        isActivePlayerSource(session.legacySource)
    }

    static func isApprovedSharedPlaybackHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        return approvedSharedPlaybackDomains.contains { domain in
            normalized == domain || normalized.hasSuffix(".\(domain)")
        }
    }

    static func isP2PLike(_ source: StreamSource) -> Bool {
        let absolute = source.url.absoluteString.lowercased()
        let provider = source.provider.lowercased()
        let quality = source.quality.lowercased()
        return absolute.contains(":6878")
            || absolute.contains("/proxy/acestream/")
            || absolute.contains("acestream://")
            || provider.contains("p2p network")
            || provider.contains("acestream")
            || quality.contains("p2p")
    }

    static func matches(_ source: StreamSource, code: String) -> Bool {
        let needle = code.lowercased()
        // Reviewed add-on labels own their family. A remote title/query that
        // happens to contain "golf" or "streamed" cannot re-enable an AS/CS
        // delivery through another module's broad legacy aliases.
        if let family = opaqueProviderFamily(source.provider) { return needle == family }
        if let definition = CuratedStreamSourceCatalog.definition(forProviderCode: needle),
           definition.isOptional, definition.provider != .communitySports {
            // Optional curated families have only their owned labels, never
            // aliases supplied by a remote title, URL or required header.
            return false
        }
        let haystacks = [
            source.provider,
            source.quality,
            source.title ?? "",
            source.url.host ?? "",
            source.url.absoluteString
        ].map { $0.lowercased() }

        let aliases: [String]
        switch needle {
        case "score808":
            aliases = ["score808", "808", "score-808", "score808live", "cricfree"]
        case communitySportsProviderCode:
            if CuratedStreamSourceCatalog.definition(forProviderCode: needle)?.matchesLegacyLabel(source.provider) == true {
                return true
            }
            aliases = [communitySportsProviderCode, "community sports"]
        default:
            aliases = [needle]
        }

        return haystacks.contains { value in
            aliases.contains { alias in value.contains(alias) }
        }
    }

    static func opaqueProviderFamily(_ provider: String) -> String? {
        CuratedStreamSourceCatalog.opaqueDefinition(for: provider)?.providerCode
    }
}

// Account configuration is deliberately separate from the playback inventory.
// A saved manifest is not an admitted adapter, source, fixture or media URL.
enum AccountSourceSetup: String, CaseIterable, Identifiable, Sendable {
    case penguPlay, highfly, streamNexus
    var id: String { rawValue }
    var playbackProviderCode: String? { self == .highfly ? "highfly" : nil }
    var name: String {
        switch self { case .penguPlay: return "PenguPlay"; case .highfly: return "Highfly"; case .streamNexus: return "StreamNexus" }
    }
    var setupURL: URL {
        switch self {
        case .penguPlay: return URL(string: "https://pengu.uk/")!
        case .highfly: return URL(string: "https://sports.highfly.to/configure")!
        case .streamNexus: return URL(string: "https://config.streamnexus.cc.cd/")!
        }
    }
    var instructions: String {
        switch self {
        case .penguPlay: return "Sign in with PenguPlay, enable Live TV and your sports, then copy its configured add-on link."
        case .highfly: return "Use your Highfly access code or configured manifest link. For free access, complete verification and copy the Install link. Premium profiles can use their own configured links."
        case .streamNexus: return "Sign in on StreamNexus’s configuration page with your own access token, then copy its manifest link."
        }
    }
    var manifestHosts: Set<String> {
        switch self {
        case .penguPlay: return ["pengu.uk"]
        case .highfly:
            return Set(["to", "dev"].flatMap { tld in
                ["sports", "premium", "premium-us2", "premium-eu1"].map { "\($0).highfly.\(tld)" }
            })
        case .streamNexus: return ["sports.streamnexus.cc.cd"]
        }
    }
    func validatedLink(_ input: String) throws -> URL {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if self == .highfly, value.range(of: #"^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}\.[a-fA-F0-9]{16}$"#, options: .regularExpression) != nil {
            value = "https://sports.highfly.to/" + value + "/manifest.json"
        }
        if self == .highfly, value.range(of: #"^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$"#, options: .regularExpression) != nil {
            value = "https://premium.highfly.to/" + value + "/manifest.json"
        }
        guard !value.isEmpty, value.utf8.count <= 8192,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              var parts = URLComponents(string: value) else { throw AccountSourceSetupError.invalidLink }
        if parts.scheme?.lowercased() == "stremio" { parts.scheme = "https" }
        guard parts.scheme?.lowercased() == "https", let host = parts.host?.lowercased(), manifestHosts.contains(host),
              parts.port == nil || parts.port == 443, parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.path.hasSuffix("/manifest.json"), !parts.path.contains("\\"),
              !parts.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
              let url = parts.url else { throw AccountSourceSetupError.invalidLink }
        return url
    }
}

enum AccountSourceSetupError: Error, LocalizedError {
    case invalidLink, storageUnavailable, accessUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidLink: return "Paste this provider’s complete configured manifest link. Its address must use a supported secure host and end in /manifest.json before any query."
        case .storageUnavailable: return "The setup link couldn’t be saved securely. Your previous link has not been replaced. Try again after unlocking this device."
        case .accessUnavailable: return "This source couldn’t be verified. Check your setup link and connection, then try again. Your previous setup is unchanged."
        }
    }
}

/// One explicit Add operation: verify access, commit private configuration, then
/// enable its admitted adapter. Failures/cancellation before commit preserve the
/// old account and opt-in. Unimplemented sources remain clearly review-only.
@MainActor
final class AccountSourceConnector {
    private let store: AccountSourceSetupStore
    private let verify: (AccountSourceSetup, URL) async throws -> Void
    private let setEnabled: (String, Bool) async -> Void
    init(store: AccountSourceSetupStore,
         verify: @escaping (AccountSourceSetup, URL) async throws -> Void = { provider, url in
             if provider == .highfly { try await HighflySportsAddonClient.validateConfiguration(url) }
         },
         setEnabled: @escaping (String, Bool) async -> Void = { code, enabled in
             guard let definition = CuratedStreamSourceCatalog.definition(forProviderCode: code) else { return }
             await StreamPluginRegistry.shared.setPluginEnabled(enabled, forId: definition.manifestID)
         }) {
        self.store = store; self.verify = verify; self.setEnabled = setEnabled
    }
    func add(_ input: String, for provider: AccountSourceSetup) async throws -> Bool {
        let url = try provider.validatedLink(input)
        if provider.playbackProviderCode != nil { try await verify(provider, url) }
        try Task.checkCancellation()
        try store.save(url.absoluteString, for: provider)
        if let code = provider.playbackProviderCode { await setEnabled(code, true); return true }
        return false
    }
    func remove(_ provider: AccountSourceSetup) async throws {
        try store.remove(provider)
        if let code = provider.playbackProviderCode { await setEnabled(code, false) }
    }
}

/// No UserDefaults, iCloud, shared app group, analytics or diagnostic export.
/// Injectable storage keeps unit tests away from the real Keychain.
@MainActor
final class AccountSourceSetupStore {
    typealias Reader = (AccountSourceSetup) throws -> Data?
    typealias Writer = (AccountSourceSetup, Data?) throws -> Void
    private let read: Reader
    private let write: Writer
    init(read: @escaping Reader, write: @escaping Writer) { self.read = read; self.write = write }
    convenience init() {
        self.init(read: { provider in
            var query = Self.keychainQuery(provider)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = result as? Data else { throw AccountSourceSetupError.storageUnavailable }
            return data
        }, write: { provider, value in
            let query = Self.keychainQuery(provider)
            if let value {
                let changes: [String: Any] = [kSecValueData as String: value]
                let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
                if status == errSecItemNotFound {
                    var item = query
                    item[kSecValueData as String] = value
                    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                    guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AccountSourceSetupError.storageUnavailable }
                } else if status != errSecSuccess { throw AccountSourceSetupError.storageUnavailable }
            } else {
                let status = SecItemDelete(query as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else { throw AccountSourceSetupError.storageUnavailable }
            }
        })
    }
    private static func keychainQuery(_ provider: AccountSourceSetup) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.fotty.account-source-setup",
         kSecAttrAccount as String: provider.rawValue,
         kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true]
    }
    func hasSavedLink(for provider: AccountSourceSetup) throws -> Bool { try savedLink(for: provider) != nil }
    func savedLink(for provider: AccountSourceSetup) throws -> URL? {
        guard let data = try read(provider) else { return nil }
        guard let value = String(data: data, encoding: .utf8) else { throw AccountSourceSetupError.storageUnavailable }
        return try provider.validatedLink(value)
    }
    func save(_ value: String, for provider: AccountSourceSetup) throws {
        let url = try provider.validatedLink(value)
        try write(provider, Data(url.absoluteString.utf8))
    }
    func remove(_ provider: AccountSourceSetup) throws { try write(provider, nil) }
}
