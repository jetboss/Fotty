import SwiftUI

struct YouTubeHighlightsView: View {
    let query: String

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MATCH HIGHLIGHTS")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(FottyTheme.textPrimary)
                    Text("Curated clips after full-time")
                        .font(.system(size: 10))
                        .foregroundColor(FottyTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "play.tv.fill")
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Highlights are not ready yet")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(FottyTheme.textPrimary)
                Text(
                    trimmedQuery.isEmpty
                        ? "Fotty will surface official clips here once broadcasters publish post-match video."
                        : "Fotty will surface clips for \(trimmedQuery) here once broadcasters publish post-match video."
                )
                .font(.system(size: 12))
                .foregroundColor(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(FottyTheme.surfaceSubtle)
            .cornerRadius(12)
        }
        .padding(16)
        .background(FottyTheme.surfaceElevated)
        .cornerRadius(16)
    }
}
