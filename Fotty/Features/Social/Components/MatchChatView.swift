import SwiftUI
import SwiftData

struct MatchChatView: View {
    let match: FootballMatch
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var socialCloudStore: SocialCloudStore
    
    @Query private var arenaMessages: [ArenaMessage]
    @Query(sort: \SocialSafetyActionItem.createdAt, order: .reverse) private var safetyActions: [SocialSafetyActionItem]
    @State private var messageText: String = ""
    @State private var selectedUserForProfile: (id: String, name: String, username: String, symbol: String)? = nil
    @State private var showStadiumCard = false
    @State private var selectedDirectRecipientID: String? = nil
    @State private var showDirectChat = false
    @State private var moderationStatusMessage: String?
    
    init(match: FootballMatch) {
        self.match = match
        let matchID = match.id
        _arenaMessages = Query(
            filter: #Predicate<ArenaMessage> { $0.matchID == matchID },
            sort: \ArenaMessage.createdAt,
            order: .forward
        )
    }
    
    private var blockedSenderIDs: Set<String> {
        Set(
            safetyActions
                .filter { $0.action == SocialSafetyAction.block.rawValue }
                .map(\.targetAccountID)
        )
    }
    
    private var visibleArenaMessages: [ArenaMessage] {
        arenaMessages.filter { !blockedSenderIDs.contains($0.senderID) }
    }
    
