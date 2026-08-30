import SwiftUI
import SwiftData

struct SocialInboxView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var socialCloudStore: SocialCloudStore
    @Query(sort: \SocialConversation.lastMessageTimestamp, order: .reverse) private var conversations: [SocialConversation]
    @State private var selectedConversation: SocialConversation? = nil
    @State private var showChat = false
    
    var body: some View {
        VStack(spacing: 0) {
            if conversations.isEmpty {
                socialEmptyStateCard(text: "No on-device private rooms yet. Open a fan profile in an Arena to start one.")
                    .padding(.horizontal, FottyTheme.spacingMD)
            } else {
                VStack(spacing: FottyTheme.spacingSM) {
                    ForEach(conversations) { conversation in
                        Button { selectedConversation = conversation; showChat = true } label: { conversationRow(conversation) }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, FottyTheme.spacingMD)
            }
        }
        .sheet(isPresented: $showChat) {
            Group {
                if let conversation = selectedConversation {
                    let localID = socialCloudStore.localAccountID(in: modelContext)
                    let otherParticipantID = conversation.participantIDs.first(where: { $0 != localID }) ?? ""
                    NavigationStack {
                        DirectChatView(recipientID: otherParticipantID)
                            .environmentObject(socialCloudStore)
                    }
                }
            }
            .fottyStandardSheetChrome()
        }
    }
    
    private func conversationRow(_ conversation: SocialConversation) -> some View {
        let localID = socialCloudStore.localAccountID(in: modelContext)
        let otherParticipantID = conversation.participantIDs.first(where: { $0 != localID }) ?? ""
        let otherName = conversation.participantNames[otherParticipantID] ?? "Fan"
        return HStack(spacing: 12) {
            Circle().fill(FottyTheme.surfaceElevated).frame(width: 50, height: 50).overlay(Image(systemName: "person.fill").foregroundStyle(FottyTheme.accentText))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(otherName).font(.system(size: 16, weight: .bold)).foregroundStyle(FottyTheme.textPrimary)
                    Spacer()
                    Text(conversation.lastMessageTimestamp, style: .time).font(.system(size: 12)).foregroundStyle(FottyTheme.textSecondary)
                }
                Text(conversation.lastMessageContent).font(.system(size: 14)).foregroundStyle(FottyTheme.textSecondary).lineLimit(1)
            }
            if conversation.unreadCount > 0 { Circle().fill(FottyTheme.accent).frame(width: 10, height: 10) }
        }.padding(FottyTheme.spacingMD).cardStyle()
    }
    
    private func socialEmptyStateCard(text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "message.and.waveform.fill").font(.system(size: 32)).foregroundStyle(FottyTheme.textTertiary)
            Text(text).font(.system(size: 14)).foregroundStyle(FottyTheme.textSecondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(FottyTheme.spacingXL).cardStyle()
    }
}

struct DirectChatView: View {
    let recipientID: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var socialCloudStore: SocialCloudStore
    @Query private var directMessages: [DirectMessage]
    @Query(sort: \SocialSafetyActionItem.createdAt, order: .reverse) private var safetyActions: [SocialSafetyActionItem]
    @State private var messageText: String = ""
    @State private var moderationStatusMessage: String?
    
    init(recipientID: String) {
        self.recipientID = recipientID
        _directMessages = Query(
            filter: #Predicate<DirectMessage> {
                $0.recipientID == recipientID || $0.senderID == recipientID
            },
            sort: \DirectMessage.createdAt,
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
    
    private var visibleDirectMessages: [DirectMessage] {
        directMessages.filter { !blockedSenderIDs.contains($0.senderID) }
    }
    
    var body: some View {
        ZStack {
            FottyTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(visibleDirectMessages) { msg in
                                dmRow(msg)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: visibleDirectMessages.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(visibleDirectMessages.last?.id, anchor: .bottom)
                        }
                    }
                }
                Spacer(minLength: 0)
                dmInputBar
            }
        }
        .navigationTitle("Private Room")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            Text("Saved only on this device")
                .font(.caption.weight(.semibold))
                .foregroundStyle(FottyTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(FottyTheme.surface)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
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
    
    private func dmRow(_ msg: DirectMessage) -> some View {
        let isFromMe = msg.senderID != recipientID
        
        return HStack(alignment: .bottom, spacing: 8) {
            if isFromMe {
                Spacer(minLength: 44)
            }
            
            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
                Text(msg.content)
                    .font(.system(size: 15))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        isFromMe
                        ? AnyShapeStyle(FottyTheme.accentGradient)
                        : AnyShapeStyle(FottyTheme.surfaceElevated)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(isFromMe ? FottyTheme.textOnAccent : FottyTheme.textPrimary)
                    .frame(maxWidth: 320, alignment: isFromMe ? .trailing : .leading)
                
                HStack(spacing: 6) {
                    Text(msg.createdAt, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(FottyTheme.textSecondary.opacity(0.6))
                    
                    Menu {
                        Button(role: .destructive) {
                            reportDirectMessage(msg)
                        } label: {
                            Label("Report Content", systemImage: "flag")
                        }
                        
                        if !isFromMe {
                            Button(role: .destructive) {
                                blockDirectSender(msg)
                            } label: {
                                Label("Block User", systemImage: "nosign")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(FottyTheme.textSecondary)
                            .padding(5)
                            .background(Circle().fill(FottyTheme.surfaceElevated))
                    }
                }
            }
            
            if !isFromMe {
                Spacer(minLength: 44)
            }
        }
    }
    
    private var dmInputBar: some View {
        HStack(spacing: 12) {
            TextField("Type a message...", text: $messageText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(FottyTheme.surfaceElevated))
                .submitLabel(.send)
                .onSubmit(sendDM)
            Button(action: sendDM) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(FottyTheme.textOnAccent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(FottyTheme.accent))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
    
    private func sendDM() {
        guard !messageText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let text = messageText
        messageText = ""
        Task {
            await socialCloudStore.sendDirectMessage(
                recipientID: recipientID,
                content: text,
                modelContext: modelContext
            )
        }
    }
    
    private func reportDirectMessage(_ message: DirectMessage) {
        recordDirectSafetyAction(
            action: .report,
            targetAccountID: "\(message.senderID)|\(message.id)",
            actorAccountID: message.senderID,
            title: "Message reported",
            reason: "Reported private-room content."
        )
    }
    
    private func blockDirectSender(_ message: DirectMessage) {
        recordDirectSafetyAction(
            action: .block,
            targetAccountID: message.senderID,
            actorAccountID: message.senderID,
            title: "User blocked",
            reason: "Blocked this user in private room."
        )
    }
    
    private func recordDirectSafetyAction(
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
