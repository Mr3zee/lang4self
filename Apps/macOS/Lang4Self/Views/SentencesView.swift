import SwiftUI
import Lang4SelfCore

struct SentencesView: View {
    @EnvironmentObject private var state: AppState
    @State private var generationCount = 5
    @State private var generationCountText = "5"
    @State private var generationOptions = SentenceGenerationOptions.defaults
    @State private var minimumWordsText = "5"
    @State private var maximumWordsText = "14"
    @State private var selection: SentenceSelection?
    @FocusState private var sentenceListFocused: Bool
    let automaticallyFocusContent: Bool

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
            if automaticallyFocusContent {
                DispatchQueue.main.async { sentenceListFocused = true }
            }
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

                numericStepper(
                    title: "Sentence count",
                    value: generationCountBinding,
                    text: $generationCountText,
                    range: 1...10,
                    fieldIdentifier: "sentences.count-input",
                    stepperIdentifier: "sentences.count"
                )
                .help("Number of sentences (maximum 10)")

                Button("Generate") {
                    commitNumericInputs()
                    state.generateSentences(count: generationCount, options: generationOptions)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isGeneratingSentences || state.wordLists.isEmpty)
                .accessibilityIdentifier("sentences.generate")
            }

            HStack(spacing: 8) {
                Text("Level")
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Picker("CEFR level", selection: $generationOptions.proficiency) {
                    ForEach(SentenceProficiencyLevel.allCases) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 70)
                .accessibilityLabel("CEFR level")
                .accessibilityIdentifier("sentences.level")

                Spacer(minLength: 8)

                Text("Words")
                    .foregroundStyle(.secondary)
                    .fixedSize()
                numericStepper(
                    title: "Minimum words",
                    value: minimumWordsBinding,
                    text: $minimumWordsText,
                    range: 2...generationOptions.maximumWords,
                    fieldIdentifier: "sentences.minimum-words-input",
                    stepperIdentifier: "sentences.minimum-words"
                )

                Text("–")
                    .foregroundStyle(.secondary)

                numericStepper(
                    title: "Maximum words",
                    value: maximumWordsBinding,
                    text: $maximumWordsText,
                    range: generationOptions.minimumWords...30,
                    fieldIdentifier: "sentences.maximum-words-input",
                    stepperIdentifier: "sentences.maximum-words"
                )
            }

            HStack(spacing: 8) {
                Text("Style")
                    .foregroundStyle(.secondary)
                TextField("Sentence style", text: $generationOptions.style)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Sentence style")
                    .accessibilityIdentifier("sentences.style")
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

    private var generationCountBinding: Binding<Int> {
        Binding(
            get: { generationCount },
            set: { generationCount = min(max($0, 1), 10) }
        )
    }

    private var minimumWordsBinding: Binding<Int> {
        Binding(
            get: { generationOptions.minimumWords },
            set: {
                generationOptions.minimumWords = min(
                    max($0, 2),
                    generationOptions.maximumWords
                )
            }
        )
    }

    private var maximumWordsBinding: Binding<Int> {
        Binding(
            get: { generationOptions.maximumWords },
            set: {
                generationOptions.maximumWords = max(
                    min($0, 30),
                    generationOptions.minimumWords
                )
            }
        )
    }

    private func numericStepper(
        title: String,
        value: Binding<Int>,
        text: Binding<String>,
        range: ClosedRange<Int>,
        fieldIdentifier: String,
        stepperIdentifier: String
    ) -> some View {
        HStack(spacing: 4) {
            TextField(title, text: text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 38)
                .accessibilityLabel(title)
                .accessibilityIdentifier(fieldIdentifier)
                .onSubmit { commitNumericInputs() }
                .onChange(of: text.wrappedValue) { _, newValue in
                    guard let number = Int(newValue), range.contains(number) else { return }
                    value.wrappedValue = number
                }

            Stepper(title, value: value, in: range)
                .labelsHidden()
                .accessibilityIdentifier(stepperIdentifier)
                .onChange(of: value.wrappedValue) { _, newValue in
                    if Int(text.wrappedValue) != newValue {
                        text.wrappedValue = String(newValue)
                    }
                }
        }
    }

    private func commitNumericInputs() {
        generationCount = min(max(Int(generationCountText) ?? generationCount, 1), 10)
        var options = generationOptions
        options.minimumWords = Int(minimumWordsText) ?? options.minimumWords
        options.maximumWords = Int(maximumWordsText) ?? options.maximumWords
        generationOptions = options.sanitized

        generationCountText = String(generationCount)
        minimumWordsText = String(generationOptions.minimumWords)
        maximumWordsText = String(generationOptions.maximumWords)
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
        .focused($sentenceListFocused)
        .accessibilityIdentifier("sentences.list")
        .onKeyPress(.rightArrow) {
            guard selectedSentence != nil else { return .ignored }
            sentenceListFocused = false
            NotificationCenter.default.post(name: .focusSentenceInspector, object: nil)
            return .handled
        }
        .onKeyPress("x") {
            guard case .generated(let id) = selection else { return .ignored }
            state.setGeneratedSentence(
                id,
                selected: !state.selectedGeneratedSentenceIDs.contains(id)
            )
            return .handled
        }
        .onKeyPress(.return) {
            guard !state.selectedGeneratedSentenceIDs.isEmpty else { return .handled }
            state.saveSelectedGeneratedSentences()
            return .handled
        }
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
                analysis: sentence.analysis,
                sourceListName: state.generatedSourceList?.name ?? state.selectedWordList?.name ?? "Selected list"
            )
        case .saved(let id):
            guard let sentence = state.savedSentences.first(where: { $0.id == id }) else { return nil }
            return .init(
                id: .saved(id),
                german: sentence.german,
                translation: sentence.translation,
                tokens: sentence.tokens,
                analysis: sentence.analysis,
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
    let analysis: SentenceAnalysis?
    let sourceListName: String
}

private struct SentenceLookupContext: Hashable {
    let sentenceID: SentenceSelection
    let token: SentenceToken?
    let nounTokenIndices: Set<Int>
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

    private var selectedTokenIndices: Set<Int> {
        guard let selectedToken else { return [] }
        return SentenceRelations.relatedTokenIndices(
            for: selectedToken,
            sentence: sentence.german,
            tokens: sentence.tokens,
            analysis: sentence.analysis,
            nounTokenIndices: Set(tokenGenders.keys)
        )
    }

    private var lookupContext: SentenceLookupContext {
        SentenceLookupContext(
            sentenceID: sentence.id,
            token: selectedToken,
            nounTokenIndices: Set(tokenGenders.keys)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(sentence.sourceListName, systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        KeyboardShortcutHint(.init(chords: [.init(.left), .init(.right)]))
                        Text("select word")
                    }
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
                        let isSelected = selectedTokenIndices.contains(token.index)
                        Button {
                            selectedTokenIndex = offset
                            focusedTokenIndex = offset
                        } label: {
                            Text(token.surface)
                                .font(.title2.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(tokenGenders[token.index]?.color ?? .primary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(
                                    isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                        }
                        .buttonStyle(.plain)
                        .focusable()
                        .focused($focusedTokenIndex, equals: offset)
                        .onMoveCommand(perform: moveSelection)
                        .accessibilityLabel("Word \(offset + 1) of \(sentence.tokens.count): \(token.surface)")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
        .task(id: lookupContext) {
            let context = lookupContext
            guard let selectedToken = context.token else { return }
            isLookingUp = true
            let foundEntries = await state.translationEntries(
                for: selectedToken,
                sentence: sentence.german,
                in: sentence.tokens,
                analysis: sentence.analysis,
                nounTokenIndices: context.nounTokenIndices
            )
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
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !sentence.tokens.isEmpty else { return }
        switch direction {
        case .left where selectedTokenIndex == sentence.tokens.startIndex:
            focusedTokenIndex = nil
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .focusSentenceList, object: nil)
            }
            return
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
