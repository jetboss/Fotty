import SwiftUI

struct CatalogRefreshNotice: View {
    let message: String
    var checkedAt: Date?
    var checkLabel = "Broadcast listings last checked"
    var isRefreshing = false
    let onRefresh: () async -> Void
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(FottyTheme.typeMeta)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if checkedAt != nil {
                    Button { showsDetails.toggle() } label: {
                        Image(systemName: "info.circle")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Update details")
                    .accessibilityValue(showsDetails ? "Expanded" : "Collapsed")
                    .accessibilityIdentifier("catalog-update-details")
                }
                Button {
                    Task { await onRefresh() }
                } label: {
                    Group {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                                .tint(FottyTheme.textSecondary)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(isRefreshing ? "Checking listings" : "Retry refresh")
                .accessibilityIdentifier("catalog-retry-refresh")
                .disabled(isRefreshing)
            }
            if showsDetails, let checkedAt {
                Text("\(checkLabel): \(checkedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(FottyTheme.typeCaption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("catalog-check-time")
            }
        }
        .buttonStyle(FottyPressButtonStyle())
        .foregroundStyle(FottyTheme.textSecondary)
        .padding(.leading, 10)
        .background(FottyTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: FottyTheme.radiusSM))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catalog-refresh-notice")
    }
}

struct FootballFixtureRefreshProgress: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).accessibilityHidden(true)
            Text("Refreshing fixtures…")
        }
        .font(FottyTheme.typeMeta)
        .foregroundStyle(FottyTheme.textSecondary)
        .accessibilityElement(children: .combine)
    }
}
