import SwiftUI

struct FanBlastBar: View {
    @Binding var messageText: String
    let onSend: () -> Void
    let onReaction: (String) -> Void
    let reactions = ["⚽️", "🟥", "🖥️", "😱", "🔥", "🧱"]
    /// When `false`, reactions and composer are disabled.
    var allowsInteraction: Bool = true
    
    private var canSend: Bool {
        allowsInteraction && !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(reactions, id: \.self) { emoji in
                        Button { onReaction(emoji) } label: { Text(emoji).font(.system(size: 24)).padding(8).background(Circle().fill(FottyTheme.surfaceElevated)) }
                            .disabled(!allowsInteraction)
                    }
                }.padding(.horizontal, FottyTheme.spacingMD)
            }
            .opacity(allowsInteraction ? 1 : 0.45)
            HStack(spacing: 12) {
                TextField("Join the Arena...", text: $messageText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(FottyTheme.surfaceElevated))
                    .submitLabel(.send)
                    .onSubmit { if canSend { onSend() } }
                    .disabled(!allowsInteraction)
                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(canSend ? FottyTheme.textOnAccent : FottyTheme.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(canSend ? FottyTheme.accent : FottyTheme.surfaceElevated))
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, FottyTheme.spacingMD)
            .padding(.bottom, 8)
            .opacity(allowsInteraction ? 1 : 0.45)
        }.padding(.top, 12).background(Rectangle().fill(.ultraThinMaterial).ignoresSafeArea())
    }
}

struct StadiumCardView: View {
    let userID: String
    let displayName: String
    let username: String
    let avatarSymbol: String
    @Environment(\.dismiss) private var dismiss
    var onMessageTap: (() -> Void)?
    var onBlockTap: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: avatarSymbol)
                    .font(.system(size: 60))
                    .frame(width: 100, height: 100)
                    .background(Circle().fill(FottyTheme.surfaceElevated))
                    .foregroundStyle(FottyTheme.accentText)
                    .overlay(Circle().stroke(FottyTheme.accent.opacity(0.3), lineWidth: 4))
                VStack(spacing: 4) {
                    Text(displayName)
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(FottyTheme.textPrimary)
                    Text("@\(username)")
                        .font(.system(size: 16))
                        .foregroundStyle(FottyTheme.textSecondary)
                }
            }
            .padding(.top, 40)
            
            Spacer()
            
            VStack(spacing: 12) {
                Button {
                    onMessageTap?()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "message.fill")
                        Text("Jump to Private Room")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(FottyTheme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(FottyTheme.textOnAccent)
                }
                
                Button(role: .destructive) {
                    onBlockTap?()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "nosign")
                        Text("Block User")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(FottyTheme.liveAccent.opacity(0.18))
                    )
                    .foregroundStyle(FottyTheme.accentText)
                }
                
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .fontWeight(.semibold)
                        .foregroundStyle(FottyTheme.textSecondary)
                        .padding(.vertical, 8)
                }
            }
            .padding(.bottom, 20)
        }
        .padding(FottyTheme.spacingXL)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                FottyTheme.background
                LinearGradient(
                    colors: [FottyTheme.accent.opacity(0.1), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    
}
