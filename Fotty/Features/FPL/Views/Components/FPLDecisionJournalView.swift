import SwiftUI

public struct FPLDecisionJournalView: View {
    @ObservedObject private var viewModel: FPLAdvisorViewModel
    @State private var isShowingComposer = false
    @State private var reflectionEntry: FPLDecisionJournalEntry?

    public init(viewModel: FPLAdvisorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if viewModel.decisionJournalEntries.isEmpty {
                emptyState
            } else {
                ForEach(groupedGameweeks, id: \.gameweek) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GAMEWEEK \(group.gameweek)")
                            .font(FottyTheme.typeCaption)
                            .foregroundStyle(FottyTheme.textTertiary)
                        ForEach(group.entries) { entry in
                            decisionRow(entry)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingComposer) {
            FPLDecisionComposerView(viewModel: viewModel)
        }
        .sheet(item: $reflectionEntry) { entry in
            FPLDecisionReflectionView(viewModel: viewModel, entry: entry)
        }
    }

    private var groupedGameweeks: [(gameweek: Int, entries: [FPLDecisionJournalEntry])] {
        Dictionary(grouping: viewModel.decisionJournalEntries, by: \.gameweek)
            .map { (gameweek: $0.key, entries: $0.value.sorted { $0.updatedAt > $1.updatedAt }) }
            .sorted { $0.gameweek > $1.gameweek }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("DECISION JOURNAL", systemImage: "book.closed.fill")
                        .font(FottyTheme.typeSectionTitle)
                        .foregroundStyle(FottyTheme.textPrimary)
                    Text("Record the call before the deadline, then judge the process after the gameweek.")
                        .font(FottyTheme.typeMeta)
                        .foregroundStyle(FottyTheme.textSecondary)
                }
                Spacer(minLength: 8)
                Button {
                    isShowingComposer = true
                } label: {
                    Image(systemName: "plus")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(FottyTheme.accentText)
                .accessibilityLabel("Record a decision")
            }

            Text("Stored only on this device for the current manager and season. A good decision can still have a bad one-week result.")
                .font(FottyTheme.typeCaption)
                .foregroundStyle(FottyTheme.textTertiary)
        }
        .padding(16)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusLG, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bookmark.square")
                .font(.fottyScaled(size: 34, weight: .semibold))
                .foregroundStyle(FottyTheme.accentText)
            Text("No decisions recorded yet")
                .font(FottyTheme.typeModuleTitle)
                .foregroundStyle(FottyTheme.textPrimary)
            Text("Save a route from Transfer Lab, save a Smart Coach card, or record your own captain, lineup, chip, or strategy call.")
                .font(FottyTheme.typeBody)
                .foregroundStyle(FottyTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Record first decision") {
                isShowingComposer = true
            }
            .buttonStyle(.borderedProminent)
            .tint(FottyTheme.accentText)
            .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusLG, style: .continuous))
    }

    private func decisionRow(_ entry: FPLDecisionJournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: entry.kind.symbol)
                    .foregroundStyle(FottyTheme.accentText)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(FottyTheme.typeModuleTitle)
                        .foregroundStyle(FottyTheme.textPrimary)
                    Text("\(entry.kind.rawValue) • \(entry.source)")
                        .font(FottyTheme.typeCaption)
                        .foregroundStyle(FottyTheme.textTertiary)
                }
                Spacer(minLength: 8)
                outcomeMenu(entry)
            }

            Text(entry.rationale)
                .font(.subheadline)
                .foregroundStyle(FottyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !entry.expectedOutcome.isEmpty {
                Label(entry.expectedOutcome, systemImage: "target")
                    .font(.subheadline)
                    .foregroundStyle(FottyTheme.textSecondary)
            }
            if let cost = entry.estimatedPointCost, cost > 0 {
                Label("Estimated transfer cost: -\(cost) points", systemImage: "minus.circle.fill")
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.error)
            }
            if !entry.outcomeNote.isEmpty {
                Text("Reflection: \(entry.outcomeNote)")
                    .font(.subheadline)
                    .foregroundStyle(FottyTheme.textPrimary)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FottyTheme.surfaceSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusSM))
            }

            HStack {
                Text(entry.createdAt, style: .date)
                    .font(FottyTheme.typeCaption)
                    .foregroundStyle(FottyTheme.textTertiary)
                Spacer()
                Button(entry.outcomeNote.isEmpty ? "Add reflection" : "Edit reflection") {
                    reflectionEntry = entry
                }
                .font(FottyTheme.typeAction)
                .frame(minHeight: 44)
                .accessibilityHint("Records what happened and what you learned")
            }
        }
        .padding(14)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FottyTheme.radiusMD, style: .continuous)
                .strokeBorder(FottyTheme.border, lineWidth: 1)
        }
        .contextMenu {
            Button("Delete decision", role: .destructive) {
                viewModel.removeDecision(id: entry.id)
            }
        }
    }

    private func outcomeMenu(_ entry: FPLDecisionJournalEntry) -> some View {
        Menu {
            ForEach(FPLDecisionJournalEntry.Outcome.allCases) { outcome in
                Button(outcome.rawValue) {
                    viewModel.updateDecisionOutcome(id: entry.id, outcome: outcome, note: entry.outcomeNote)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(outcomeColor(entry.outcome))
                    .frame(width: 7, height: 7)
                Text(entry.outcome.rawValue)
                    .font(FottyTheme.typeCaption)
            }
            .foregroundStyle(FottyTheme.textPrimary)
            .padding(.horizontal, 8)
            .frame(minHeight: 36)
            .background(FottyTheme.surfaceElevated)
            .clipShape(Capsule())
        }
        .accessibilityLabel("Outcome: \(entry.outcome.rawValue)")
        .accessibilityHint("Change the decision outcome")
    }

    private func outcomeColor(_ outcome: FPLDecisionJournalEntry.Outcome) -> Color {
        switch outcome {
        case .pending: return FottyTheme.textTertiary
        case .worked: return FottyTheme.success
        case .mixed: return FottyTheme.accentText
        case .missed: return FottyTheme.error
        case .abandoned: return FottyTheme.textSecondary
        }
    }
}

