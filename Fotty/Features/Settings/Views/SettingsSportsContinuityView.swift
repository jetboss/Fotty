import SwiftUI

struct SettingsSportsContinuityView: View {
    @State private var sync = SportsPreferenceSyncStore.shared
    private let bridge = SportsContinuityBridge.shared
    var body: some View {
        Form {
            Section {
                Toggle("Sync sports preferences", isOn: Binding(get: { sync.enabled }, set: { sync.setEnabled($0) }))
                    .accessibilityIdentifier("sports-sync-toggle")
                if sync.enabled || sync.status != .off {
                    Text(sync.status.message).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("sports-sync-status")
                        .accessibilityValue(AppRuntime.isPhysicalLiveTesting ? (sync.failureStage?.rawValue ?? "none") : "")
                }
                if let error = bridge.presentation.localError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sports-local-apply-error")
                    Button("Retry pending changes") { bridge.retryPendingChanges() }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("sports-continuity-retry")
                }
            } footer: {
                Text("Uses your Apple Account for sports interests, viewing-window choices and saved match identities only. FPL, reminders, viewing history and stream links are not included. iCloud key-value storage is not an encrypted vault.")
            }
            Section {
                Label("Continue watching", systemImage: "ipad.and.iphone")
                Text("Choose Continue on Another Device in the player's viewing options. The receiving device confirms the match and checks a fresh broadcast.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                Label("My Matchday widget", systemImage: "rectangle.3.group")
                Text("Add the sports widget from your Home Screen. Its saved-match snapshot can be delayed; opening a match checks the current schedule.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if bridge.presentation.widgetWriteFailed {
                    Label("The widget couldn’t update on this device.", systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .accessibilityIdentifier("sports-widget-write-error")
                    Button("Retry widget update") { bridge.retryPendingChanges() }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("sports-widget-retry")
                }
            }
            Section {} footer: {
                Text("Turning sync off stops transfers; it does not delete your local or iCloud copies. A different iCloud account requires a new opt-in.")
            }
        }
        .navigationTitle("Sports continuity").navigationBarTitleDisplayMode(.inline)
    }
}
