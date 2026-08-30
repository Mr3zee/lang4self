import SwiftUI
import Lang4SelfCore

struct SentencesView: View {
    @EnvironmentObject private var state: AppState
    @State private var generationCount = 5
    @State private var selection: SentenceSelection?
    @FocusState private var sentenceListFocused: Bool

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                generationControls
                Divider()
                sentenceList
                if !state.generatedSentences.isEmpty {
                    Divider()
                    saveControls
                }
            }
            .frame(minWidth: 330, idealWidth: 400)

            if let sentence = selectedSentence {
                SentenceInspector(sentence: sentence)
                    .id(sentence.id)
            } else {
                PlaceholderView(
                    symbol: "text.quote",
                    title: "Select a sentence",
                    detail: "Use the arrow keys inside a sentence to inspect each word's translation."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Sentences")
        .onAppear {
            repairSelection()
            DispatchQueue.main.async { sentenceListFocused = true }
        }
        .onChange(of: state.generatedSentences.map(\.id)) { _, _ in repairSelection(preferGenerated: true) }
        .onChange(of: state.savedSentences.map(\.id)) { _, _ in repairSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .focusSentenceList)) { _ in
            DispatchQueue.main.async { sentenceListFocused = true }
        }
    }

    private var generationControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Generate from", selection: Binding(
                    get: { state.selectedListID },
                    set: { state.selectWordList($0) }
                )) {
                    ForEach(state.wordLists) { list in Text(list.name).tag(list.id) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("sentences.list-picker")

                Stepper(value: $generationCount, in: 1...10) {
                    Text("\(generationCount)")
                        .monospacedDigit()
                        .frame(minWidth: 18)
                }
                .help("Number of sentences (maximum 10)")
                .accessibilityIdentifier("sentences.count")

                Button("Generate") {
                    state.generateSentences(count: generationCount)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isGeneratingSentences || state.wordLists.isEmpty)
                .accessibilityIdentifier("sentences.generate")
            }

            HStack(spacing: 8) {
                if state.lmStudioProgress.isWorking {
                    ProgressView().controlSize(.small)
                } else if case .failed = state.lmStudioProgress {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else if case .ready = state.lmStudioProgress {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Image(systemName: "externaldrive.connected.to.line.below").foregroundStyle(.secondary)
                }
                Text(state.lmStudioProgress.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(14)
    }

    private var sentenceList: some View {
        List(selection: $selection) {
            if !state.generatedSentences.isEmpty {
                Section("Generated") {
                    ForEach(state.generatedSentences) { sentence in
                        HStack(alignment: .top, spacing: 9) {
                            Toggle(isOn: Binding(
                                get: { state.selectedGeneratedSentenceIDs.contains(sentence.id) },
                                set: { state.setGeneratedSentence(sentence.id, selected: $0) }
                            )) {
                                Text("Include \(sentence.german) when saving")
                            }
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .help("Include when saving")
                            .accessibilityLabel("Include generated sentence when saving")
                            .accessibilityIdentifier("sentences.include.\(sentence.id.uuidString)")

                            SentenceRow(
                                german: sentence.german,
                                translation: sentence.translation,
                                tokens: sentence.tokens
                            )
                        }
                        .tag(SentenceSelection.generated(sentence.id))
                    }
                }
            }

            Section("Saved sentences") {
                if state.savedSentences.isEmpty {
                    Text("No saved sentences yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.savedSentences) { sentence in
                        SentenceRow(
                            german: sentence.german,
                            translation: sentence.translation,
                            tokens: sentence.tokens,
                            footnote: sentence.sourceListName
                        )
                        .tag(SentenceSelection.saved(sentence.id))
                        .contextMenu {
                            Button("Delete Sentence", role: .destructive) {
                                state.deleteSentence(sentence)
                            }
                        }
                    }
                }
            }
        }
        .onDeleteCommand {
            guard case .saved(let id) = selection,
                  let sentence = state.savedSentences.first(where: { $0.id == id }) else { return }
            state.deleteSentence(sentence)
        }
        .onKeyPress(.return) {
            guard selectedSentence != nil else { return .ignored }
            sentenceListFocused = false
            NotificationCenter.default.post(name: .focusSentenceInspector, object: nil)
            return .handled
        }
        .focused($sentenceListFocused)
        .accessibilityIdentifier("sentences.list")
    }

    private var saveControls: some View {
        HStack {
            Button(state.selectedGeneratedSentenceIDs.count == state.generatedSentences.count ? "Select None" : "Select All") {
                state.selectAllGeneratedSentences(
                    state.selectedGeneratedSentenceIDs.count != state.generatedSentences.count
                )
            }
            .accessibilityIdentifier("sentences.select-all")
            Spacer()
            Button("Save Selected (\(state.selectedGeneratedSentenceIDs.count))") {
                state.saveSelectedGeneratedSentences()
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.selectedGeneratedSentenceIDs.isEmpty)
            .accessibilityIdentifier("sentences.save-selected")
        }
        .padding(12)
    }

    private var selectedSentence: SentencePresentation? {
        switch selection {
        case .generated(let id):
            guard let sentence = state.generatedSentences.first(where: { $0.id == id }) else { return nil }
            return .init(
                id: .generated(id),
                german: sentence.german,
                translation: sentence.translation,
                tokens: sentence.tokens,
                sourceListName: state.generatedSourceList?.name ?? state.selectedWordList?.name ?? "Selected list"
            )
        case .saved(let id):
            guard let sentence = state.savedSentences.first(where: { $0.id == id }) else { return nil }
            return .init(
                id: .saved(id),
                german: sentence.german,
                translation: sentence.translation,
                tokens: sentence.tokens,
                sourceListName: sentence.sourceListName
            )
        case nil:
            return nil
        }
    }

    private func repairSelection(preferGenerated: Bool = false) {
        if preferGenerated, let first = state.generatedSentences.first {
            selection = .generated(first.id)
        } else if selectedSentence != nil {
            return
        } else if let first = state.savedSentences.first {
            selection = .saved(first.id)
        } else if let first = state.generatedSentences.first {
            selection = .generated(first.id)
        } else {
            selection = nil
        }
    }
}

private enum SentenceSelection: Hashable {
    case generated(UUID)
    case saved(Int64)
}

private struct SentencePresentation: Identifiable {
    let id: SentenceSelection
    let german: String
    let translation: String
    let tokens: [SentenceToken]
    let sourceListName: String
}

private struct SentenceRow: View {
    let german: String
    let translation: String
    let tokens: [SentenceToken]
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GermanSentenceText(german: german, tokens: tokens)
                .fontWeight(.medium)
                .lineLimit(2)
            Text(translation).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            if let footnote {
                Label(footnote, systemImage: "list.bullet")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct SentenceInspector: View {
    @EnvironmentObject private var state: AppState
    let sentence: SentencePresentation

    @State private var selectedTokenIndex = 0
    @State private var entries: [DictionaryEntry] = []
    @State private var selectedEntryIndex = 0
    @State private var isLookingUp = false
    @State private var tokenGenders: [Int: Gender] = [:]
    @FocusState private var focusedTokenIndex: Int?

    private var selectedToken: SentenceToken? {
        guard sentence.tokens.indices.contains(selectedTokenIndex) else { return nil }
        return sentence.tokens[selectedTokenIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(sentence.sourceListName, systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("←/→ select word")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if let savedSentence {
                        Button("Delete Sentence", role: .destructive) {
                            state.deleteSentence(savedSentence)
                        }
                        .keyboardShortcut(.delete, modifiers: [])
                        .accessibilityIdentifier("sentences.delete-selected")
                    }
                }

                TokenFlowLayout(spacing: 7) {
                    ForEach(Array(sentence.tokens.enumerated()), id: \.element.id) { offset, token in
                        Button {
                            selectedTokenIndex = offset
                            focusedTokenIndex = offset
                        } label: {
                            Text(token.surface)
                                .font(.title2.weight(offset == selectedTokenIndex ? .semibold : .regular))
                                .foregroundStyle(tokenGenders[token.index]?.color ?? .primary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(
                                    offset == selectedTokenIndex ? Color.accentColor.opacity(0.18) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                        }
                        .buttonStyle(.plain)
                        .focusable()
                        .focused($focusedTokenIndex, equals: offset)
                        .onMoveCommand(perform: moveSelection)
                        .accessibilityLabel("Word \(offset + 1) of \(sentence.tokens.count): \(token.surface)")
                        .accessibilityIdentifier("sentence.token.\(offset)")
                    }
                }
                Text(sentence.translation)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)

            Divider()

            if isLookingUp {
                ProgressView("Finding translation…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                PlaceholderView(
                    symbol: "character.book.closed",
                    title: "No translation found",
                    detail: "Try selecting another word."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    if entries.count > 1 {
                        Picker("Translation card", selection: $selectedEntryIndex) {
                            ForEach(entries.indices, id: \.self) { index in
                                HStack {
                                    GermanWordView(entry: entries[index], font: .body)
                                    Text("— " + entries[index].english)
                                }
                                .tag(index)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .accessibilityIdentifier("sentence.translation-picker")
                    }
                    EntryDetailView(entry: entries[min(selectedEntryIndex, entries.count - 1)])
                }
            }
        }
        .task(id: selectedToken) {
            guard let selectedToken else { return }
            isLookingUp = true
            let foundEntries = await state.translationEntries(for: selectedToken)
            guard !Task.isCancelled else { return }
            entries = foundEntries
            selectedEntryIndex = 0
            isLookingUp = false
        }
        .task(id: sentence.tokens) {
            tokenGenders = await state.sentenceGenders(for: sentence.tokens)
        }
        .onAppear {
            selectedTokenIndex = 0
        }
        .onChange(of: focusedTokenIndex) { _, index in
            if let index { selectedTokenIndex = index }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSentenceInspector)) { _ in
            selectedTokenIndex = 0
            focusedTokenIndex = 0
        }
        .onExitCommand {
            focusedTokenIndex = nil
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .focusSentenceList, object: nil)
            }
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !sentence.tokens.isEmpty else { return }
        switch direction {
        case .left, .up:
            selectedTokenIndex = max(0, selectedTokenIndex - 1)
        case .right, .down:
            selectedTokenIndex = min(sentence.tokens.count - 1, selectedTokenIndex + 1)
        @unknown default:
            break
        }
        focusedTokenIndex = selectedTokenIndex
    }

    private var savedSentence: SavedSentence? {
        guard case .saved(let id) = sentence.id else { return nil }
        return state.savedSentences.first { $0.id == id }
    }
}

private extension Notification.Name {
    static let focusSentenceInspector = Notification.Name("focusSentenceInspector")
    static let focusSentenceList = Notification.Name("focusSentenceList")
}

private struct TokenFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(proposal: .init(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return (CGSize(width: min(usedWidth, maxWidth), height: y + lineHeight), points)
    }
}
