import SwiftUI

public struct FPLCaptainPickerView: View {
    let recommendations: [CaptainRecommendation]

    public init(recommendations: [CaptainRecommendation]) {
        self.recommendations = recommendations
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ranked by Fotty's overall player rating, not just predicted points. The points estimate is shown separately and isn't doubled for captaincy.")
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.textSecondary)
            if recommendations.isEmpty {
                Text("No captain recommendations yet. Pull down to refresh your squad.")
                    .font(FottyTheme.typeBody)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .padding()
            } else {
                ForEach(Array(recommendations.enumerated()), id: \.element.id) { index, recommendation in
                    captainCard(recommendation, rank: index + 1)
                }
            }
        }
    }

    private func captainCard(_ rec: CaptainRecommendation, rank: Int) -> some View {
        let isTop = rank == 1
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rec.player.player.webName)
                        .font(FottyTheme.typeSectionTitle)
                        .foregroundStyle(FottyTheme.textPrimary)
                    Text("\(rec.player.team.shortName) · \(rec.player.player.positionName) · \(rec.player.player.selectedByPercent)% owned")
                        .font(FottyTheme.typeMeta)
                        .foregroundStyle(FottyTheme.textSecondary)
                }
                Spacer(minLength: 8)
                Text("#\(rank)")
                    .font(.title2.bold())
                    .foregroundStyle(isTop ? FottyTheme.accentText : FottyTheme.textSecondary)
                    .accessibilityLabel("Rank \(rank)")
            }
            Text("Fotty rating: \(Int(rec.player.compositeScore.rounded()))/100")
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.textPrimary)
            Text("\(rec.player.player.officialExpectedPointsNext == nil ? "Fotty modeled estimate" : "FPL next-gameweek estimate"): \(rec.expectedPoints.formatted(.number.precision(.fractionLength(1)))) points")
                .font(FottyTheme.typeBody)
                .foregroundStyle(FottyTheme.accentText)
                .fixedSize(horizontal: false, vertical: true)
            Text(rec.reason)
                .font(FottyTheme.typeMeta)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isTop ? FottyTheme.accent.opacity(0.08) : FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(isTop ? FottyTheme.accent.opacity(0.4) : FottyTheme.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fpl-captain-card-\(rank)")
    }
}
