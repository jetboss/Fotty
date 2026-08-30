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
                Button("Watch 2-Up", action: onWatchMulti)
                    .disabled(selectedCount != 2)
                    .fontWeight(.bold)
            } else {
                Button(action: onBeginMulti) {
                    Label("MultiView", systemImage: "square.split.2x1")
                }
            }
        }
    }
}
