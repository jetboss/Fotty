//
//  StreamPluginRegistry.swift
//  Fotty
//
//  Created for Stream Plugin Engine Architecture
//

import Foundation

/// Central registry for the supported built-in stream modules and their enabled state.
actor StreamPluginRegistry {
    static let shared = StreamPluginRegistry()

    private var registeredPlugins: [String: StreamPlugin] = [:]
    private var pluginStates: [String: Bool] = [:]

    private static let defaultsKey = "com.fotty.stream_plugin_states"
    private static let legacyManifestsKey = "com.fotty.stream_installed_manifests"
    private init() {
        let initialState = Self.makeInitialState()
        self.registeredPlugins = initialState.plugins
        self.pluginStates = initialState.states
    }

    /// Provider codes for enabled modules (currently StreamEx and Score808).
    func enabledProviderCodes() -> [String] {
        registeredPlugins.compactMap { id, plugin in
            let enabled = pluginStates[id] ?? plugin.isEnabled
            guard enabled else { return nil }
            return plugin.providerCode.lowercased()
        }
    }

    // MARK: - Module Management

    func setPluginEnabled(_ enabled: Bool, forId pluginId: String) {
        pluginStates[pluginId] = enabled
        saveStates()
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

    // MARK: - Persistence Helpers

    private func saveStates() {
        UserDefaults.standard.set(pluginStates, forKey: Self.defaultsKey)
    }

    private static func makeInitialState() -> (
        plugins: [String: StreamPlugin],
        states: [String: Bool]
    ) {
        var states = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Bool] ?? [:]
        var plugins: [String: StreamPlugin] = [:]

        // Older builds allowed arbitrary remote manifests, but the player only supported
        // two native provider families. Purge those misleading persisted records.
        UserDefaults.standard.removeObject(forKey: legacyManifestsKey)

        // Always load this build's bundled manifests so bundle-container URLs cannot stale.
        for name in ["streamex_manifest", "score808_manifest"] {
            guard let (manifest, url) = try? StreamPluginBundle.loadManifest(named: name) else { continue }
            plugins[manifest.id] = StreamPlugin(
                id: manifest.id,
                name: manifest.name,
                providerCode: manifest.providerCode,
                version: manifest.version,
                author: manifest.author,
                description: manifest.description,
                isBuiltIn: true,
                allowedDomains: manifest.allowedDomains,
                manifestURL: url,
                isEnabled: true
            )
            if states[manifest.id] == nil {
                states[manifest.id] = true
            }
        }

        let activeIDs = Set(plugins.keys)
        states = states.filter { activeIDs.contains($0.key) }
        UserDefaults.standard.set(states, forKey: defaultsKey)
        return (plugins, states)
    }

}
