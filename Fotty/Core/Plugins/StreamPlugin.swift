//
//  StreamPlugin.swift
//  Fotty
//
//  Created for Stream Plugin Engine Architecture
//

import Foundation

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
        } else if id.contains("streamex") {
            providerCode = "streamex"
        } else if id.contains("vipleague") {
            providerCode = "echo"
        } else if id.contains("p2p") {
            providerCode = "p2p"
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

/// Shared provider-family matching for Settings modules and Nexus catalog rows.
enum StreamPluginProviderMatching {
    static let activePlayerProviderCodes = ["streamex", "score808"]

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

    static func activeProviderCode(forCatalogSourceCode sourceCode: String) -> String? {
        switch sourceCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "hotel":
            return "score808"
        case "admin", "delta", "echo", "golf", "india":
            return "streamex"
        default:
            return nil
        }
    }

    static func isActiveCatalogSource(_ source: NexusASource) -> Bool {
        activeProviderCode(forCatalogSourceCode: source.source) != nil
    }

    static func hasActiveCatalogSource(_ event: AnalyticalDataEngine.EventReference) -> Bool {
        event.sources?.contains(where: isActiveCatalogSource(_:)) == true
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
        let haystacks = [
            source.provider,
            source.quality,
            source.title ?? "",
            source.headers["X-Fotty-Nexus-Source"] ?? "",
            source.url.host ?? "",
            source.url.absoluteString
        ].map { $0.lowercased() }

        let aliases: [String]
        switch needle {
        case "score808", "hotel":
            aliases = ["score808", "808", "score-808", "score808live", "hotel", "cricfree"]
        case "streamex", "delta", "golf", "india", "admin":
            aliases = [
                "streamex", "streamed", "pooembed", "delta", "echo", "vipleague",
                "golf", "india", "strikeout", "admin", "embed.st"
            ]
        default:
            aliases = [needle]
        }

        return haystacks.contains { value in
            aliases.contains { alias in value.contains(alias) }
        }
    }
}
