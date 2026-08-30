import SwiftUI

public struct FPLPriceAlertsView: View {
    let alerts: [PriceChangeAlert]
    @State private var selectedFilter: AlertFilter = .all

    public enum AlertFilter: String, CaseIterable, Identifiable {
        case all = "All projections"
        case rising = "Projected up"
        case falling = "Projected down"
        public var id: String { rawValue }
    }

    public init(alerts: [PriceChangeAlert]) {
        self.alerts = alerts
    }

    public var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            header
            if filteredAlerts.isEmpty {
                emptyState
            } else {
                ForEach(filteredAlerts) { alert in
                    alertCard(alert)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Official price projections", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline.weight(.black))
                    .foregroundStyle(FottyTheme.textPrimary)
                Spacer()
                Text("FPL FEED")
                    .font(.fottyScaled(size: 8, weight: .black))
                    .foregroundStyle(FottyTheme.accentText)
            }
            Text("FPL's price signals suggest a direction, not a guaranteed change tonight. Don't make a transfer on this signal alone.")
                .font(.caption)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 7) {
                ForEach(AlertFilter.allCases) { filter in
                    let selected = selectedFilter == filter
                    Button(filter.rawValue) { selectedFilter = filter }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selected ? FottyTheme.textOnAccent : FottyTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(selected ? FottyTheme.accent : FottyTheme.surfaceElevated)
                        .clipShape(Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(15)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "minus.circle")
                .font(.title)
                .foregroundStyle(FottyTheme.textTertiary)
            Text("No official projection in this category")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(FottyTheme.textPrimary)
            Text("This means the current FPL snapshot did not return a qualifying projection. It does not guarantee that prices will remain unchanged.")
                .font(.caption)
                .foregroundStyle(FottyTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func alertCard(_ alert: PriceChangeAlert) -> some View {
        let color = alert.isRising ? FottyTheme.success : FottyTheme.error
        let magnitude = min(100, max(0, abs(alert.officialProjectedPercent)))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                FPLOfficialShirtImageView(
                    teamCode: alert.team.code,
                    isGoalkeeper: alert.player.elementType == 1,
                    size: 38
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.player.webName)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(FottyTheme.textPrimary)
                    Text("\(alert.team.shortName) • \(alert.player.positionName) • \(alert.player.formattedCost)")
                        .font(.caption2)
                        .foregroundStyle(FottyTheme.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(alert.officialProjectedPercent.formatted(.number.precision(.fractionLength(1))))%")
                        .font(.title3.weight(.black))
                        .foregroundStyle(color)
                    Text("projected threshold")
                        .font(.fottyScaled(size: 8, weight: .bold))
                        .foregroundStyle(FottyTheme.textTertiary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(FottyTheme.surfaceElevated)
                    Capsule().fill(color).frame(width: max(4, proxy.size.width * magnitude / 100))
                }
            }
            .frame(height: 6)

            HStack {
                Label(alert.isRising ? "Upward projection" : "Downward projection", systemImage: alert.isRising ? "arrow.up.right" : "arrow.down.right")
                Spacer()
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(FottyTheme.textSecondary)

            DisclosureGroup("FPL signal details") {
                Text("Raw FPL likelihood index: \(alert.officialLikelihood). Projection offset: \(alert.projectionOffset). These are feed indicators, not a probability or a confirmed change date.")
                    .font(.caption)
                    .foregroundStyle(FottyTheme.textSecondary)
            }
            .font(FottyTheme.typeMeta)

            Text("Net event transfers: \(alert.netTransfers >= 0 ? "+" : "")\(alert.netTransfers.formatted())")
                .font(.caption2)
                .foregroundStyle(FottyTheme.textTertiary)
        }
        .padding(14)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.2), lineWidth: 1))
    }

    private var filteredAlerts: [PriceChangeAlert] {
        switch selectedFilter {
        case .all: return alerts
        case .rising: return alerts.filter(\.isRising)
        case .falling: return alerts.filter { !$0.isRising }
        }
    }
}
