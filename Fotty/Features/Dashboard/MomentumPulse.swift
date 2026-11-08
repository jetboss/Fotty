import SwiftUI

struct MomentumPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var allowsMotion: Bool {
        FottyMotionPolicy.allowsContinuousMotion(
            reduceMotion: reduceMotion,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            sceneIsActive: scenePhase == .active
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !allowsMotion)) { timeline in
            let time = allowsMotion ? timeline.date.timeIntervalSinceReferenceDate : 0
            HStack(spacing: 2) {
                ForEach(0..<6) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(FottyTheme.momentumGradient)
                        .frame(width: 2, height: height(for: index, time: time))
                        .opacity(opacity(for: index, time: time))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func height(for index: Int, time: TimeInterval) -> CGFloat {
        let base = CGFloat(5 + (index % 3) * 2)
        guard allowsMotion else { return base }
        let wave = (sin(time * 5.2 + Double(index) * 0.9) + 1) / 2
        return base + CGFloat(wave) * 8
    }

    private func opacity(for index: Int, time: TimeInterval) -> Double {
        guard allowsMotion else { return 0.55 }
        let wave = (sin(time * 5.2 + Double(index) * 0.9) + 1) / 2
        return 0.35 + wave * 0.65
    }
}
