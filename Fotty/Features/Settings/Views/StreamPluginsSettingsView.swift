import SwiftUI

enum PlaybackSourceSettingsState: Equatable {
    case loading
    case available
    case empty
    case unavailable

    static func resolved(availableSourceCount: Int, unavailableSourceCount: Int) -> Self {
        if unavailableSourceCount > 0 { return .unavailable }
        return availableSourceCount > 0 ? .available : .empty
    }
}

struct StreamPluginsSettingsView: View {
    @State private var plugins: [StreamPlugin] = []
    @State private var loadState = PlaybackSourceSettingsState.loading
    @State private var showsFeedback = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        List {
            Section(header: Text("Supported sources")) {
                if plugins.isEmpty {
                    if loadState == .loading {
                        ProgressView("Loading sources…")
                            .tint(FottyTheme.accentText)
                    } else {
                        Label(loadState == .unavailable ? "Source settings unavailable" : "No supported sources",
                              systemImage: "play.rectangle")
                            .foregroundStyle(FottyTheme.textSecondary)
                    }
                } else {
                    ForEach(plugins) { plugin in
                        pluginRow(plugin)
                            .listRowBackground(FottyTheme.surface)
                    }
                    if loadState == .loading {
                        ProgressView("Checking sources…")
                            .tint(FottyTheme.accentText)
                            .listRowBackground(FottyTheme.surface)
                    }
                }
            }

            if loadState == .unavailable || loadState == .empty {
                Section {
                    Text(unavailableDetail)
                        .font(FottyTheme.typeBody)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowBackground(FottyTheme.surface)
                    Button("Retry") { Task { await loadPlugins(reload: true) } }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("settings-sources-retry")
                    Button("Report a problem") { showsFeedback = true }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("settings-sources-report")
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(24)
        .scrollContentBackground(.hidden)
        .background(FottyTheme.background.ignoresSafeArea())
        .navigationTitle("Playback sources")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPlugins()
        }
        .sheet(isPresented: $showsFeedback) {
            FottyFeedbackSheet(area: .playback,
                               initialExpected: "Open and configure playback sources",
                               initialActual: unavailableDetail)
        }
    }

    @ViewBuilder private func pluginRow(_ plugin: StreamPlugin) -> some View {
        if dynamicTypeSize >= .xxxLarge {
            VStack(alignment: .leading, spacing: 12) {
                pluginLabel(plugin)
                HStack { Spacer(); pluginToggle(plugin).fixedSize() }
            }
            .padding(.vertical, 6)
        } else {
            HStack(spacing: 12) {
                pluginLabel(plugin)
                    .layoutPriority(1)
                Spacer()
                pluginToggle(plugin).fixedSize()
            }
            .padding(.vertical, 4)
        }
    }

    private func pluginLabel(_ plugin: StreamPlugin) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsIcon(icon: icon(for: plugin.providerCode), color: FottyTheme.accentText)

            VStack(alignment: .leading, spacing: 4) {
                Text(plugin.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(plugin.description)
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func pluginToggle(_ plugin: StreamPlugin) -> some View {
        Toggle(
            "\(plugin.name) enabled",
            isOn: Binding(
                get: { plugin.isEnabled },
                set: { enabled in togglePlugin(plugin, enabled: enabled) }
            )
        )
        .labelsHidden()
        .tint(FottyTheme.liveAccent)
        .accessibilityHint("Removes or adds this source in Watch results")
    }

    private func icon(for providerCode: String) -> String {
        switch providerCode.lowercased() {
        case "score808": return "play.tv.fill"
        case StreamPluginProviderMatching.communitySportsProviderCode: return "rectangle.stack.badge.play.fill"
        default: return "play.rectangle.fill"
        }
    }

    private var unavailableDetail: String {
        if loadState == .empty {
            return "This build has no supported playback sources to configure. Try again, or report the problem if it returns."
        }
        return plugins.isEmpty
            ? "Source settings couldn't be loaded from this build. Try again, or report the problem if it returns."
            : "Some sources couldn't be loaded from this build. The sources above can still be configured."
    }

    private func loadPlugins(reload: Bool = false) async {
        loadState = .loading
        let snapshot = await StreamPluginRegistry.shared.playbackSettingsSnapshot(reload: reload)
        guard !Task.isCancelled else { return }
        plugins = snapshot.plugins
            .filter { StreamPluginProviderMatching.activePlayerProviderCodes.contains($0.providerCode.lowercased()) }
        loadState = .resolved(availableSourceCount: plugins.count, unavailableSourceCount: snapshot.unavailableSourceCount)
    }

    private func togglePlugin(_ plugin: StreamPlugin, enabled: Bool) {
        Task {
            await StreamPluginRegistry.shared.setPluginEnabled(enabled, forId: plugin.id)
            await loadPlugins()
        }
    }
}