private struct FPLDecisionComposerView: View {
    @ObservedObject var viewModel: FPLAdvisorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind: FPLDecisionJournalEntry.Kind = .strategy
    @State private var title = ""
    @State private var rationale = ""
    @State private var expectedOutcome = ""

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Decision") {
                    Picker("Type", selection: $kind) {
                        ForEach(FPLDecisionJournalEntry.Kind.allCases) { kind in
                            Label(kind.rawValue, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    TextField("Short title", text: $title)
                    TextField("Why are you making this call?", text: $rationale, axis: .vertical)
                        .lineLimit(3...7)
                    TextField("What do you expect to happen?", text: $expectedOutcome, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Text("Fotty records this locally. It does not submit a change to official FPL.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Record Decision")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.recordDecision(
                            kind: kind,
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            rationale: rationale.trimmingCharacters(in: .whitespacesAndNewlines),
                            expectedOutcome: expectedOutcome.trimmingCharacters(in: .whitespacesAndNewlines),
                            source: "Manual note"
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

private struct FPLDecisionReflectionView: View {
    @ObservedObject var viewModel: FPLAdvisorViewModel
    let entry: FPLDecisionJournalEntry
    @Environment(\.dismiss) private var dismiss
    @State private var outcome: FPLDecisionJournalEntry.Outcome
    @State private var note: String

    init(viewModel: FPLAdvisorViewModel, entry: FPLDecisionJournalEntry) {
        self.viewModel = viewModel
        self.entry = entry
        _outcome = State(initialValue: entry.outcome)
        _note = State(initialValue: entry.outcomeNote)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Outcome") {
                    Picker("Result", selection: $outcome) {
                        ForEach(FPLDecisionJournalEntry.Outcome.allCases) { outcome in
                            Text(outcome.rawValue).tag(outcome)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Process reflection") {
                    TextField("What happened, and was the reasoning sound?", text: $note, axis: .vertical)
                        .lineLimit(4...10)
                }
                Section {
                    Text("Review the quality of the information and reasoning, not only the one-week points result.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Review Decision")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.updateDecisionOutcome(
                            id: entry.id,
                            outcome: outcome,
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}
