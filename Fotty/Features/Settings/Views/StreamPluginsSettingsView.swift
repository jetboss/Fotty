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

            Section {
                // Only account sources that can play in Watch are offered.
                ForEach(AccountSourceSetup.allCases.filter { $0.playbackProviderCode != nil }) { source in
                    NavigationLink {
                        AccountSourceSetupView(source: source, didChange: { await loadPlugins() })
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.name).foregroundStyle(FottyTheme.textPrimary)
                            Text("Set up your account")
                                .font(FottyTheme.typeMeta)
                                .foregroundStyle(FottyTheme.textSecondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(FottyTheme.surface)
                }
            } header: {
                Text("Sources requiring setup")
            } footer: {
                Text("Add your account to enable a supported source in Watch.")
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


private struct AccountSourceSetupView: View {
    let source: AccountSourceSetup
    let didChange: () async -> Void
    @State private var draft = ""
    @State private var saved = false
    @State private var status: String?
    @State private var confirmsRemoval = false
    @State private var saving = false
    @State private var enabled = false
    @State private var operation: Task<Void, Never>?
    private let store = AccountSourceSetupStore()

    var body: some View {
        Form {
            Section {
                Text(source.instructions).fixedSize(horizontal: false, vertical: true)
                Link("Open \(source.name) setup", destination: source.setupURL)
                    .frame(minHeight: 44)
            }
            Section {
                SecureField(source == .highfly ? "Manifest link or Highfly access code" : "Configured manifest link", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .privacySensitive()
                    .accessibilityIdentifier("source-setup-link")
                Button { save() } label: {
                    HStack {
                        if saving { ProgressView() }
                        Text(saving ? "Checking source…" : source.playbackProviderCode != nil
                             ? (saved ? "Update and enable" : "Add source") : "Save for review")
                    }
                }
                    .disabled(saving || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .frame(minHeight: 44)
                if let status {
                    Text(status).font(.footnote).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("source-setup-status")
                }
            } header: {
                Text("Private setup link")
            } footer: {
                Text(source.playbackProviderCode != nil ? "Your account is checked, saved securely on this device and enabled in Watch. Availability still depends on the match. You can turn this source off in Playback sources." : "Stored securely on this device only. This source is awaiting compatibility review and cannot be used in Watch yet.")
            }
            if saved {
                Section {
                    Label(source.playbackProviderCode != nil ? (enabled ? "Added · enabled" : "Added · turned off") : "Link saved · awaiting review", systemImage: "checkmark.circle")
                    Button("Remove source", role: .destructive) { confirmsRemoval = true }.disabled(saving)
                }
            }
        }
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .onDisappear { operation?.cancel(); draft = "" }
        .confirmationDialog("Remove this saved setup link?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Remove link", role: .destructive) {
                operation = Task {
                    do { try await AccountSourceConnector(store: store).remove(source); saved = false; enabled = false; draft = ""; status = nil; await didChange() }
                    catch { status = "The link couldn’t be removed. Try again after unlocking this device." }
                }
            }
        }
    }
    private func refresh() async {
        do { saved = try store.hasSavedLink(for: source) }
        catch { status = "Secure storage is unavailable. Try again after unlocking this device." }
        if let code = source.playbackProviderCode { enabled = await StreamPluginRegistry.shared.enabledProviderCodes().contains(code) }
    }
    private func save() {
        guard !saving else { return }
        let input = draft
        saving = true; status = nil
        operation = Task {
            defer { saving = false }
            do {
                enabled = try await AccountSourceConnector(store: store).add(input, for: source)
                draft = ""; saved = true
                status = enabled ? "Added and enabled. This source will be checked when you tap Watch." : "Saved for review. This source cannot be used in Watch yet."
                await didChange()
            } catch is CancellationError { }
            catch let error as AccountSourceSetupError { status = error.errorDescription }
            catch { status = "The source couldn’t be added. Your previous setup is unchanged. Try again." }
        }
    }
}
