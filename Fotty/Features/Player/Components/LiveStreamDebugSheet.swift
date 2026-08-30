import SwiftUI

struct LiveStreamDebugSheet: View {
    let event: AnalyticalDataEngine.EventReference
    let attemptDiagnostics: StreamAttemptDiagnostics?
    let sourceCount: Int
    let currentSourceIndex: Int
    let activeSource: StreamSource?
    let p2pProbeInfo: String?
    let isUsingWebEmbed: Bool
    let proxyPort: UInt16?
    let activeSourceHealthScore: Int?
    let connectionPhase: String
    let lastStartupLatencyMs: Int?
    let stallCount: Int
    let playbackStagnationTicks: Int
    let isPlaybackWatchdogArmed: Bool
    let isNetworkReachable: Bool
    let pendingRetryAfterNetworkRestore: Bool
    let autoFailoverCount: Int
    let lastFailureKind: String
    let lastFailureReason: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Match") {
                    infoRow("Fixture", "\(event.homeName) vs \(event.awayName)")
                    infoRow("Competition", event.categoryDisplayName)
                }
                
                Section("Source") {
                    infoRow("Provider", activeSource?.provider ?? "None")
                    infoRow("Mode", isUsingWebEmbed ? "Web Embed" : "Native AVPlayer")
                    infoRow("Index", sourceCount > 0 ? "\(currentSourceIndex + 1) / \(sourceCount)" : "0 / 0")
                    infoRow("Host", activeSource?.url.host ?? activeSource?.url.absoluteString ?? "Unknown")
                    infoRow("Proxy Port", proxyPort.map(String.init) ?? "Not active")
                    infoRow("Health Score", activeSourceHealthScore.map(String.init) ?? "N/A")
                    if let p2pProbeInfo, !p2pProbeInfo.isEmpty {
                        infoRow("P2P Probe", p2pProbeInfo)
                    }
                }
                
                Section("Playback Health") {
                    infoRow("Phase", connectionPhase)
                    infoRow("Network", isNetworkReachable ? "Online" : "Offline")
                    infoRow("Pending Net Retry", pendingRetryAfterNetworkRestore ? "Yes" : "No")
                    infoRow("Last Startup", lastStartupLatencyMs.map { "\($0) ms" } ?? "N/A")
                    infoRow("Stalls", "\(stallCount)")
                    infoRow("Watchdog", isPlaybackWatchdogArmed ? "Armed" : "Idle")
                    infoRow("Stagnation Ticks", "\(playbackStagnationTicks)")
                    infoRow("Auto Failovers", "\(autoFailoverCount)")
                    infoRow("Failure Kind", lastFailureKind)
                    infoRow("Last Failure", lastFailureReason ?? "None")
                }

                if let attemptDiagnostics {
                    Section("Attempt") {
                        infoRow("Attempt ID", attemptDiagnostics.attemptID)
                        infoRow("Final State", attemptDiagnostics.finalState.rawValue)
                        infoRow("Timeline Events", "\(attemptDiagnostics.timeline.count)")
                        infoRow("Provider Attempts", "\(attemptDiagnostics.providerAttempts.count)")
                    }

                    Section("Timeline") {
                        ForEach(attemptDiagnostics.timeline) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name.rawValue)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(FottyTheme.textPrimary)
                                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.system(size: 11))
                                    .foregroundStyle(FottyTheme.textSecondary)
                                Text(entry.currentState.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(FottyTheme.accentText)
                                if let providerName = entry.providerName {
                                    Text(providerName)
                                        .font(.system(size: 11))
                                        .foregroundStyle(FottyTheme.textSecondary)
                                }
                                if let failureCategory = entry.failureCategory {
                                    Text(failureCategory.rawValue)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.red.opacity(0.8))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Stream Debug")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    @ViewBuilder
    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(FottyTheme.textSecondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(FottyTheme.textPrimary)
        }
        .font(.system(size: 14, weight: .medium))
    }
}
