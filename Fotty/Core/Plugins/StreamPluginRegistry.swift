//
//  StreamPluginRegistry.swift
//  Fotty
//
//  Created for Stream Plugin Engine Architecture
//

import Foundation

struct StreamPluginCatalogSnapshot: Sendable {
    let plugins: [StreamPlugin]
    let unavailableSourceCount: Int
}

/// Central registry for the supported built-in stream modules and their enabled state.
actor StreamPluginRegistry {
    static let shared = StreamPluginRegistry()

    private var registeredPlugins: [String: StreamPlugin] = [:]
    private var pluginStates: [String: Bool] = [:]
    private var unavailableSourceCount = 0
    private var enablementRevision: UInt64 = 0

    private static let defaultsKey = "com.fotty.stream_plugin_states"
    private static let legacyManifestsKey = "com.fotty.stream_installed_manifests"
    private init() {
        let initialState = Self.makeInitialState()
        self.registeredPlugins = initialState.plugins
        self.pluginStates = initialState.states
        self.unavailableSourceCount = initialState.unavailableSourceCount
    }

    /// Provider codes for enabled playback modules.
    func enabledProviderCodes() -> [String] {
        registeredPlugins.compactMap { id, plugin in
            let enabled = pluginStates[id] ?? plugin.isEnabled
            guard enabled else { return nil }
            return plugin.providerCode.lowercased()
        }
    }

    // MARK: - Module Management

    func setPluginEnabled(_ enabled: Bool, forId pluginId: String) async {
        pluginStates[pluginId] = enabled
        saveStates()
        enablementRevision &+= 1
        await refreshDiscoveryAvailability(invalidating: registeredPlugins[pluginId]?.providerCode)
    }

    /// One host-level refresh, plus explicit source changes. This reads only
    /// bundled/local state; rows never start registry or provider requests.
    func refreshDiscoveryAvailability(invalidating providerCode: String? = nil) async {
        let codes = Set(enabledProviderCodes()), revision = enablementRevision
        await MainActor.run {
            FixtureStreamDiscoveryIndex.shared.updateEnabledProviders(codes, revision: revision,
                                                                      invalidating: providerCode)
            FixtureCatalogAvailabilityIndex.shared.updateEnabledProviders(codes, revision: revision,
                                                                          invalidating: providerCode)
        }
    }

    func isPluginEnabled(id: String) -> Bool {
        return pluginStates[id] ?? registeredPlugins[id]?.isEnabled ?? false
    }

    func allPlugins() -> [StreamPlugin] {
        return registeredPlugins.values.map { plugin in
            var module = plugin
            module.isEnabled = pluginStates[module.id] ?? module.isEnabled
            return module
        }.sorted { $0.name < $1.name }
    }

    /// Retry only the bundled catalog. It does not fetch providers, enable a
    /// source, or change the owner's stored choices.
    func playbackSettingsSnapshot(reload: Bool = false) async -> StreamPluginCatalogSnapshot {
        if reload {
            let catalog = Self.bundledCatalog(savedStates: pluginStates)
            registeredPlugins = Dictionary(uniqueKeysWithValues: catalog.plugins.map { ($0.id, $0) })
            unavailableSourceCount = catalog.unavailableSourceCount
            enablementRevision &+= 1
            await refreshDiscoveryAvailability()
        }
        return .init(plugins: allPlugins(), unavailableSourceCount: unavailableSourceCount)
    }

    // MARK: - Persistence Helpers

    private func saveStates() {
        UserDefaults.standard.set(pluginStates, forKey: Self.defaultsKey)
    }

    private static func makeInitialState() -> (
        plugins: [String: StreamPlugin],
        states: [String: Bool],
        unavailableSourceCount: Int
    ) {
        var states = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Bool] ?? [:]

        // Older builds allowed arbitrary remote manifests, but the player only supported
        // two native provider families. Purge those misleading persisted records.
        UserDefaults.standard.removeObject(forKey: legacyManifestsKey)

        let catalog = bundledCatalog(savedStates: states)
        let plugins = Dictionary(uniqueKeysWithValues: catalog.plugins.map { ($0.id, $0) })
        for plugin in catalog.plugins where states[plugin.id] == nil {
            states[plugin.id] = plugin.isEnabled
        }

        // Retired manifests stay excluded. A temporarily unreadable bundled
        // source must not erase its saved enabled/disabled choice before Retry.
        let bundledIDs = Set(CuratedStreamSourceCatalog.all.map(\.manifestID))
        states = states.filter { bundledIDs.contains($0.key) }
        UserDefaults.standard.set(states, forKey: defaultsKey)
        return (plugins, states, catalog.unavailableSourceCount)
    }

    nonisolated static func bundledCatalog(
        savedStates: [String: Bool],
        loadManifest: (String) throws -> (StreamPluginManifest, URL) = StreamPluginBundle.loadManifest(named:)
    ) -> StreamPluginCatalogSnapshot {
        var plugins: [StreamPlugin] = []
        var unavailable = 0
        // Always read bundled manifests so a restored catalog never retains an
        // obsolete bundle-container URL. Failure exposes only a bounded count.
        for definition in CuratedStreamSourceCatalog.all {
            guard let (manifest, url) = try? loadManifest(definition.manifestFilename), definition.accepts(manifest: manifest) else {
                unavailable += 1
                continue
            }
            plugins.append(StreamPlugin(
                id: manifest.id,
                name: manifest.name,
                providerCode: manifest.providerCode,
                version: manifest.version,
                author: manifest.author,
                description: manifest.description,
                isBuiltIn: true,
                allowedDomains: manifest.allowedDomains,
                manifestURL: url,
                isEnabled: savedStates[manifest.id] ?? definition.defaultEnabled
            ))
        }
        return .init(plugins: plugins.sorted { $0.name < $1.name }, unavailableSourceCount: unavailable)
    }

    nonisolated static func isEnabledByDefault(providerCode: String) -> Bool {
        // Preserve this helper's existing unknown-code fallback. Unknown or
        // mismatched manifests cannot register through bundledCatalog above.
        CuratedStreamSourceCatalog.definition(forProviderCode: providerCode)?.defaultEnabled ?? true
    }

}
