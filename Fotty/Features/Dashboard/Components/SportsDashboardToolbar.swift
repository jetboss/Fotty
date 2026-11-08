import SwiftUI

struct SportsDashboardToolbar: ToolbarContent {
    let isMultiSelectMode: Bool
    let selectedCount: Int
    let onCancel: () -> Void
    let onWatchMulti: () -> Void
    let onBeginMulti: () -> Void
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isMultiSelectMode {
                Button("Cancel", action: onCancel)
            }
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            if isMultiSelectMode {
                Button("Start", action: onWatchMulti)
                    .disabled(selectedCount != 2)
                    .fontWeight(.bold)
            } else {
                Button(action: onBeginMulti) {
                    Label("Watch two", systemImage: "rectangle.split.2x1")
                }
            }
        }
    }
}
