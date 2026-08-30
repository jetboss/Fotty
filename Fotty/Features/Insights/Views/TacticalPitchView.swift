import SwiftUI

struct TacticalPitchView: View {
    let homeLineup: FottyLineup
    let awayLineup: FottyLineup
    let homeTeamName: String
    let awayTeamName: String
    var homeAccent: Color = Color(red: 0.35, green: 0.58, blue: 1.0)
    var awayAccent: Color = Color(red: 1.0, green: 0.55, blue: 0.28)

    @State private var showLineupsList = false

    private var hasBenchPlayers: Bool {
        !homeLineup.substitutes.isEmpty || !awayLineup.substitutes.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            teamFormationBlock(
                teamName: homeTeamName,
                lineup: homeLineup,
                accent: homeAccent,
                invertDepth: false
            )

            teamFormationBlock(
                teamName: awayTeamName,
                lineup: awayLineup,
                accent: awayAccent,
                invertDepth: true
            )

            DisclosureGroup(isExpanded: $showLineupsList) {
                fullLineupsPanel
                    .padding(.top, 10)
            } label: {
                HStack {
                    Text("Lineups")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FottyTheme.textSecondary)
                    Spacer()
                    Text(lineupsSummaryLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FottyTheme.textTertiary)
                }
            }
            .tint(FottyTheme.accentText)
        }
    }

    private var lineupsSummaryLabel: String {
        let starters = min(homeLineup.startingXi.count, 11) + min(awayLineup.startingXi.count, 11)
        if hasBenchPlayers {
            let bench = homeLineup.substitutes.count + awayLineup.substitutes.count
            return "\(starters) starters · \(bench) subs"
        }
        return "\(starters) players"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "sportscourt.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FottyTheme.accentText)
            Text("LINEUPS & FORMATIONS")
                .font(.system(size: 12, weight: .black))
                .tracking(0.8)
            Spacer()
            if !formationsLabel.isEmpty {
                Text(formationsLabel)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(FottyTheme.surface.opacity(0.9))
                    .clipShape(Capsule())
            }
        }
    }

    private var formationsLabel: String {
        let h = homeLineup.formation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let a = awayLineup.formation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if h.isEmpty, a.isEmpty { return "" }
        if h.isEmpty { return a }
        if a.isEmpty { return h }
        return "\(h) · \(a)"
    }

    private func teamFormationBlock(
        teamName: String,
        lineup: FottyLineup,
        accent: Color,
        invertDepth: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                Text(teamName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .lineLimit(1)
                if let formation = lineup.formation?.trimmingCharacters(in: .whitespacesAndNewlines), !formation.isEmpty {
                    Text(formation)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accent.opacity(0.15))
                        .clipShape(Capsule())
                }
                Spacer(minLength: 0)
                if let coach = lineup.coach, !coach.isEmpty {
                    Text(coach)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(FottyTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            FormationPitchCanvas(
                lineup: lineup,
                accent: accent,
                invertDepth: invertDepth
            )
            .frame(maxWidth: .infinity)
            .frame(height: 240)
        }
    }

    private var fullLineupsPanel: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                lineupColumn(teamName: homeTeamName, lineup: homeLineup, accent: homeAccent)
                lineupColumn(teamName: awayTeamName, lineup: awayLineup, accent: awayAccent)
            }
        }
        .padding(14)
        .background(FottyTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func lineupColumn(teamName: String, lineup: FottyLineup, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(teamName)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(accent)
                .lineLimit(2)

            if let coach = lineup.coach, !coach.isEmpty {
                Text("Coach · \(coach)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FottyTheme.textTertiary)
                    .lineLimit(2)
            }

            lineupSection(title: "Starting XI", players: lineup.startingXi, accent: accent, muted: false)

            if !lineup.substitutes.isEmpty {
                lineupSection(title: "Substitutes", players: lineup.substitutes, accent: accent, muted: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lineupSection(title: String, players: [FottyPlayer], accent: Color, muted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(muted ? FottyTheme.textTertiary : FottyTheme.textSecondary)
                .tracking(0.6)

            if players.isEmpty {
                Text("Not available")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FottyTheme.textTertiary)
            } else {
                ForEach(players) { player in
                    playerRow(player, accent: accent, muted: muted)
                }
            }
        }
    }

    private func playerRow(_ player: FottyPlayer, accent: Color, muted: Bool) -> some View {
        HStack(spacing: 8) {
            Text(player.number.map { "\($0)" } ?? "–")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(muted ? FottyTheme.textSecondary : FottyTheme.textPrimary)
                .frame(width: 22, height: 22)
                .background(accent.opacity(muted ? 0.12 : 0.2))
                .clipShape(Circle())
            Text(player.name)
                .font(.system(size: 11, weight: muted ? .medium : .semibold))
                .foregroundStyle(muted ? FottyTheme.textSecondary : FottyTheme.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
            if let pos = player.position, !pos.isEmpty {
                Text(pos)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(FottyTheme.textTertiary)
            }
        }
    }
}

// MARK: - Pitch canvas

private struct FormationPitchCanvas: View {
    let lineup: FottyLineup
    let accent: Color
    var invertDepth: Bool

    private var starters: [FottyPlayer] { Array(lineup.startingXi.prefix(11)) }

    var body: some View {
        GeometryReader { geo in
            let placements = FormationLayout.layoutPlayers(starters, in: geo.size, invertDepth: invertDepth)
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.14, green: 0.42, blue: 0.24),
                                Color(red: 0.09, green: 0.30, blue: 0.17)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                PitchMarkingsOverlay()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)

                ForEach(placements, id: \.player.id) { item in
                    PlayerPitchMarker(player: item.player, accent: accent)
                        .position(item.point)
                }
            }
        }
    }
}