    var body: some View {
        ZStack {
            FottyTheme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                MatchChatHUD(match: match)
                    .padding(.top, 8)

                Label("Arena messages are saved only on this device", systemImage: "iphone")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FottyTheme.textSecondary)
                    .padding(.vertical, 6)
                
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: FottyTheme.spacingMD) {
                            ForEach(visibleArenaMessages) { message in
                                ArenaMessageRow(
                                    message: message,
                                    onAvatarTap: {
                                        selectedUserForProfile = (
                                            id: message.senderID,
                                            name: message.senderDisplayName,
                                            username: message.senderUsername,
                                            symbol: message.senderAvatarSymbol
                                        )
                                        showStadiumCard = true
                                    },
                                    onReportTap: {
                                        reportArenaMessage(message)
                                    },
                                    onBlockTap: {
                                        blockArenaUser(
                                            senderID: message.senderID,
                                            username: message.senderUsername
                                        )
                                    }
                                )
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        .padding(FottyTheme.spacingMD)
                    }
                    .onChange(of: visibleArenaMessages.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(visibleArenaMessages.last?.id, anchor: .bottom)
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation {
                                proxy.scrollTo(visibleArenaMessages.last?.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                Spacer(minLength: 0)
                
                FanBlastBar(
                    messageText: $messageText,
                    onSend: sendMessage,
                    onReaction: sendReaction,
                    allowsInteraction: true
                )
            }
        }
        .navigationTitle("The Arena")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .sheet(isPresented: $showStadiumCard) {
            Group {
                if let user = selectedUserForProfile {
                    StadiumCardView(
                        userID: user.id,
                        displayName: user.name,
                        username: user.username,
                        avatarSymbol: user.symbol
                    ) {
                        selectedDirectRecipientID = user.id
                        showDirectChat = true
                    } onBlockTap: {
                        blockArenaUser(senderID: user.id, username: user.username)
                    }
                }
            }
            .fottyStandardSheetChrome()
        }
        .sheet(isPresented: $showDirectChat) {
            Group {
                if let recipientID = selectedDirectRecipientID {
                    NavigationStack {
                        DirectChatView(recipientID: recipientID)
                            .environmentObject(socialCloudStore)
                    }
                }
            }
            .fottyStandardSheetChrome()
        }
        .alert(
            "Safety Action",
            isPresented: Binding(
                get: { moderationStatusMessage != nil },
                set: { if !$0 { moderationStatusMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                moderationStatusMessage = nil
            }
        } message: {
            Text(moderationStatusMessage ?? "")
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let text = messageText
        messageText = ""
        Task {
            await socialCloudStore.sendArenaMessage(matchID: match.id, content: text, type: "text", modelContext: modelContext)
        }
    }
    
    private func sendReaction(_ emoji: String) {
        Task {
            await socialCloudStore.sendArenaMessage(matchID: match.id, content: emoji, type: "reaction", modelContext: modelContext)
        }
    }
    
    private func reportArenaMessage(_ message: ArenaMessage) {
        recordArenaSafetyAction(
            action: .report,
            targetAccountID: "\(message.senderID)|\(message.id)",
            actorAccountID: message.senderID,
            title: "Message reported",
            reason: "Reported Arena message from @\(message.senderUsername)."
        )
    }
    
    private func blockArenaUser(senderID: String, username: String) {
        recordArenaSafetyAction(
            action: .block,
            targetAccountID: senderID,
            actorAccountID: senderID,
            title: "User blocked",
            reason: "Blocked @\(username) in Arena chat."
        )
    }
    
    private func recordArenaSafetyAction(
        action: SocialSafetyAction,
        targetAccountID: String,
        actorAccountID: String,
        title: String,
        reason: String
    ) {
        let existing = safetyActions.contains {
            $0.action == action.rawValue && $0.targetAccountID == targetAccountID
        }
        guard !existing else {
            moderationStatusMessage = "This action was already recorded."
            return
        }
        
        modelContext.insert(
            SocialSafetyActionItem(
                action: action.rawValue,
                targetAccountID: targetAccountID,
                reason: reason
            )
        )
        
        modelContext.insert(
            SocialNotificationItem(
                type: "safety",
                title: title,
                body: reason,
                actorAccountID: actorAccountID
            )
        )
        
        do {
            try modelContext.save()
            moderationStatusMessage = reason
            HapticManager.notification(action == .report ? .warning : .success)
        } catch {
            moderationStatusMessage = "Could not save safety action: \(error.localizedDescription)"
        }
    }
}

struct MatchChatHUD: View {
    let match: FootballMatch
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 24) {
                teamBadge(match.homeTeam)
                VStack(spacing: 2) {
                    Text("\(match.score.fullTime?.home ?? 0) - \(match.score.fullTime?.away ?? 0)")
                        .font(.system(size: 32, weight: .black, design: .monospaced))
                        .foregroundStyle(FottyTheme.accentText)
                    Text(match.status.displayText)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.green)
                }
                teamBadge(match.awayTeam)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(FottyTheme.surfaceElevated.opacity(0.8))
                    .overlay { RoundedRectangle(cornerRadius: 24).stroke(FottyTheme.accent.opacity(0.2), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
            }
        }
    }
    private func teamBadge(_ team: FootballTeam) -> some View {
        VStack(spacing: 4) {
            if let badgeUrl = team.crest {
                AsyncImage(url: URL(string: badgeUrl)) { image in image.resizable().aspectRatio(contentMode: .fit).frame(width: 48, height: 48) } placeholder: { Circle().fill(FottyTheme.surface).frame(width: 48, height: 48) }
            }
            Text(team.displayName.prefix(3).uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(FottyTheme.textSecondary)
        }
    }
}

struct ArenaMessageRow: View {
    let message: ArenaMessage
    let onAvatarTap: () -> Void
    let onReportTap: () -> Void
    let onBlockTap: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                onAvatarTap()
            } label: {
                Image(systemName: message.senderAvatarSymbol)
                    .font(.system(size: 18))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(FottyTheme.surfaceElevated))
                    .foregroundStyle(FottyTheme.accentText)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.senderDisplayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(FottyTheme.textPrimary)
                    Text("@\(message.senderUsername)")
                        .font(.system(size: 12))
                        .foregroundStyle(FottyTheme.textSecondary)
                    Spacer()
                    Text(message.createdAt, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(FottyTheme.textSecondary.opacity(0.5))
                    Menu {
                        Button(role: .destructive) {
                            onReportTap()
                        } label: {
                            Label("Report Content", systemImage: "flag")
                        }
                        
                        Button(role: .destructive) {
                            onBlockTap()
                        } label: {
                            Label("Block User", systemImage: "nosign")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(FottyTheme.textSecondary)
                            .padding(6)
                            .background(Circle().fill(FottyTheme.surfaceElevated))
                    }
                }
                
                if message.type == "reaction" {
                    Text(message.content)
                        .font(.system(size: 40))
                } else {
                    Text(message.content)
                        .font(.system(size: 15))
                        .foregroundStyle(FottyTheme.textPrimary)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(FottyTheme.surfaceElevated.opacity(0.5))
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
