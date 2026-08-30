import SwiftUI

struct UserAgreementView: View {
    @Environment(\.dismiss) private var dismiss
    var onAccept: () -> Void = {}
    
    var body: some View {
        NavigationStack {
            ZStack {
                FottyTheme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("User Generated Content (UGC) Policy")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(FottyTheme.textPrimary)
                        
                        Text("By using Fotty's social features, you agree to the following terms:")
                            .font(.system(size: 16))
                            .foregroundStyle(FottyTheme.textSecondary)
                        
                        legalLinks
                        
                        VStack(alignment: .leading, spacing: 16) {
                            policySection(title: "1. No Objectionable Content", content: "Users may not post content that is offensive, insensitive, upsetting, intended to disgust, or in exceptionally poor taste. This includes, but is not limited to, defamation, harassment, and hate speech.")
                            
                            policySection(title: "2. Zero Tolerance", content: "Fotty has a zero-tolerance policy towards objectionable content and abusive users. Failure to comply with these terms will result in immediate account suspension and a permanent ban from social features.")
                            
                            policySection(title: "3. Reporting Mechanism", content: "You can report any objectionable content or users by using the 'Report' button found on every post. Reports are reviewed by our moderation team within 24 hours.")
                            
                            policySection(title: "4. Blocking Users", content: "You can block any user to prevent their content from appearing in your feed and to stop them from interacting with you.")
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding()
                }
            }
            .navigationTitle("End User License Agreement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Accept") {
                        onAccept()
                        dismiss()
                    }
                    .foregroundStyle(FottyTheme.accentText)
                    .fontWeight(.bold)
                }
            }
        }
    }
    
    @ViewBuilder
    private var legalLinks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review full legal documents:")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FottyTheme.textSecondary)
            
            HStack(spacing: 10) {
                if let termsURL = Config.termsOfUseURL {
                    Link(destination: termsURL) {
                        Label("Terms of Use", systemImage: "scroll.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(FottyTheme.accentText)
                }
                
                if let privacyURL = Config.privacyPolicyURL {
                    Link(destination: privacyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(FottyTheme.accentText)
                }
            }
        }
        .padding(12)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    private func policySection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(FottyTheme.accentText)
            
            Text(content)
                .font(.system(size: 14))
                .foregroundStyle(FottyTheme.textSecondary)
                .lineSpacing(4)
        }
        .padding()
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