private struct PitchMarkingsOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let line = Color.white.opacity(0.22)
            let thin: CGFloat = 1.5

            ZStack {
                // Mow stripes
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { i in
                        Rectangle()
                            .fill(i.isMultiple(of: 2) ? Color.white.opacity(0.04) : Color.clear)
                            .frame(height: h / 8)
                    }
                }

                // Halfway line
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.5))
                    p.addLine(to: CGPoint(x: w, y: h * 0.5))
                }
                .stroke(line, lineWidth: thin)

                // Center circle
                Circle()
                    .stroke(line, lineWidth: thin)
                    .frame(width: min(w, h) * 0.22)
                    .position(x: w * 0.5, y: h * 0.5)

                // Penalty areas (top & bottom)
                penaltyBox(width: w, height: h, edge: .top, line: line, thin: thin)
                penaltyBox(width: w, height: h, edge: .bottom, line: line, thin: thin)

                // Goals
                RoundedRectangle(cornerRadius: 2)
                    .stroke(line, lineWidth: thin)
                    .frame(width: w * 0.28, height: 5)
                    .position(x: w * 0.5, y: 4)
                RoundedRectangle(cornerRadius: 2)
                    .stroke(line, lineWidth: thin)
                    .frame(width: w * 0.28, height: 5)
                    .position(x: w * 0.5, y: h - 4)
            }
        }
    }

    private enum VerticalEdge { case top, bottom }

    private func penaltyBox(width w: CGFloat, height h: CGFloat, edge: VerticalEdge, line: Color, thin: CGFloat) -> some View {
        let boxW = w * 0.62
        let boxH = h * 0.16
        let y = edge == .top ? boxH * 0.5 : h - boxH * 0.5
        return RoundedRectangle(cornerRadius: 4)
            .stroke(line, lineWidth: thin)
            .frame(width: boxW, height: boxH)
            .position(x: w * 0.5, y: y)
    }
}

private struct PlayerPitchMarker: View {
    let player: FottyPlayer
    let accent: Color

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: 36, height: 36)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.95), accent.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                    )
                Text(markerNumber)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            Text(shortSurname)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .frame(width: 52)
                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
        }
    }

    private var markerNumber: String {
        if let n = player.number { return "\(n)" }
        return FormationLayout.shortLabel(player.name)
    }

    private var shortSurname: String {
        let parts = player.name.split(separator: " ").map(String.init)
        if let last = parts.last, !last.isEmpty { return last }
        return FormationLayout.shortLabel(player.name)
    }
}

