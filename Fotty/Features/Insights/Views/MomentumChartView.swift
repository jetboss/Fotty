import SwiftUI

struct MomentumChartView: View {
    let momentum: [Double]
    
    init(momentum: [Double] = []) {
        self.momentum = momentum
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(FottyTheme.accentText)
                Text("MATCH MOMENTUM")
                    .font(.system(size: 12, weight: .black))
                    .tracking(1)
            }
            
            ZStack {
                // Baseline
                Rectangle()
                    .fill(FottyTheme.border.opacity(0.5))
                    .frame(height: 1)
                
                if momentum.isEmpty {
                    Text("Momentum data will update shortly")
                        .font(.system(size: 10))
                        .foregroundStyle(FottyTheme.textTertiary)
                } else {
                    // Simple path representation
                    GeometryReader { geo in
                        Path { path in
                            let denom = max(1, CGFloat(momentum.count - 1))
                            let stepX = geo.size.width / denom
                            let centerY = geo.size.height / 2
                            
                            path.move(to: CGPoint(x: 0, y: centerY - CGFloat(momentum[0]) * centerY))
                            
                            for i in 1..<momentum.count {
                                path.addLine(to: CGPoint(x: CGFloat(i) * stepX, y: centerY - CGFloat(momentum[i]) * centerY))
                            }
                        }
                        .stroke(FottyTheme.accent, lineWidth: 2)
                    }
                    .frame(height: 60)
                }
            }
            .frame(height: 80)
            .padding()
            .background(FottyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
}
