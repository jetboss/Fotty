import SwiftUI

struct MatchHubHeader: View {
    let data: MatchHubData?
    let onWatchLive: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 10) {
            // Competition and Match Info
            HStack {
                Text(data?.fixture.competition.audienceFacingName ?? "Match Detail")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(FottyTheme.textSecondary)
                    .tracking(0.8)
                    .lineLimit(1)
                
                Spacer()
                
                if let data {
                    DataQualityIndicator(status: data.dataQuality, lastUpdated: data.lastUpdated)
                }
            }
            .padding(.horizontal)
            
            // Scoreboard Area
            HStack(spacing: 0) {
                // Home Team
                VStack(spacing: 6) {
                    TeamBadgeView(badgeURL: data?.homeTeam.crestURL, teamName: data?.homeTeam.displayName ?? "", size: 48)
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    
                    Text(data?.homeTeam.displayName ?? "Home")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .frame(width: 84)
                }
                .layoutPriority(0)
                
                Spacer(minLength: 6)
                
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
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                    } else if let kickoff = data?.fixture.utcDate {
                        Text(kickoff.formatted(date: .omitted, time: .shortened))
                            .font(.fottyScaled(size: 24, weight: .black, design: .rounded))
                            .lineLimit(1)
                    }
                    
                    statusBadge
                }
                .frame(minWidth: 72)
                
                Spacer(minLength: 6)
                
                // Away Team
                VStack(spacing: 6) {
                    TeamBadgeView(badgeURL: data?.awayTeam.crestURL, teamName: data?.awayTeam.displayName ?? "", size: 48)
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    
                    Text(data?.awayTeam.displayName ?? "Away")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .frame(width: 84)
                }
                .layoutPriority(0)
            }
            .padding(.horizontal, 16)

            if let detailLine = matchDetailLine {
                Label(detailLine, systemImage: "calendar")
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            
            // Context-aware CTA
            if data?.fixture.status.isLive == true, onWatchLive != nil {
                watchLiveButton
            }
        }
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
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FottyTheme.accentText)
            } else {
                Text(statusText(status))
                    .font(.system(size: 12, weight: .black))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(FottyTheme.surfaceElevated)
                    .clipShape(Capsule())
            }
        } else {
            Text("NS")
                .font(.system(size: 12, weight: .black))
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
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Watch live")
            }
            .font(FottyTheme.typeAction)
            .foregroundStyle(FottyTheme.textOnAccent)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(FottyTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusSM, style: .continuous))
        }
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
            
            Text("\(statusLabel) • \(ageLabel)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(FottyTheme.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(FottyTheme.surfaceElevated)
        .clipShape(Capsule())
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
