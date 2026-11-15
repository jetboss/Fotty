import SwiftUI

struct SettingsView: View {
    var onClose: (() -> Void)? = nil
    var body: some View {
        SettingsScreen(onClose: onClose)
    }
}

#Preview {
    SettingsView()
}
