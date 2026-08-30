import SwiftUI

struct SettingsView: View {
    var onOpenFPL: (() -> Void)? = nil
    var body: some View {
        SettingsScreen(onOpenFPL: onOpenFPL)
    }
}

#Preview {
    SettingsView()
}
