import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let fottyPrivateBackup = UTType(
        exportedAs: "com.jelani.fotty.private-backup",
        conformingTo: .data
    )
}

struct FottyPrivateBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.fottyPrivateBackup, .data] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw FottyPrivateBackupError.unsupportedFormat
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// File-provider reads must not block SwiftUI, and a stale size receipt must
/// not let a growing file allocate past the reviewed encrypted-file limit.
enum FottyPrivateBackupFileReader {
    static func read(_ url: URL, maximumBytes: Int = FottyPrivateBackupCrypto.maximumFileBytes) async throws -> Data {
        guard maximumBytes > 0 else { throw FottyPrivateBackupError.fileTooLarge }
        let reader = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumBytes {
                throw FottyPrivateBackupError.fileTooLarge
            }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var data = Data()
            while true {
                try Task.checkCancellation()
                guard let chunk = try file.read(upToCount: min(64 * 1024, maximumBytes - data.count + 1)), !chunk.isEmpty else { break }
                guard chunk.count <= maximumBytes - data.count else { throw FottyPrivateBackupError.fileTooLarge }
                data.append(chunk)
            }
            try Task.checkCancellation()
            return data
        }
        return try await withTaskCancellationHandler {
            let data = try await reader.value
            try Task.checkCancellation()
            return data
        } onCancel: { reader.cancel() }
    }
}

/// A cancelled decrypt may still finish its bounded crypto work. Only the
/// current input generation can publish a preview, error or busy-state change.
struct FottyPrivateBackupReviewState {
    struct Ticket: Equatable {
        fileprivate let id = UUID()
    }

    private var currentTicket: Ticket?
    private(set) var isWorking = false
    private(set) var payload: FottyPrivateBackupPayload?
    private(set) var errorMessage: String?

    mutating func begin() -> Ticket {
        invalidate()
        let ticket = Ticket()
        currentTicket = ticket
        isWorking = true
        return ticket
    }

    mutating func invalidate() {
        currentTicket = nil
        isWorking = false
        payload = nil
        errorMessage = nil
    }

    @discardableResult
    mutating func complete(_ ticket: Ticket, payload: FottyPrivateBackupPayload) -> Bool {
        guard ticket == currentTicket else { return false }
        currentTicket = nil
        isWorking = false
        self.payload = payload
        errorMessage = nil
        return true
    }

    @discardableResult
    mutating func fail(_ ticket: Ticket, message: String) -> Bool {
        guard ticket == currentTicket else { return false }
        currentTicket = nil
        isWorking = false
        payload = nil
        errorMessage = message
        return true
    }

    mutating func clearError() {
        errorMessage = nil
    }
}

