import SwiftUI
import UIKit

public struct FPLManagerInputView: View {
    @ObservedObject var viewModel: FPLAdvisorViewModel
    @StateObject private var connection = FPLManagerConnectionModel()
    @State private var inputID = ""
    @State private var lookupRequest: UUID?
    @FocusState private var isInputFocused: Bool
    @Environment(\.openURL) private var openURL

    private var parsedManagerID: Int? { FPLManagerIDParser.parse(inputID) }

    public init(viewModel: FPLAdvisorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Connect your FPL team", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.title2.bold())
                    .foregroundStyle(FottyTheme.textPrimary)

                Text("Use your public team to plan the gameweek and give Smart Coach context. No FPL password is needed.")
                    .font(.body)
                    .foregroundStyle(FottyTheme.textSecondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Team link or manager ID").font(.headline)
                    TextField("Paste your team link or ID", text: $inputID)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isInputFocused)
                        .submitLabel(.search)
                        .onSubmit(checkTeam)
                        .padding(14)
                        .background(FottyTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("fpl-manager-input")
                    Button("Paste team link or ID") {
                        inputID = UIPasteboard.general.string ?? inputID
                    }
                    .frame(minHeight: 44)
                    if !inputID.isEmpty && parsedManagerID == nil {
                        Text("Use your official FPL team link or the number after /entry/.")
                            .font(.callout)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Where do I find it?").font(.headline)
                    Text("Open your Points page in FPL and copy its web address. You can also enter just the number after /entry/.")
                        .font(.callout)
                    Button("Open Fantasy Premier League") {
                        if let url = URL(string: "https://fantasy.premierleague.com/") { openURL(url) }
                    }
                    .frame(minHeight: 44)
                }
                .foregroundStyle(FottyTheme.textSecondary)

                connectionControls

                Text(FottyHelpContent.fplDrafts)
                    .font(.footnote)
                    .foregroundStyle(FottyTheme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FottyTheme.background.ignoresSafeArea())
        .tint(FottyTheme.accentText)
        .task(id: lookupRequest) {
            guard lookupRequest != nil else { return }
            await connection.lookup(inputID)
        }
        .onChange(of: inputID) { _, _ in cancelLookup() }
        .onDisappear { cancelLookup() }
    }

    @ViewBuilder
    private var connectionControls: some View {
        if connection.isChecking {
            ProgressView("Checking your team…")
            Button("Cancel check", action: cancelLookup).frame(minHeight: 44)
        } else if let identity = connection.identity, identity.id == parsedManagerID {
            VStack(alignment: .leading, spacing: 10) {
                Text("Is this your team?").font(.headline)
                Text(identity.teamName).font(.title3.bold())
                Text("\(identity.managerName) · ID \(identity.id)").font(.subheadline)
                Text(identity.sourceDescription)
                    .font(.caption)
                    .foregroundStyle(FottyTheme.textSecondary)
                Button("Connect this team") {
                    isInputFocused = false
                    viewModel.setManagerId(identity.id)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(FottyTheme.textOnAccent)
                .accessibilityIdentifier("fpl-confirm-team")
                Button("Use a different team") {
                    cancelLookup()
                    isInputFocused = true
                }
                .frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .bentoSurface()
        } else {
            if let error = connection.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(FottyTheme.textPrimary)
            }
            Button("Find my team", action: checkTeam)
                .buttonStyle(.borderedProminent)
                .foregroundStyle(FottyTheme.textOnAccent)
                .disabled(parsedManagerID == nil)
                .frame(minHeight: 44)
                .accessibilityIdentifier("fpl-find-team")
        }
    }

    private func checkTeam() {
        guard parsedManagerID != nil else { return }
        isInputFocused = false
        lookupRequest = UUID()
    }

    private func cancelLookup() {
        lookupRequest = nil
        connection.reset()
    }
}
