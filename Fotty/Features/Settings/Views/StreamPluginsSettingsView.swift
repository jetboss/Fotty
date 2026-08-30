import SwiftUI

struct StreamPluginsSettingsView: View {
    @State private var plugins: [StreamPlugin] = []
    @State private var statusMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Playback sources")
                        .font(FottyTheme.typeBody)
                        .foregroundStyle(FottyTheme.textPrimary)
                    Text("Fotty currently supports the two built-in web player sources below. Turning one off removes it from Watch Now results.")
                        .font(FottyTheme.typeMeta)
                        .foregroundStyle(FottyTheme.textSecondary)
                }
                .padding(.vertical, 4)
                .listRowBackground(FottyTheme.surface)
            }

            Section(header: Text("Available")) {
                if plugins.isEmpty {
                    ProgressView("Loading sources…")
                        .tint(FottyTheme.accentText)
                        .listRowBackground(FottyTheme.surface)
                } else {
                    ForEach(plugins) { plugin in
                        pluginRow(plugin)
                            .listRowBackground(FottyTheme.surface)
                    }
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(FottyTheme.typeMeta)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .listRowBackground(FottyTheme.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(FottyTheme.background.ignoresSafeArea())
        .navigationTitle("Playback sources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await loadPlugins()
        }
    }

    private func pluginRow(_ plugin: StreamPlugin) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: plugin.providerCode))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(FottyTheme.accentText)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(plugin.name)
                    .font(FottyTheme.typeBody.weight(.semibold))
                    .foregroundStyle(FottyTheme.textPrimary)
                Text(plugin.description)
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .lineLimit(2)
                Text("Built in • v\(plugin.version)")
                    .font(FottyTheme.typeCaption)
                    .foregroundStyle(FottyTheme.textTertiary)
            }

            Spacer()

            Toggle(
                "\(plugin.name) enabled",
                isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { enabled in togglePlugin(plugin, enabled: enabled) }
                )
            )
            .labelsHidden()
            .tint(FottyTheme.liveAccent)
        }
        .padding(.vertical, 4)
    }

    private func icon(for providerCode: String) -> String {
        providerCode.lowercased() == "score808" ? "play.tv.fill" : "play.rectangle.fill"
    }

    private func loadPlugins() async {
        let supported = await StreamPluginRegistry.shared.allPlugins()
            .filter { StreamPluginProviderMatching.activePlayerProviderCodes.contains($0.providerCode.lowercased()) }
        plugins = supported
    }

    private func togglePlugin(_ plugin: StreamPlugin, enabled: Bool) {
        Task {
            await StreamPluginRegistry.shared.setPluginEnabled(enabled, forId: plugin.id)
            await loadPlugins()
            statusMessage = enabled ? "\(plugin.name) enabled." : "\(plugin.name) disabled."
        }
    }
}
