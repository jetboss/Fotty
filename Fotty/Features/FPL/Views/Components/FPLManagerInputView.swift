import SwiftUI
import UIKit

public struct FPLManagerInputView: View {
    @Environment(\.fottyWideLayout) private var usesWideLayout
    @ObservedObject var viewModel: FPLAdvisorViewModel
    @StateObject private var connection = FPLManagerConnectionModel()
    @State private var inputID = ""
    @State private var lookupRequest: UUID?
    @State private var showsConnectionHelp = false
    @FocusState private var isInputFocused: Bool
    @Environment(\.openURL) private var openURL

    private var parsedManagerID: Int? { FPLManagerIDParser.parse(inputID) }

    public init(viewModel: FPLAdvisorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
          let columns = usesWideLayout
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 32))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
          columns {
            VStack(alignment: .leading, spacing: 20) {
                Text(viewModel.requiresManagerConfirmation ? "Confirm your FPL team" : "Your FPL")
                    .font(.title.weight(.bold))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .frame(minHeight: 44, alignment: .leading)

                Text(viewModel.requiresManagerConfirmation
                     ? "Check your team for this season. Your saved plans and history are still on this device."
                     : "Connect your public team to plan your gameweek. No FPL password needed.")
                    .font(.body)
                    .foregroundStyle(FottyTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 20) {
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

                connectionControls

                DisclosureGroup("Team link help", isExpanded: $showsConnectionHelp) {
                  VStack(alignment: .leading, spacing: 8) {
                    Text("Paste your FPL Points-page link or manager number.")
                        .font(.callout)
                    if viewModel.requiresManagerConfirmation {
                        Text("Manager IDs can change or be reassigned each season. A saved ID from an earlier installation or backup needs a fresh check before your team is connected.")
                            .font(.callout)
                    }
                    Button("Open Fantasy Premier League") {
                        if let url = URL(string: "https://fantasy.premierleague.com/") { openURL(url) }
                    }
                    .frame(minHeight: 44)
                  }
                  .padding(.top, 8)
                }
                .foregroundStyle(FottyTheme.textSecondary)
                .accessibilityIdentifier("fpl-connection-help")

                if viewModel.hasUnverifiedLegacyWorkspace {
                    Text("Older unassigned plans and chats stay on this device and won't be applied automatically.")
                        .font(.footnote)
                        .foregroundStyle(FottyTheme.textSecondary)
                }

                Text(FottyHelpContent.fplDrafts)
                    .font(.footnote)
                    .foregroundStyle(FottyTheme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
          }
            .padding(16)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FottyTheme.background.ignoresSafeArea())
        .tint(FottyTheme.accentText)
        .onAppear {
            if inputID.isEmpty, viewModel.requiresManagerConfirmation, let id = viewModel.managerId {
                inputID = String(id)
            }
        }
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
            Button(action: checkTeam) {
                Text("Find my team")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
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
