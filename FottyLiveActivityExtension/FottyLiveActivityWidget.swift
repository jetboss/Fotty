import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FottyLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        FottyMatchLiveActivityWidget()
        FottyFPLDeadlineWidget()
    }
}

struct FottyMatchLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FottyMatchActivityAttributes.self) { context in
            FottyLockScreenLiveActivityView(context: context)
                .activityBackgroundTint(Color(red: 0.04, green: 0.05, blue: 0.08))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    teamBlock(context.attributes.homeTeam, label: "HOME")
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(context.state.scoreText)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text(context.state.phase.uppercased())
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(statusColor(context.state))
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    teamBlock(context.attributes.awayTeam, label: "AWAY")
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.tv.fill")
                            .foregroundStyle(statusColor(context.state))
                        Text(context.state.phase)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("Return to Fotty")
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Circle()
                        .fill(statusColor(context.state))
                        .frame(width: 6, height: 6)
                    Text(compactPhase(context.state.phase))
                        .font(.system(size: 10, weight: .black))
                }
            } compactTrailing: {
                Text(context.state.scoreText)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .monospacedDigit()
            } minimal: {
                Text(context.state.scoreText == "—" ? "LIVE" : context.state.scoreText)
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(statusColor(context.state))
            }
            .widgetURL(URL(string: "fotty://live/\(context.attributes.matchID)"))
            .keylineTint(statusColor(context.state))
        }
    }

    private func teamBlock(_ name: String, label: String) -> some View {
        VStack(alignment: .center, spacing: 3) {
            Text(shortCode(name))
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }

    private func statusColor(_ state: FottyMatchActivityAttributes.ContentState) -> Color {
        if state.isPlaying { return Color(red: 1.0, green: 0.16, blue: 0.36) }
        return .gray
    }

    private func shortCode(_ team: String) -> String {
        let words = team
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        if words.count <= 1 {
            return String((words.first ?? team).prefix(4)).uppercased()
        }

        return words.prefix(3).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private func compactPhase(_ phase: String) -> String {
        let trimmed = phase.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Score unavailable" { return "LIVE" }
        return String(trimmed.prefix(7)).uppercased()
    }
}

private struct FottyLockScreenLiveActivityView: View {
    let context: ActivityViewContext<FottyMatchActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    if context.state.isPlaying {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.16, blue: 0.36))
                            .frame(width: 8, height: 8)
                    }

                    Text("LIVE MATCH")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.4)
                        .foregroundStyle(Color(red: 1.0, green: 0.16, blue: 0.36))
                }

                Spacer()

                HStack(spacing: 6) {
                    Text(context.state.phase)
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())

                }
            }

            HStack(alignment: .center) {
                Text(context.attributes.homeTeam)
                    .lineLimit(1)
                Spacer()
                Text(context.state.scoreText)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text(context.attributes.awayTeam)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            }
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white)

            HStack(spacing: 8) {
                Image(systemName: "arrow.up.forward.app.fill")
                    .foregroundStyle(Color(red: 1.0, green: 0.16, blue: 0.36))
                Text(context.state.isPlaying ? "Tap to return to your match" : "Tap to open this match in Fotty")
                    .lineLimit(1)
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
        }
        .padding(16)
    }
}
