import SwiftUI

struct SettingsView: View {
    var onOpenFPL: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil
    var body: some View {
        SettingsScreen(onOpenFPL: onOpenFPL, onClose: onClose)
    }
}

#Preview {
    SettingsView()
}
