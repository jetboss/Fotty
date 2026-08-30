import SwiftUI

/// Runs **StreamPipelineValidationService** against public sample URLs (reachable from DEBUG Settings only).
struct StreamPipelineValidationView: View {
    @State private var report: StreamPipelineValidationReport?
    @State private var isRunning = false
    @State private var continuityReport: StreamPlaybackContinuityReport?
    @State private var isRunningContinuitySoak = false
    @State private var continuityProgress = 0

    var body: some View {
        ZStack {
            FottyTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: FottyTheme.spacingLG) {
                    Text("Validates URL hygiene, HTTP probes, StreamContractValidator, and AVAsset.isPlayable using Apple’s public HLS sample and a common sample MP4. Does not resolve P2P or broker-only sources.")
                        .font(.system(size: 13))
                        .foregroundStyle(FottyTheme.textSecondary)

                    if isRunning {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Running checks…")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }

                    Button {
                        Task { await run() }
                    } label: {
                        Text(report == nil ? "Run full suite" : "Run again")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(FottyTheme.accent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isRunning)

                    if let report {
                        HStack {
                            Text(report.allPassed ? "All steps passed" : "Some steps failed")
                                .font(.system(size: 15, weight: .black))
                            Spacer()
                            ShareLink(item: report.copyPasteSummary()) {
                                Label("Export", systemImage: "square.and.arrow.up")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .padding(.top, 8)

                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(report.steps) { step in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: step.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(step.passed ? .green : .red)
                                        Text(step.title)
                                            .font(.system(size: 14, weight: .bold))
                                    }
                                    Text(step.detail)
                                        .font(.system(size: 12))
                                        .foregroundStyle(FottyTheme.textSecondary)
                                    Text(step.evidenceTag)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(FottyTheme.textTertiary)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(FottyTheme.surfaceElevated.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }

                    Divider()
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Playback continuity")
                            .font(.system(size: 17, weight: .black))
                        Text("Runs the production player, local header proxy, readiness observer, watchdog, and failover policy for two minutes. The reference video is muted for the entire run.")
                            .font(.system(size: 13))
                            .foregroundStyle(FottyTheme.textSecondary)
                    }

                    if isRunningContinuitySoak {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: Double(continuityProgress), total: 120)
                            Text("Muted soak: \(continuityProgress) / 120 seconds")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }

                    Button {
                        Task { await runContinuitySoak() }
                    } label: {
                        Text(continuityReport == nil ? "Run 2-minute muted soak" : "Run muted soak again")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(FottyTheme.surfaceElevated)
                            .foregroundStyle(FottyTheme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isRunning || isRunningContinuitySoak)

                    if let continuityReport {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Image(systemName: continuityReport.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(continuityReport.passed ? .green : .red)
                                Text(continuityReport.passed ? "Continuity passed" : "Continuity failed")
                                    .font(.system(size: 15, weight: .black))
                                Spacer()
                                ShareLink(item: continuityReport.copyPasteSummary()) {
                                    Label("Export", systemImage: "square.and.arrow.up")
                                }
                            }
                            Text(String(format: "Decoded %.1fs · %d advancing samples · %d automatic failovers", continuityReport.playbackProgressSeconds, continuityReport.advancingSamples, continuityReport.automaticFailovers))
                                .font(.system(size: 12))
                                .foregroundStyle(FottyTheme.textSecondary)
                            Text("Attempt/source/item stable: \(continuityReport.attemptStayedStable ? "yes" : "no") / \(continuityReport.sourceStayedStable ? "yes" : "no") / \(continuityReport.playerItemStayedStable ? "yes" : "no")")
                                .font(.system(size: 12))
                                .foregroundStyle(FottyTheme.textSecondary)
                            if let failure = continuityReport.failureReason {
                                Text(failure)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(12)
                        .background(FottyTheme.surfaceElevated.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(FottyTheme.spacingMD)
            }
        }
        .navigationTitle("Stream pipeline checks")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run() async {
        await MainActor.run {
            isRunning = true
        }
        let result = await StreamPipelineValidationService.runFullSuite()
        await MainActor.run {
            self.report = result
            self.isRunning = false
        }
    }

    @MainActor
    private func runContinuitySoak() async {
        continuityProgress = 0
        isRunningContinuitySoak = true
        continuityReport = await StreamPipelineValidationService.runPlaybackContinuitySoak(
            durationSeconds: 120,
            onProgress: { elapsed, _ in continuityProgress = elapsed }
        )
        isRunningContinuitySoak = false
    }
}
