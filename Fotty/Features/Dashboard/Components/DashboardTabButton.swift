import SwiftUI

struct DashboardTabButton<Icon: View>: View {
    let text: String
    let isSelected: Bool
    let icon: () -> Icon
    let action: () -> Void
    
    init(text: String, isSelected: Bool, @ViewBuilder icon: @escaping () -> Icon, action: @escaping () -> Void) {
        self.text = text
        self.isSelected = isSelected
        self.icon = icon
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon()
                
                Text(text)
                    .font(.fottyScaled(size: 13, weight: .bold))
            }
            .foregroundStyle(isSelected ? FottyTheme.textOnAccent : FottyTheme.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? AnyShapeStyle(FottyTheme.accentGradient) : AnyShapeStyle(FottyTheme.surface))
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isSelected ? .white.opacity(0.3) : FottyTheme.border,
                                lineWidth: 0.5
                            )
                    )
            )
            .shadow(color: isSelected ? FottyTheme.accent.opacity(0.4) : .clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}
