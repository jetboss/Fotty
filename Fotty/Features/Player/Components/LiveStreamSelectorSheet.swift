import SwiftUI

// MARK: - Live Stream Selector Sheet
// A compact, consumer-facing picker. Diagnostics and provider health internals do
// not belong here: every visible label should help somebody choose a source.

struct LiveStreamSelectorSheet: View {
    let sessions: [StreamSession]
    @Binding var currentSourceIndex: Int
    let failedSessionIDs: Set<UUID>
    let currentPlaybackHasError: Bool
    let onSelect: (Int) -> Void
    
    @Environment(\.dismiss) private var dismiss
    init(
        sessions: [StreamSession],
        currentSourceIndex: Binding<Int>,
        failedSessionIDs: Set<UUID>,
        currentPlaybackHasError: Bool = false,
        onSelect: @escaping (Int) -> Void
    ) {
        self.sessions = sessions
        self._currentSourceIndex = currentSourceIndex
        self.failedSessionIDs = failedSessionIDs
        self.currentPlaybackHasError = currentPlaybackHasError
        self.onSelect = onSelect
    }
    
    private var playableSessions: [(index: Int, session: StreamSession)] {
        sessions.enumerated().compactMap { index, session in
            (session.validationStatus == .validated) ? (index, session) : nil
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Broadcast sources")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(FottyTheme.textPrimary)
                    
                    Text(sourceSummary)
                        .font(.system(size: 13))
                        .foregroundStyle(FottyTheme.textSecondary)
                }
                
                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(FottyTheme.textTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close broadcast sources")
            }
            .padding(.horizontal, FottyTheme.spacingLG)
            .padding(.top, FottyTheme.spacingLG)
            .padding(.bottom, FottyTheme.spacingMD)
            
            ScrollView {
                VStack(spacing: FottyTheme.spacingMD) {
                    ForEach(playableSessions, id: \.session.id) { index, session in
                        SessionRow(
                            session: session,
                            displayNumber: index + 1,
                            isActive: index == currentSourceIndex,
                            isFailed: failedSessionIDs.contains(session.id)
                                || (index == currentSourceIndex && currentPlaybackHasError),
                            isCoolingDown: LiveSourceHealthStore.isTemporarilyUnavailable(session.legacySource)
                        ) {
                            if index != currentSourceIndex
                                || failedSessionIDs.contains(session.id)
                                || LiveSourceHealthStore.isTemporarilyUnavailable(session.legacySource) {
                                onSelect(index)
                                dismiss()
                            }
                        }
                    }
                }
                .padding(.horizontal, FottyTheme.spacingMD)
                .padding(.bottom, FottyTheme.spacingXL)
            }
        }
        .background(FottyTheme.background)
        .preferredColorScheme(.dark)
    }

    private var sourceSummary: String {
        let count = playableSessions.count
        let noun = count == 1 ? "broadcast option" : "broadcast options"
        return "\(count) \(noun) · Tap one to switch playback"
    }
}

struct SessionRow: View {
    let session: StreamSession
    let displayNumber: Int
    let isActive: Bool
    let isFailed: Bool
    var isCoolingDown = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text("\(displayNumber)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(isActive ? FottyTheme.textOnAccent : FottyTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(isActive ? FottyTheme.accent : FottyTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Broadcast \(displayNumber)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(FottyTheme.textPrimary)
                        .lineLimit(1)

                    Text(sourceDescription)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FottyTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    if isActive {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                    }
                    Text(actionLabel)
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(statusColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(statusColor.opacity(0.12))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 56)
            .background(FottyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous)
                    .strokeBorder(
                        isActive ? FottyTheme.accent.opacity(0.7) : FottyTheme.border.opacity(0.75),
                        lineWidth: isActive ? 1.5 : 0.5
                    )
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier("broadcast-source-\(displayNumber)")
        .accessibilityLabel("Broadcast \(displayNumber), \(actionLabel)")
        .accessibilityHint(isActive ? "This source is currently playing" : "Switch playback to this source")
    }

    private var sourceDescription: String {
        let raw = session.qualityLabel ?? session.title ?? "Live video"
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if raw.contains(" - ") || raw.contains(" · ") {
            return raw.replacingOccurrences(of: " - ", with: " · ")
        }

        if normalized.contains("4k") || normalized.contains("uhd") {
            return "Ultra HD video"
        }
        if normalized.contains("1080") || normalized.contains("full hd") || normalized.contains("fhd") {
            return "Full HD video"
        }
        if normalized.contains("hd") {
            return "HD video"
        }
        if normalized.contains("sd") {
            return "Standard video"
        }
        return "Live video"
    }

    private var actionLabel: String {
        if isFailed || isCoolingDown { return "Try again" }
        if isActive { return "Selected" }
        return "Select"
    }

    private var statusColor: Color {
        if isActive { return FottyTheme.accent }
        if isFailed || isCoolingDown { return FottyTheme.textSecondary }
        return FottyTheme.textPrimary
    }
}

struct DiscoveryDebugView: View {
    let diagnostics: MatchDiscoveryDiagnostics
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Overview")) {
                    LabeledContent("Match ID", value: diagnostics.matchId)
                    LabeledContent("Status", value: diagnostics.engineStatus)
                    LabeledContent("Queries Generated", value: "\(diagnostics.generatedQueries.count)")
                    LabeledContent("Raw Results", value: "\(diagnostics.rawResultCount)")
                    LabeledContent("Final Candidates", value: "\(diagnostics.candidateCount)")
                    LabeledContent("Rejected", value: "\(diagnostics.rejectedCount)")
                }
                
                Section(header: Text("Generated Queries")) {
                    ForEach(diagnostics.generatedQueries, id: \.self) { query in
                        Text(query)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                
                Section(header: Text("Final Ranked List")) {
                    ForEach(diagnostics.finalRankedList) { candidate in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(candidate.title)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                Spacer()
                                Text(String(format: "%.2f", candidate.finalScore))
                                    .font(.caption)
                                    .padding(4)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(4)
                            }
                            
                            HStack(spacing: 12) {
                                scoreBadge(label: "Team", score: candidate.teamMatchScore)
                                scoreBadge(label: "Health", score: candidate.playbackHealthScore)
                                scoreBadge(label: "Fresh", score: candidate.freshnessScore)
                            }
                            
                            Text(candidate.url.absoluteString)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                if !diagnostics.rejections.isEmpty {
                    Section(header: Text("Rejections")) {
                        ForEach(Array(diagnostics.rejections.keys.sorted()), id: \.self) { cid in
                            VStack(alignment: .leading) {
                                Text(cid)
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                Text(diagnostics.rejections[cid] ?? "Unknown reason")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Discovery Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fottyStandardSheetChrome()
    }
    
    private func scoreBadge(label: String, score: Double) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
            Text(String(format: "%.1f", score))
                .font(.system(size: 8))
        }
        .padding(4)
        .background(score > 0.5 ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(4)
    }
}
