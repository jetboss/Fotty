import SwiftUI

struct SocialActivityRow: View {
    let item: SocialActivityItem
    let replies: [SocialActivityItem]
    let reactionSummary: [SocialReactionSummaryItem]
    let isExpanded: Bool
    @Binding var replyDraft: String
    
    let onReaction: (String) -> Void
    let onToggleThread: () -> Void
    let onPostReply: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerSection
            
            Text(item.content)
                .font(.system(size: 13))
                .foregroundStyle(FottyTheme.textPrimary)
                .multilineTextAlignment(.leading)

            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 10))
                .foregroundStyle(FottyTheme.textTertiary)
            
            if !reactionSummary.isEmpty {
                reactionPills
            }
            
            actionButtons
            
            if isExpanded {
                threadSection
            }
        }
        .padding(FottyTheme.spacingMD)
        .cardStyle()
        .padding(.horizontal, FottyTheme.spacingMD)
    }
    
    private var headerSection: some View {
        HStack(spacing: 8) {
            Text(item.actorDisplayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FottyTheme.textPrimary)
            Text("@\(item.actorUsername)")
                .font(.system(size: 11))
                .foregroundStyle(FottyTheme.textSecondary)
            Spacer()
            
            Menu {
                Button(role: .destructive, action: onReport) {
                    Label("Report Content", systemImage: "flag")
                }
                
                Button(role: .destructive, action: onBlock) {
                    Label("Block User", systemImage: "nosign")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundStyle(FottyTheme.textTertiary)
                    .padding(4)
            }
        }
    }
    
    private var reactionPills: some View {
        HStack(spacing: 6) {
            ForEach(reactionSummary) { pill in
                Text("\(pill.emoji) \(pill.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(FottyTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(FottyTheme.surfaceElevated))
            }
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 8) {
            quickReactionButton("⚽")
            quickReactionButton("🔥")
            quickReactionButton("👏")
            
            Button(isExpanded ? "Hide Thread" : "Reply • \(replies.count)") {
                onToggleThread()
            }
            .pillButtonStyle(accent: false)
        }
    }
    
    private func quickReactionButton(_ emoji: String) -> some View {
        Button {
            onReaction(emoji)
        } label: {
            Text(emoji)
                .font(.system(size: 14))
                .padding(6)
                .background(Circle().fill(FottyTheme.surfaceElevated))
        }
    }
    
    private var threadSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if replies.isEmpty {
                Text("No replies yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(FottyTheme.textSecondary)
            } else {
                ForEach(Array(replies.prefix(4))) { reply in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(reply.actorDisplayName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(FottyTheme.textPrimary)
                            Text("@\(reply.actorUsername)")
                                .font(.system(size: 10))
                                .foregroundStyle(FottyTheme.textSecondary)
                        }
                        Text(reply.content)
                            .font(.system(size: 11))
                            .foregroundStyle(FottyTheme.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(FottyTheme.surfaceElevated)
                    )
                }
            }
            
            HStack(spacing: 8) {
                TextField("Write a reply...", text: $replyDraft)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(FottyTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Button("Post") {
                    onPostReply()
                }
                .disabled(replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(FottyTheme.accentText)
            }
        }
        .padding(.top, 4)
    }
}