struct SettingsPrivateBackupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("fotty.privateBackup.lastVerifiedExport") private var lastVerifiedExport = 0.0
    @State private var createPassword = ""
    @State private var confirmPassword = ""
    @State private var restorePassword = ""
    @State private var importedData: Data?
    @State private var importTask: Task<Void, Never>?
    @State private var importGeneration: UUID?
    @State private var restoreReview = FottyPrivateBackupReviewState()
    @State private var reviewTask: Task<Void, Never>?
    @State private var exportDocument: FottyPrivateBackupDocument?
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var isCreating = false
    @State private var confirmsRestore = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: FottyTheme.spacingLG) {
                includedSection
                createSection
                restoreSection

                Text("Fotty never stores the backup password. Keep it somewhere safe: an encrypted backup cannot be opened without it.")
                    .font(FottyTheme.typeCaption)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(FottyTheme.spacingMD)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(FottyTheme.background.ignoresSafeArea())
        .navigationTitle("Private Backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.fottyPrivateBackup, .data],
            allowsMultipleSelection: false,
            onCompletion: receiveImport
        )
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .fottyPrivateBackup,
            defaultFilename: defaultFilename
        ) { result in
            switch result {
            case .success:
                lastVerifiedExport = Date().timeIntervalSince1970
                statusMessage = "Encrypted backup saved and verified. Keep the file and password separate."
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            exportDocument = nil
        }
        .confirmationDialog(
            "Replace this device's Fotty setup?",
            isPresented: $confirmsRestore,
            titleVisibility: .visible
        ) {
            Button("Restore Backup", role: .destructive, action: restoreReviewedBackup)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Followed teams, leagues, saved Matchday items, selected FPL manager and local plans will be replaced. Match reminders will be turned off and Smart Coach consent must be given again.")
        }
        .alert("Backup problem", isPresented: Binding(
            get: { backupErrorMessage != nil },
            set: { if !$0 { clearBackupError() } }
        )) {
            Button("OK", action: clearBackupError)
        } message: {
            Text(backupErrorMessage ?? "")
        }
        .onDisappear(perform: clearRestoreReview)
        .accessibilityIdentifier("settings-private-backup")
    }

    private var includedSection: some View {
        SettingsSection(title: "Private and portable") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Included", systemImage: "checkmark.shield.fill")
                    .font(FottyTheme.typeAction)
                    .foregroundStyle(FottyTheme.textPrimary)
                Text("Appearance, Home and alert preferences, followed teams and leagues, saved Matchday identities, your public FPL manager ID, local squad draft, planning scenarios, decision journal, reviews and Coach strategy profile.")
                    .font(FottyTheme.typeBody)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().overlay(FottyTheme.border)
                Label("Never included", systemImage: "minus.circle.fill")
                    .font(FottyTheme.typeAction)
                    .foregroundStyle(FottyTheme.textPrimary)
                Text("Passwords, Coach conversations, AI consent, reminders, diagnostics, cached feeds, provider URLs, stream history, profile photos and local messages.")
                    .font(FottyTheme.typeBody)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if lastVerifiedExport > 0 {
                    Divider().overlay(FottyTheme.border)
                    Label(
                        "Last verified export: \(Date(timeIntervalSince1970: lastVerifiedExport).formatted(date: .abbreviated, time: .shortened))",
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.success)
                }
            }
            .padding(FottyTheme.spacingMD)
        }
    }

    private var createSection: some View {
        SettingsSection(title: "Create encrypted backup") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Use at least 12 characters for the backup password.")
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                SecureField("Backup password", text: $createPassword)
                    .textContentType(.newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .fottyInputStyle()
                    .accessibilityIdentifier("backup-create-password")
                SecureField("Confirm backup password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .fottyInputStyle()
                    .accessibilityIdentifier("backup-create-confirm")
                Button(action: createEncryptedBackup) {
                    Label(isCreating ? "Preparing…" : "Save encrypted backup", systemImage: "lock.doc.fill")
                        .font(FottyTheme.typeAction)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(FottyTheme.accent)
                .foregroundStyle(FottyTheme.textOnAccent)
                .disabled(isWorking)
                .accessibilityIdentifier("backup-create")
            }
            .padding(FottyTheme.spacingMD)
        }
    }

    private var restoreSection: some View {
        SettingsSection(title: "Restore") {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    clearRestoreReview()
                    isImporting = true
                } label: {
                    Label(importedData == nil ? "Choose backup file" : "Choose a different file", systemImage: "folder.fill")
                        .font(FottyTheme.typeAction)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("backup-choose-file")

                if importedData != nil {
                    SecureField("Backup password", text: restorePasswordBinding)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .fottyInputStyle()
                        .accessibilityIdentifier("backup-restore-password")
                    Button(action: reviewImportedBackup) {
                        Label(restoreReview.isWorking ? "Checking…" : "Review before restoring", systemImage: "doc.text.magnifyingglass")
                            .font(FottyTheme.typeAction)
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)
                    .accessibilityIdentifier("backup-review")
                }

                if let previewPayload = restoreReview.payload {
                    restorePreview(FottyPrivateBackupSummary(payload: previewPayload))
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(FottyTheme.typeBody)
                        .foregroundStyle(FottyTheme.success)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("backup-status")
                }
            }
            .padding(FottyTheme.spacingMD)
        }
    }

    private func restorePreview(_ summary: FottyPrivateBackupSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(FottyTheme.border)
            Text("Backup ready to review")
                .font(FottyTheme.typeAction)
                .foregroundStyle(FottyTheme.textPrimary)
            previewRow("Created", summary.createdAt.formatted(date: .abbreviated, time: .shortened))
            previewRow("App", "v\(summary.appVersion) (\(summary.appBuild))")
            previewRow("Followed", "\(summary.followedTeams) teams · \(summary.followedLeagues) leagues")
            previewRow("Matchday", "\(summary.savedMatches) saved")
            previewRow("FPL", summary.managerID.map { "Manager \($0) · \(summary.fplPlans) local plans" } ?? "Not connected")
            Button(role: .destructive) { confirmsRestore = true } label: {
                Label("Restore this backup", systemImage: "arrow.clockwise.circle.fill")
                    .font(FottyTheme.typeAction)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(FottyTheme.error)
            .accessibilityIdentifier("backup-restore")
        }
        .padding(.top, 4)
    }

    private func previewRow(_ label: String, _ value: String) -> some View {
        previewLayout {
            Text(label).foregroundStyle(FottyTheme.textSecondary)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 12) }
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(FottyTheme.textPrimary)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(FottyTheme.typeMeta)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var previewLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
    }

    private func createEncryptedBackup() {
        guard !isWorking else { return }
        statusMessage = nil
        guard createPassword == confirmPassword else {
            errorMessage = "The two backup passwords do not match."
            return
        }
        do {
            let payload = try FottyPrivateBackupService.capture(modelContext: modelContext)
            let password = createPassword
            isCreating = true
            Task {
                defer { isCreating = false }
                do {
                    let data = try await Task.detached(priority: .userInitiated) {
                        let data = try FottyPrivateBackupCrypto.seal(payload, password: password)
                        guard try FottyPrivateBackupCrypto.open(data, password: password) == payload else {
                            throw FottyPrivateBackupError.invalidBackup("encrypted export self-check failed")
                        }
                        return data
                    }.value
                    exportDocument = FottyPrivateBackupDocument(data: data)
                    createPassword = ""
                    confirmPassword = ""
                    isExporting = true
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func receiveImport(_ result: Result<[URL], Error>) {
        clearRestoreReview()
        do {
            let url = try result.get().first ?? { throw FottyPrivateBackupError.unsupportedFormat }()
            let generation = UUID()
            importGeneration = generation
            importTask = Task {
                do {
                    let data = try await FottyPrivateBackupFileReader.read(url)
                    guard !Task.isCancelled, importGeneration == generation else { return }
                    importedData = data
                    importGeneration = nil
                    importTask = nil
                } catch {
                    guard !Task.isCancelled, importGeneration == generation else { return }
                    errorMessage = error.localizedDescription
                    importGeneration = nil
                    importTask = nil
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reviewImportedBackup() {
        guard !isCreating, let importedData else { return }
        let password = restorePassword
        reviewTask?.cancel()
        let ticket = restoreReview.begin()
        statusMessage = nil
        errorMessage = nil
        confirmsRestore = false
        reviewTask = Task {
            do {
                let payload = try await Task.detached(priority: .userInitiated) {
                    try FottyPrivateBackupCrypto.open(importedData, password: password)
                }.value
                guard !Task.isCancelled else { return }
                if restoreReview.complete(ticket, payload: payload) {
                    reviewTask = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                if restoreReview.fail(ticket, message: error.localizedDescription) {
                    reviewTask = nil
                }
            }
        }
    }

    private func restoreReviewedBackup() {
        guard let previewPayload = restoreReview.payload else { return }
        do {
            let summary = try FottyPrivateBackupService.restore(
                previewPayload,
                modelContext: modelContext
            )
            clearRestoreReview()
            statusMessage = "Restore complete: \(summary.followedTeams) followed teams, \(summary.savedMatches) Matchday items and \(summary.fplPlans) FPL plans. Check the FPL manager shown, then re-enable only the reminders and Smart Coach access you want."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearRestoreReview() {
        importTask?.cancel()
        importTask = nil
        importGeneration = nil
        invalidateRestoreReview()
        importedData = nil
        restorePassword = ""
        statusMessage = nil
        errorMessage = nil
    }

    private func invalidateRestoreReview() {
        reviewTask?.cancel()
        reviewTask = nil
        restoreReview.invalidate()
        confirmsRestore = false
    }

    private var restorePasswordBinding: Binding<String> {
        Binding(get: { restorePassword }, set: { password in
            guard password != restorePassword else { return }
            // Fence the old password before another completion can reach the UI.
            invalidateRestoreReview()
            restorePassword = password
        })
    }

    private var isWorking: Bool { isCreating || importGeneration != nil || restoreReview.isWorking }

    private var backupErrorMessage: String? { errorMessage ?? restoreReview.errorMessage }

    private func clearBackupError() {
        errorMessage = nil
        restoreReview.clearError()
    }

    private var defaultFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "Fotty-Private-Backup-\(formatter.string(from: Date())).fottybackup"
    }
}

private extension View {
    func fottyInputStyle() -> some View {
        self
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(FottyTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusSM))
            .overlay {
                RoundedRectangle(cornerRadius: FottyTheme.radiusSM)
                    .strokeBorder(FottyTheme.borderStrong, lineWidth: 1)
            }
    }
}
