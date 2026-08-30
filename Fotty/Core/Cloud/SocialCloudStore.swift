import Foundation
import Combine
import SwiftData

/// Local-first social persistence. Cloud accounts and PocketBase sync are retired;
/// this environment object owns only the on-device messaging operations.
@MainActor
final class SocialCloudStore: ObservableObject {
    @Published private(set) var persistenceErrorMessage: String?

    func localAccountID(in modelContext: ModelContext) -> String {
        localProfile(in: modelContext)?.id ?? "local-profile"
    }

    func sendArenaMessage(matchID: Int, content: String, type: String, modelContext: ModelContext) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let profile = localProfile(in: modelContext)
        modelContext.insert(
            ArenaMessage(
                matchID: matchID,
                senderID: profile?.id ?? "local-profile",
                senderDisplayName: nonEmpty(profile?.displayName) ?? "Fan",
                senderUsername: nonEmpty(profile?.username) ?? "fan",
                senderAvatarSymbol: profile?.avatarSymbol ?? "person.crop.circle.fill",
                content: trimmed,
                type: type,
                createdAt: Date()
            )
        )
        save(modelContext, operation: "save the Arena message")
    }

    func sendArenaMessage(matchID: String, content: String, type: String, modelContext: ModelContext) async {
        await sendArenaMessage(
            matchID: stableIntegerID(for: matchID),
            content: content,
            type: type,
            modelContext: modelContext
        )
    }

    func sendDirectMessage(recipientID: String, content: String, modelContext: ModelContext) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let profile = localProfile(in: modelContext)
        let senderID = profile?.id ?? "local-profile"
        let conversationID = [senderID, recipientID].sorted().joined(separator: "_")
        let sentAt = Date()
        modelContext.insert(
            DirectMessage(
                conversationID: conversationID,
                senderID: senderID,
                recipientID: recipientID,
                content: trimmed,
                isRead: true,
                createdAt: sentAt
            )
        )

        let descriptor = FetchDescriptor<SocialConversation>(
            predicate: #Predicate { $0.id == conversationID }
        )
        if let conversation = try? modelContext.fetch(descriptor).first {
            conversation.lastMessageContent = trimmed
            conversation.lastMessageTimestamp = sentAt
            conversation.unreadCount = 0
        } else {
            let accountDescriptor = FetchDescriptor<SocialAccount>(
                predicate: #Predicate { $0.id == recipientID }
            )
            let recipientName = (try? modelContext.fetch(accountDescriptor).first?.displayName) ?? "Fan"
            modelContext.insert(
                SocialConversation(
                    id: conversationID,
                    participantIDs: [senderID, recipientID],
                    participantNames: [
                        senderID: nonEmpty(profile?.displayName) ?? "You",
                        recipientID: recipientName
                    ],
                    lastMessageContent: trimmed,
                    lastMessageTimestamp: sentAt,
                    unreadCount: 0
                )
            )
        }
        save(modelContext, operation: "save the direct message")
    }

    private func localProfile(in modelContext: ModelContext) -> UserProfile? {
        let descriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])
        guard let profiles = try? modelContext.fetch(descriptor) else { return nil }
        return profiles.first(where: { $0.id == "local-profile" }) ?? profiles.first
    }

    private func save(_ modelContext: ModelContext, operation: String) {
        do {
            try modelContext.save()
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "Could not \(operation): \(error.localizedDescription)"
        }
    }

    private func nonEmpty(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func stableIntegerID(for raw: String) -> Int {
        if let integer = Int(raw) { return integer }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in raw.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash & UInt64(Int.max))
    }
}
