import SwiftUI
import SwiftData

struct SocialFollowingView: View {
    @Binding var composerText: String
    @Binding var composerCategory: String
    let composerCategories: [String]
    let rootFeedItems: [SocialActivityItem]
    let expandedThreadIDs: Set<String>
    @Binding var replyDraftByActivityID: [String: String]
    
    let onPostActivity: () -> Void
    let onQuickReaction: (String, String) -> Void
    let onToggleThread: (String) -> Void
    let onPostReply: (String) -> Void
    let onReport: (SocialActivityItem) -> Void
    let onBlock: (SocialActivityItem) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: FottyTheme.spacingLG) {
            activityComposerSection
            activityFeedSection
        }
    }
    
    private var activityComposerSection: some View {
        VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
            SectionHeader(
                title: "Activity Feed",
                subtitle: "Post updates and reactions for your network"
            )

            VStack(alignment: .leading, spacing: 10) {
                TextField("Share a quick update...", text: $composerText, axis: .vertical)
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.sentences)

                HStack {
                    Picker("Category", selection: $composerCategory) {
                        ForEach(composerCategories, id: \.self) { category in
                            Text(category.capitalized).tag(category)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()

                    Button("Post") {
                        onPostActivity()
                    }
                    .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .pillButtonStyle(accent: true)
                }
            }
            .padding(FottyTheme.spacingMD)
            .cardStyle()
            .padding(.horizontal, FottyTheme.spacingMD)
        }
    }

    private var activityFeedSection: some View {
        VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
            if rootFeedItems.isEmpty {
                socialEmptyStateCard(text: "No feed activity yet. Follow accounts and post updates to get started.")
                    .padding(.horizontal, FottyTheme.spacingMD)
            } else {
                VStack(spacing: FottyTheme.spacingSM) {
                    ForEach(Array(rootFeedItems.prefix(20))) { item in
                        SocialActivityRow(
                            item: item,
                            replies: [], // Needs to be passed or resolved
                            reactionSummary: [], // Needs to be passed or resolved
                            isExpanded: expandedThreadIDs.contains(item.id),
                            replyDraft: Binding(
                                get: { replyDraftByActivityID[item.id] ?? "" },
                                set: { replyDraftByActivityID[item.id] = $0 }
                            ),
                            onReaction: { emoji in
                                onQuickReaction(emoji, item.id)
                            },
                            onToggleThread: {
                                onToggleThread(item.id)
                            },
                            onPostReply: {
                                onPostReply(item.id)
                            },
                            onReport: {
                                onReport(item)
                            },
                            onBlock: {
                                onBlock(item)
                            }
                        )
                    }
                }
            }
        }
    }
    
    private func socialEmptyStateCard(text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 32))
                .foregroundStyle(FottyTheme.textTertiary)
            
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(FottyTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(FottyTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
