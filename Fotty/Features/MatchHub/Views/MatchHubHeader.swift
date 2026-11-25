import SwiftUI

struct MatchHubHeader: View {
    @Environment(\.fottyStreamLookupBusy) private var streamLookupBusy
    let data: MatchHubData?
    let onWatchLive: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    var body: some View {
        VStack(spacing: 10) {
            // Competition and Match Info
            metadataLayout {
                Text(data?.fixture.competition.audienceFacingName ?? "Match Detail")
                    .font(FottyTheme.typeModuleTitle)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                
                if let data {
                    DataQualityIndicator(status: data.dataQuality, lastUpdated: data.lastUpdated)
                }
            }
            .padding(.horizontal)
            
            // Scoreboard Area
            scoreboardLayout {
                // Home Team
                teamIdentity(name: data?.homeTeam.displayName ?? "Home", badgeURL: data?.homeTeam.crestURL)
                
                // Score and Status — intrinsic width so large digits are not clipped between team columns.
                VStack(spacing: 5) {
                    if data?.fixture.status.isLive == true {
                        LivePulse()
                            .scaleEffect(0.92)
                    }
                    
                    if showsScore {
                        Text("\(data?.score.home ?? 0)–\(data?.score.away ?? 0)")
                            .font(.fottyScaled(size: 34, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                    } else if let kickoff = data?.fixture.utcDate {
                        Text(kickoff.formatted(date: .omitted, time: .shortened))
                            .font(.title2.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)
                    }
                    
                    statusBadge
                }
                .frame(minWidth: 72)
                
                // Away Team
                teamIdentity(name: data?.awayTeam.displayName ?? "Away", badgeURL: data?.awayTeam.crestURL)
            }
            .padding(.horizontal, 16)

            if let detailLine = matchDetailLine {
                Label(detailLine, systemImage: "calendar")
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            
            // Context-aware CTA
            if data?.fixture.status.isLive == true, onWatchLive != nil {
                watchLiveButton
            }
        }
        .foregroundStyle(FottyTheme.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 14)
        .background(
            ZStack {
                FottyTheme.surface
                
                PitchPattern()
                    .opacity(0.1)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(FottyTheme.border.opacity(0.5), lineWidth: 1)
                .padding(.horizontal, 10)
        )
    }

    private var metadataLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
    }

    private var scoreboardLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .center, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }

    private func teamIdentity(name: String, badgeURL: URL?) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            : AnyLayout(VStackLayout(alignment: .center, spacing: 8))
        return layout {
            TeamBadgeView(badgeURL: badgeURL, teamName: name, size: 48)
                .accessibilityHidden(true)
            Text(name)
                .font(FottyTheme.typeModuleTitle)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center)
        .accessibilityElement(children: .combine)
    }

    private var showsScore: Bool {
        guard let status = data?.fixture.status else { return false }
        return status.isLive || status.isFinished
    }

    private var matchDetailLine: String? {
        guard let fixture = data?.fixture else { return nil }
        var parts: [String] = []
        if !fixture.status.isLive {
            parts.append(fixture.utcDate.formatted(date: .abbreviated, time: .shortened))
        }
        if let venue = fixture.venue?.name, !venue.isEmpty {
            parts.append(venue)
        }
        if let matchday = fixture.matchday {
            parts.append("Matchday \(matchday)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        if let status = data?.fixture.status {
            if status.isLive {
                Text(data?.fixture.elapsedMinutes.map { "\($0)'" } ?? "Live")
                    .font(FottyTheme.typeMeta.weight(.semibold))
                    .foregroundStyle(FottyTheme.accentText)
            } else {
                Text(statusText(status))
                    .font(FottyTheme.typeMeta.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(FottyTheme.surfaceElevated)
                    .clipShape(Capsule())
            }
        } else {
            Text("NS")
                .font(FottyTheme.typeMeta.weight(.semibold))
        }
    }

    private func statusText(_ status: FottyMatchStatus) -> String {
        switch status {
        case .scheduled, .preMatch: return "Scheduled"
        case .halfTime: return "Half time"
        case .fullTime: return "Full time"
        case .extraTime: return "Extra time"
        case .penalties: return "Penalties"
        case .postponed: return "Postponed"
        case .cancelled: return "Cancelled"
        case .abandoned: return "Abandoned"
        case .live: return "Live"
        case .unknown: return "Status unavailable"
        }
    }
    
    @ViewBuilder
    private var watchLiveButton: some View {
        Button {
            HapticManager.impact(.medium)
            onWatchLive?()
        } label: {
            Label("Watch live", systemImage: "play.fill")
        }
        .disabled(streamLookupBusy)
        .buttonStyle(FottyPrimaryButtonStyle())
        .padding(.top, 6)
    }
}

struct DataQualityIndicator: View {
    let status: MatchHubData.DataQualityStatus
    let lastUpdated: Date
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            
            Text("\(statusLabel) • \(ageLabel)")
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(FottyTheme.surfaceElevated)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }
    
    private var statusColor: Color {
        switch status {
        case .official: return .green
        case .verified: return .green
        case .degraded: return .orange
        case .stale: return .red
        case .fallback: return .blue
        }
    }

    private var statusLabel: String {
        switch status {
        case .official: return "Official FPL"
        case .verified: return "Live data"
        case .degraded: return "Partial data"
        case .stale: return "Update delayed"
        case .fallback: return "Schedule available"
        }
    }

    private var ageLabel: String {
        let seconds = max(0, Date().timeIntervalSince(lastUpdated))
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h ago" }
        return lastUpdated.formatted(date: .abbreviated, time: .omitted)
    }
}

private extension Date {
    var minuteDifference: Int {
        let diff = Calendar.current.dateComponents([.minute], from: self, to: Date()).minute ?? 0
        return max(0, min(90, diff))
    }
}
