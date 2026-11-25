import SwiftUI

struct SettingsCoachAccessView: View {
    @State private var code = ""
    @State private var isStored = false
    @State private var notice: String?
    @State private var error: String?
    @State private var confirmsRemoval = false
    @FocusState private var isEditing: Bool

    var body: some View {
        Form {
            Section {
                Label(isStored ? "Code stored on this device" : "No code stored", systemImage: isStored ? "key.fill" : "key")
            }
            Section("Private invitation code") {
                SecureField("64-character code", text: $code)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isEditing)
                    .accessibilityLabel("Private Coach invitation code")
                PasteButton(payloadType: String.self) { values in
                    if let value = values.first { code = String(value.prefix(128)) }
                }
                Button("Save code") {
                    do {
                        try FPLCoachAccessStore.save(code)
                        code = ""
                        isEditing = false
                        isStored = true
                        error = nil
                        notice = "Code stored securely. Service access is checked when you next ask Cloud Coach."
                    } catch { self.error = error.localizedDescription }
                }
                .disabled((try? FPLCoachAccessStore.validated(code)) == nil)
                if isStored { Button("Remove stored code", role: .destructive) { confirmsRemoval = true } }
            }
            Section {
                Text("Stored in this device's Keychain and used only for Coach requests.")
                    .font(.footnote)
                if let notice { Text(notice).accessibilityIdentifier("coach-access-status") }
                if let error { Text(error).foregroundStyle(FottyTheme.error) }
            }
        }
        .navigationTitle("Coach Access")
        .navigationBarTitleDisplayMode(.inline)
        .tint(FottyTheme.accentText)
        .scrollDismissesKeyboard(.interactively)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { isEditing = false } } }
        .onAppear {
            do { isStored = try FPLCoachAccessStore.load() != nil }
            catch { self.error = error.localizedDescription }
        }
        .onDisappear { code = "" }
        .confirmationDialog("Remove private Coach access from this device?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Remove code", role: .destructive) {
                do {
                    try FPLCoachAccessStore.remove()
                    isStored = false
                    code = ""
                    error = nil
                    notice = "Code removed. Local FPL tools remain available."
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}
