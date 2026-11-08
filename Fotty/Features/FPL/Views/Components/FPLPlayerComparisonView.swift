import SwiftUI

public struct FPLPlayerComparisonView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var viewModel: FPLAdvisorViewModel
    @State private var selectingSlot: ComparisonSlot?
    @State private var playerQuery = ""
    private enum ComparisonSlot: Int, Identifiable {
        case first, second
        var id: Int { rawValue }
    }
    private var player1Index: Int { viewModel.playerScores.firstIndex { $0.id == viewModel.comparisonPlayer1ID } ?? 0 }
    private var player2Index: Int { viewModel.playerScores.firstIndex { $0.id == viewModel.comparisonPlayer2ID } ?? min(1, max(0, viewModel.playerScores.count - 1)) }
    private var comparisonLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }
    
    public init(viewModel: FPLAdvisorViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // Header Title
            HStack {
                Image(systemName: "chart.pie.fill")
                    .font(.fottyScaled(size: 20, weight: .bold))
                    .foregroundStyle(FottyTheme.accentText)
                
                Text("Player Evidence Comparison")
                    .font(.fottyScaled(size: 18, weight: .black))
                    .foregroundStyle(FottyTheme.textPrimary)
                
                Spacer()
                Button {
                    Task { await loadSelectedSummaries(forceRefresh: true) }
                } label: {
                    Image(systemName: "arrow.clockwise").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Refresh both players' official history")
                .disabled(viewModel.playerScores.count < 2 || !viewModel.loadingElementSummaries.isEmpty)
            }
            .padding(16)
            .background(FottyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            if viewModel.playerScores.count >= 2 {
                let p1 = viewModel.playerScores[min(player1Index, viewModel.playerScores.count - 1)]
                let p2 = viewModel.playerScores[min(player2Index, viewModel.playerScores.count - 1)]
                
                // Player Selection Pickers
                comparisonLayout {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle().fill(FottyTheme.success).frame(width: 8, height: 8)
                            Text("PLAYER 1")
                                .font(.fottyScaled(size: 10, weight: .bold))
                                .foregroundStyle(FottyTheme.success)
                        }
                        
                        Button { playerQuery = ""; selectingSlot = .first } label: {
                            Label(p1.player.webName, systemImage: "magnifyingglass")
                                .font(FottyTheme.typeAction)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(FottyPressButtonStyle())
                        .accessibilityLabel("Choose first player, \(p1.player.webName)")
                        .padding(8)
                        .background(FottyTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .frame(maxWidth: .infinity)
                    
                    Text("VS")
                        .font(.fottyScaled(size: 16, weight: .black))
                        .foregroundStyle(FottyTheme.accentText)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle().fill(FottyTheme.liveAccent).frame(width: 8, height: 8)
                            Text("PLAYER 2")
                                .font(.fottyScaled(size: 10, weight: .bold))
                                .foregroundStyle(FottyTheme.accentText)
                        }
                        
                        Button { playerQuery = ""; selectingSlot = .second } label: {
                            Label(p2.player.webName, systemImage: "magnifyingglass")
                                .font(FottyTheme.typeAction)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(FottyPressButtonStyle())
                        .accessibilityLabel("Choose second player, \(p2.player.webName)")
                        .padding(8)
                        .background(FottyTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(16)
                .background(FottyTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // 5-Axis Radar Chart
                VStack(spacing: 12) {
                    HStack {
                        Text("Player strengths · Fotty model")
                            .font(.fottyScaled(size: 11, weight: .black))
                            .foregroundStyle(FottyTheme.textSecondary)
                        Spacer()
                    }
                    
                    if dynamicTypeSize.isAccessibilitySize {
                        accessibleStrengths(first: p1, second: p2)
                    } else {
                        RadarChartCanvas(
                            p1Metrics: computeRadarMetrics(p1),
                            p2Metrics: computeRadarMetrics(p2),
                            p1Name: p1.player.webName,
                            p2Name: p2.player.webName
                        )
                        .frame(height: 220)
                        .padding(.vertical, 8)
                    }
                }
                .padding(16)
                .background(FottyTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // Head-to-Head Stats Comparison Cards
                VStack(spacing: 10) {
                    metricRow("FPL next-GW estimate", val1: decimal(p1.player.officialExpectedPointsNext), val2: decimal(p2.player.officialExpectedPointsNext), p1Better: (p1.player.officialExpectedPointsNext ?? 0) >= (p2.player.officialExpectedPointsNext ?? 0))
                    metricRow("Points per match", val1: p1.player.pointsPerGame, val2: p2.player.pointsPerGame, p1Better: (Double(p1.player.pointsPerGame) ?? 0) >= (Double(p2.player.pointsPerGame) ?? 0))
                    metricRow("xGI per 90", val1: decimal(p1.player.expectedGoalInvolvementsPer90), val2: decimal(p2.player.expectedGoalInvolvementsPer90), p1Better: (p1.player.expectedGoalInvolvementsPer90 ?? 0) >= (p2.player.expectedGoalInvolvementsPer90 ?? 0))
                    metricRow("Defensive contrib / 90", val1: decimal(p1.player.defensiveContributionPer90), val2: decimal(p2.player.defensiveContributionPer90), p1Better: (p1.player.defensiveContributionPer90 ?? 0) >= (p2.player.defensiveContributionPer90 ?? 0))
                    metricRow("Minutes", val1: p1.player.minutes.formatted(), val2: p2.player.minutes.formatted(), p1Better: p1.player.minutes >= p2.player.minutes)
                    metricRow("Selected by", val1: "\(p1.player.selectedByPercent)%", val2: "\(p2.player.selectedByPercent)%", p1Better: (Double(p1.player.selectedByPercent) ?? 0) >= (Double(p2.player.selectedByPercent) ?? 0))
                }
                .padding(16)
                .background(FottyTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                comparisonLayout {
                    evidenceCard(p1)
                    evidenceCard(p2)
                }
            } else {
                Text(viewModel.isLoading ? "Loading players…" : "Player data is not available yet. Pull down to refresh.")
                    .font(.fottyScaled(size: 13))
                    .foregroundStyle(FottyTheme.textSecondary)
                    .padding(24)
            }
        }
        .task(id: "\(viewModel.comparisonPlayer1ID ?? 0)-\(viewModel.comparisonPlayer2ID ?? 0)-\(viewModel.evidenceRevision)") {
            await loadSelectedSummaries()
        }
        .onDisappear { viewModel.cancelPlayerHistoryChecks() }
        .sheet(item: $selectingSlot) { slot in
            NavigationStack {
                List {
                    if comparisonSearchResults.isEmpty {
                        Text("No players match your search").foregroundStyle(FottyTheme.textSecondary)
                    }
                    ForEach(comparisonSearchResults) { score in
                        Button {
                            if slot == .first { viewModel.comparisonPlayer1ID = score.id }
                            else { viewModel.comparisonPlayer2ID = score.id }
                            selectingSlot = nil
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(score.player.webName).font(.headline).foregroundStyle(FottyTheme.textPrimary)
                                HStack(spacing: 5) {
                                    TeamIdentityLabel(
                                        teamName: score.team.name,
                                        badgeURL: score.team.badgeURL,
                                        badgeSize: 20,
                                        font: .subheadline,
                                        foregroundColor: FottyTheme.textSecondary
                                    )
                                    Text("· \(score.player.positionName) · \(score.player.formattedCost)")
                                        .font(.subheadline)
                                        .foregroundStyle(FottyTheme.textSecondary)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("fpl-comparison-result-\(score.id)")
                    }
                    if comparisonSearchResults.count == 60 {
                        Text("Showing the first 60 matches. Search by player or club to narrow the list.")
                            .font(.footnote).foregroundStyle(FottyTheme.textSecondary)
                    }
                }
                .searchable(text: $playerQuery, prompt: "Player or club name")
                .navigationTitle(slot == .first ? "Choose first player" : "Choose second player")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { selectingSlot = nil } } }
                .tint(FottyTheme.accentText)
            }
        }
    }

    private var comparisonSearchResults: [PlayerScore] {
        let query = playerQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(viewModel.playerScores.lazy.filter {
            query.isEmpty || "\($0.player.firstName) \($0.player.secondName) \($0.player.webName) \($0.team.name)".localizedStandardContains(query)
        }.prefix(60))
    }

    private func decimal(_ value: Double?) -> String {
        value?.formatted(.number.precision(.fractionLength(2))) ?? "Not supplied"
    }

    private func loadSelectedSummaries(forceRefresh: Bool = false) async {
        guard viewModel.playerScores.count >= 2 else { return }
        let first = viewModel.playerScores[min(player1Index, viewModel.playerScores.count - 1)].id
        let second = viewModel.playerScores[min(player2Index, viewModel.playerScores.count - 1)].id
        viewModel.cancelPlayerHistoryChecks(except: [first, second])
        async let firstSummary = viewModel.fetchElementSummary(playerID: first, forceRefresh: forceRefresh)
        async let secondSummary = viewModel.fetchElementSummary(playerID: second, forceRefresh: forceRefresh)
        _ = await (firstSummary, secondSummary)
    }

    private func evidenceCard(_ score: PlayerScore) -> some View {
        let history = viewModel.elementSummaries[score.id]?.history.suffix(5) ?? []
        return VStack(alignment: .leading, spacing: 7) {
            Text(score.player.webName.uppercased())
                .font(.caption.weight(.black))
                .foregroundStyle(FottyTheme.accentText)
            Text(setPieceSummary(score.player))
                .font(.caption2)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider().background(FottyTheme.border)
            Text(viewModel.playerHistoryStatus(playerID: score.id))
                .font(.caption2)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if history.isEmpty {
                Text(viewModel.elementSummaries[score.id] == nil ? "No recent history loaded." : "No recent appearances supplied.")
                    .font(.caption2)
                    .foregroundStyle(FottyTheme.textTertiary)
            } else {
                ForEach(Array(history), id: \.fixture) { match in
                    HStack {
                        Text("GW\(match.round)")
                        Spacer()
                        Text("\(match.minutes)m")
                        Text("\(match.totalPoints) pts").fontWeight(.bold)
                    }
                    .font(.caption2)
                    .foregroundStyle(FottyTheme.textSecondary)
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private func setPieceSummary(_ player: FPLPlayer) -> String {
        var roles = [String]()
        if let order = player.penaltiesOrder { roles.append("penalties #\(order)") }
        if let order = player.directFreekicksOrder { roles.append("direct free-kicks #\(order)") }
        if let order = player.cornersAndIndirectFreekicksOrder { roles.append("corners/indirect #\(order)") }
        return roles.isEmpty ? "No set-piece order supplied by FPL." : "Official set pieces: " + roles.joined(separator: ", ") + "."
    }
    
    private func computeRadarMetrics(_ score: PlayerScore) -> [Double] {
        // 5 Normalized dimensions [0.0 ... 1.0]
        let form = min(1.0, max(0.15, score.formScore / 100.0))
        let ict = min(1.0, max(0.15, score.ictScore / 100.0))
        let composite = min(1.0, max(0.15, score.compositeScore / 100.0))
        let value = min(1.0, max(0.15, score.valueScore / 100.0))
        let attacking = min(1.0, max(0.15, score.xGIScore / 100.0))
        return [form, ict, composite, value, attacking]
    }

    private func accessibleStrengths(first: PlayerScore, second: PlayerScore) -> some View {
        let labels = ["Form", "ICT Index", "Composite", "Value/£", "xG Threat"]
        let firstMetrics = computeRadarMetrics(first)
        let secondMetrics = computeRadarMetrics(second)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Relative model scores, on the chart’s 0–100 scale.")
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.textSecondary)
            ForEach(labels.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    Text(labels[index]).font(FottyTheme.typeModuleTitle)
                    Text("\(first.player.webName): \(Int((firstMetrics[index] * 100).rounded()))")
                    Text("\(second.player.webName): \(Int((secondMetrics[index] * 100).rounded()))")
                }
                .font(FottyTheme.typeBody)
                .foregroundStyle(FottyTheme.textPrimary)
                .accessibilityElement(children: .combine)
            }
        }
    }
    
    @ViewBuilder
    private func metricRow(_ label: String, val1: String, val2: String, p1Better: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
          if dynamicTypeSize.isAccessibilitySize {
            Text(label)
                .font(FottyTheme.typeModuleTitle)
                .foregroundStyle(FottyTheme.textSecondary)
          }
          HStack(alignment: .top) {
            Text(val1)
                .font(.fottyScaled(size: 12, weight: .bold))
                .foregroundStyle(p1Better ? FottyTheme.success : FottyTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if !dynamicTypeSize.isAccessibilitySize {
              Text(label)
                .font(.fottyScaled(size: 11, weight: .bold))
                .foregroundStyle(FottyTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            Text(val2)
                .font(.fottyScaled(size: 12, weight: .bold))
                .foregroundStyle(!p1Better ? FottyTheme.accentText : FottyTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .trailing)
          }
        }
        .padding(10)
        .background(FottyTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), first player \(val1), second player \(val2)")
    }
}

// MARK: - Radar Chart Canvas

private struct RadarChartCanvas: View {
    let p1Metrics: [Double]
    let p2Metrics: [Double]
    let p1Name: String
    let p2Name: String
    
    private let axisLabels = ["Form", "ICT Index", "Composite", "Value/£", "xG Threat"]
    private var accessibilitySummary: String {
        let comparisons = axisLabels.indices.compactMap { index -> String? in
            guard p1Metrics.indices.contains(index), p2Metrics.indices.contains(index) else { return nil }
            let first = Int((p1Metrics[index] * 100).rounded())
            let second = Int((p2Metrics[index] * 100).rounded())
            return "\(axisLabels[index]): \(p1Name) \(first), \(p2Name) \(second)"
        }
        return "Fotty model relative strengths, chart scale 0 to 100. " + comparisons.joined(separator: ". ")
    }
    
    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = min(geometry.size.width, geometry.size.height) * 0.38
            let count = axisLabels.count
            
            ZStack {
                // Background Spiderweb Grid
                ForEach(1...3, id: \.self) { ring in
                    let ringRadius = radius * (Double(ring) / 3.0)
                    PolygonShape(sides: count, radius: ringRadius, center: center)
                        .stroke(FottyTheme.surfaceElevated, lineWidth: 1)
                }
                
                // Radial Axis Lines
                ForEach(0..<count, id: \.self) { index in
                    let angle = angleFor(index: index, total: count)
                    let endPoint = CGPoint(
                        x: center.x + CGFloat(cos(angle)) * radius,
                        y: center.y + CGFloat(sin(angle)) * radius
                    )
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: endPoint)
                    }
                    .stroke(FottyTheme.surfaceElevated.opacity(0.8), lineWidth: 1)
                    
                    // Axis Label
                    let labelPos = CGPoint(
                        x: center.x + CGFloat(cos(angle)) * (radius + 20),
                        y: center.y + CGFloat(sin(angle)) * (radius + 14)
                    )
                    Text(axisLabels[index])
                        .font(.fottyScaled(size: 9, weight: .bold))
                        .foregroundStyle(FottyTheme.textSecondary)
                        .position(labelPos)
                }
                
                // Player 1 Polygon (Green)
                RadarPolygon(metrics: p1Metrics, radius: radius, center: center)
                    .fill(FottyTheme.success.opacity(0.35))
                RadarPolygon(metrics: p1Metrics, radius: radius, center: center)
                    .stroke(FottyTheme.success, lineWidth: 2)
                
                // Player 2 Polygon (Orange/LiveAccent)
                RadarPolygon(metrics: p2Metrics, radius: radius, center: center)
                    .fill(FottyTheme.liveAccent.opacity(0.35))
                RadarPolygon(metrics: p2Metrics, radius: radius, center: center)
                    .stroke(FottyTheme.liveAccent, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }
    
    private func angleFor(index: Int, total: Int) -> Double {
        return (Double(index) * 2 * .pi / Double(total)) - (.pi / 2)
    }
}

private struct PolygonShape: Shape {
    let sides: Int
    let radius: CGFloat
    let center: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard sides > 2 else { return path }
        for i in 0..<sides {
            let angle = (Double(i) * 2 * .pi / Double(sides)) - (.pi / 2)
            let pt = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}

private struct RadarPolygon: Shape {
    let metrics: [Double]
    let radius: CGFloat
    let center: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard metrics.count > 2 else { return path }
        for i in 0..<metrics.count {
            let angle = (Double(i) * 2 * .pi / Double(metrics.count)) - (.pi / 2)
            let val = max(0.05, min(1.0, metrics[i]))
            let pt = CGPoint(
                x: center.x + CGFloat(cos(angle)) * (radius * CGFloat(val)),
                y: center.y + CGFloat(sin(angle)) * (radius * CGFloat(val))
            )
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}
