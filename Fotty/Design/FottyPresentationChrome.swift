import SwiftUI

extension View {
    /// Standard iOS sheet affordances (grabber) so sheets feel system-native.
    @ViewBuilder
    func fottyStandardSheetChrome() -> some View {
        self.presentationDragIndicator(.visible)
    }

    /// Narrow leading-edge horizontal swipe dismisses full-screen live players (one gesture, like interactive pop).
    func fottyLeadingEdgeSwipeDismissesPlayer(onDismiss: @escaping () -> Void) -> some View {
        overlay(alignment: .leading) {
            LeadingEdgeSwipeToDismissStrip(onDismiss: onDismiss)
        }
    }
}

/// Hit target on the leading safe-area edge only so WebViews and horizontal video gestures are not stolen.
struct LeadingEdgeSwipeToDismissStrip: View {
    var onDismiss: () -> Void

    private let stripWidth: CGFloat = 28
    private let minimumDragDistance: CGFloat = 22
    private let translationDismissThreshold: CGFloat = 64

    var body: some View {
        Color.clear
            .frame(width: stripWidth)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .ignoresSafeArea(edges: .leading)
            .highPriorityGesture(
                DragGesture(minimumDistance: minimumDragDistance)
                    .onEnded { value in
                        guard shouldDismiss(with: value) else { return }
                        onDismiss()
                    }
            )
    }

    private func shouldDismiss(with value: DragGesture.Value) -> Bool {
        let dx = value.translation.width
        let dy = value.translation.height
        func dominantHorizontal(_ px: CGFloat, _ py: CGFloat) -> Bool {
            abs(px) >= abs(py) * 1.05
        }
        if dx > translationDismissThreshold, dominantHorizontal(dx, dy) {
            return true
        }
        if #available(iOS 17.0, *) {
            let px = value.predictedEndTranslation.width
            let py = value.predictedEndTranslation.height
            if px > 95, dominantHorizontal(px, py) {
                return true
            }
        }
        return false
    }
}