// MARK: - Layout engine
//
// API-Football grid is `row:column` (row = depth from goal, column = left→right index within that row).
// Do **not** map column numbers to absolute X — column 1 is not “left touchline”; it is the first slot in the row.
// Group by row, then spread players evenly across the row width (same approach as Fotty Android `TacticalPitch`).

private enum FormationLayout {
    static func shortLabel(_ name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        if parts.count >= 2, let a = parts.first?.first, let b = parts.last?.first {
            return "\(a)\(b)"
        }
        if name.count > 10 { return String(name.prefix(9)) + "…" }
        return name
    }

    static func layoutPlayers(_ players: [FottyPlayer], in size: CGSize, invertDepth: Bool) -> [(player: FottyPlayer, point: CGPoint)] {
        guard !players.isEmpty, size.width > 1, size.height > 1 else { return [] }

        let marginX: CGFloat = 0.06
        let marginY: CGFloat = 0.07
        let usableW = size.width * (1 - 2 * marginX)
        let usableH = size.height * (1 - 2 * marginY)

        var rows: [Int: [FottyPlayer]] = [:]
        for (index, player) in players.enumerated() {
            let row = player.y ?? positionalRowFallback(player: player, index: index, total: players.count)
            rows[row, default: []].append(player)
        }

        let rowKeys = rows.keys.sorted()
        guard let minRow = rowKeys.first, let maxRow = rowKeys.last else { return [] }
        let rowSpan = max(maxRow - minRow, 1)

        var result: [(player: FottyPlayer, point: CGPoint)] = []

        for rowKey in rowKeys {
            let rowPlayers = (rows[rowKey] ?? []).sorted {
                ($0.x ?? Int.max, $0.name) < ($1.x ?? Int.max, $1.name)
            }
            let count = rowPlayers.count
            let depthStep = CGFloat(rowKey - minRow) / CGFloat(rowSpan)
            var yFrac = 0.08 + depthStep * 0.84
            if invertDepth { yFrac = 1 - yFrac }
            let yPos = marginY * size.height + usableH * yFrac

            for (index, player) in rowPlayers.enumerated() {
                let horizontalT: CGFloat = count <= 1
                    ? 0.5
                    : CGFloat(index + 1) / CGFloat(count + 1)
                let xPos = marginX * size.width + usableW * horizontalT
                result.append((player: player, point: CGPoint(x: xPos, y: yPos)))
            }
        }

        return result
    }

    /// When API grid is missing (e.g. TheSportsDB), bucket by G/D/M/F into pseudo-rows 1…4.
    private static func positionalRowFallback(player: FottyPlayer, index: Int, total: Int) -> Int {
        guard let pos = player.position?.uppercased(), let c = pos.first else {
            if index == 0 { return 1 }
            if index <= 4 { return 2 }
            if index <= 8 { return 3 }
            return 4
        }
        switch String(c) {
        case "G": return 1
        case "D": return 2
        case "M": return 3
        case "F": return 4
        default:
            if index == 0 { return 1 }
            if index <= 4 { return 2 }
            if index <= 8 { return 3 }
            return 4
        }
    }
}

extension TacticalPitchView {
    init(
        homeLineup: FottyLineup,
        awayLineup: FottyLineup,
        homeTeam: FottyTeam,
        awayTeam: FottyTeam
    ) {
        self.homeLineup = homeLineup
        self.awayLineup = awayLineup
        self.homeTeamName = homeTeam.displayName
        self.awayTeamName = awayTeam.displayName
        self.homeAccent = Color.fromTeamColor(homeTeam.color) ?? Color(red: 0.35, green: 0.58, blue: 1.0)
        self.awayAccent = Color.fromTeamColor(awayTeam.color) ?? Color(red: 1.0, green: 0.55, blue: 0.28)
    }
}

private extension Color {
    static func fromTeamColor(_ raw: String?) -> Color? {
        guard var hex = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }
}
