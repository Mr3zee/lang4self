import SwiftUI
import Lang4SelfCore

struct SentenceReviewView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var germanSpeech: GermanSpeechController
    @State private var generationCount = 5
    @State private var generationCountText = "5"
    @State private var generationOptions = SentenceGenerationOptions.defaults
    @State private var minimumWordsText = "5"
    @State private var maximumWordsText = "14"
    @State private var testMode = SentenceTestMode.vocabularyBlanks
    @State private var answer = ""
    @FocusState private var focusedControl: FocusControl?
    let automaticallyFocusContent: Bool
    let forcedTestMode: SentenceTestMode?

    private enum FocusControl: Hashable { case style, answer }

    init(
        automaticallyFocusContent: Bool,
        forcedTestMode: SentenceTestMode? = nil
    ) {
        self.automaticallyFocusContent = automaticallyFocusContent
        self.forcedTestMode = forcedTestMode
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    if state.sentencePractice.hasStarted {
                        practiceContent
                    } else {
                        VStack(spacing: 18) {
                            Text("Choose the run settings, then start practicing.")
                                .foregroundStyle(.secondary)
                            generationControls
                        }
                    }
                }
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .center)
                .padding(.horizontal, 20)
            }
            .accessibilityIdentifier("sentences.scroll")
        }
        .onAppear {
            applyForcedTestMode()
            updateGermanSpeechTarget()
            if automaticallyFocusContent { focusPrimaryContent() }
        }
        .onChange(of: state.sentencePractice.currentItem?.id) { _, _ in
            answer = ""
            updateGermanSpeechTarget()
            if state.sentencePractice.currentItem != nil {
                DispatchQueue.main.async { focusedControl = .answer }
            }
        }
        .onChange(of: state.sentencePractice.result) { _, _ in
            updateGermanSpeechTarget()
        }
        .onChange(of: state.sentencePractice.hasStarted) { _, _ in
            answer = ""
            updateGermanSpeechTarget()
            if automaticallyFocusContent { focusPrimaryContent() }
        }
        .onChange(of: state.sentencePractice.mode) { _, _ in
            updateGermanSpeechTarget()
        }
        .onChange(of: forcedTestMode) { _, _ in
            applyForcedTestMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusReviewContent)) { _ in
            focusPrimaryContent()
        }
        .task(id: automaticListeningItemID) {
            guard isListeningPractice,
                  state.sentencePractice.result == nil,
                  let item = state.sentencePractice.currentItem
            else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            germanSpeech.speak(item.draft.german)
        }
    }

    private var generationControls: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    numericStepper(
                        title: "Sentence count",
                        value: generationCountBinding,
                        text: $generationCountText,
                        range: 1...50,
                        fieldIdentifier: "sentences.count-input",
                        stepperIdentifier: "sentences.count"
                    )
                    .help("Number of new sentences (maximum 50)")

                    Spacer(minLength: 12)

                    Button("Start run") {
                        commitNumericInputs()
                        answer = ""
                        state.startSentencePractice(
                            count: generationCount,
                            mode: selectedTestMode,
                            options: generationOptions
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        state.sentencePractice.isGenerating ||
                        state.sentencePractice.isUpdatingRetry ||
                        state.wordLists.isEmpty
                    )
                    .accessibilityIdentifier("sentences.generate")
                }

                if forcedTestMode == nil {
                    Picker("Test mode", selection: $testMode) {
                        ForEach(SentenceTestMode.configurableCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(state.sentencePractice.isGenerating)
                    .accessibilityIdentifier("sentences.mode")
                } else {
                    Label("Listen to each generated sentence and write what you hear.", systemImage: "waveform")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("sentences.listening-description")
                }

                HStack(spacing: 8) {
                    Text("Level")
                        .foregroundStyle(.secondary)
                    Picker("CEFR level", selection: $generationOptions.proficiency) {
                        ForEach(SentenceProficiencyLevel.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 70)
                    .accessibilityIdentifier("sentences.level")

                    Spacer(minLength: 8)

                    Text("Words")
                        .foregroundStyle(.secondary)
                    numericStepper(
                        title: "Minimum words",
                        value: minimumWordsBinding,
                        text: $minimumWordsText,
                        range: 2...generationOptions.maximumWords,
                        fieldIdentifier: "sentences.minimum-words-input",
                        stepperIdentifier: "sentences.minimum-words"
                    )
                    Text("–").foregroundStyle(.secondary)
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
                    Text("Style").foregroundStyle(.secondary)
                    TextField("Sentence style", text: $generationOptions.style)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedControl, equals: .style)
                        .accessibilityIdentifier("sentences.style")
                }

                HStack(spacing: 8) {
                    generationStatusIcon
                    Text(generationStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    if !state.sentenceRetries.isEmpty {
                        Label(
                            "\(state.sentenceRetries.count) waiting for retry",
                            systemImage: "arrow.clockwise"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("sentences.retry-count")
                    }
                }
            }
            .padding(4)
        } label: {
            Text("Sentence run settings")
        }
    }

    @ViewBuilder
    private var generationStatusIcon: some View {
        if state.sentencePractice.isGenerating || state.lmStudioProgress.isWorking {
            ProgressView().controlSize(.small)
        } else if case .failed = state.lmStudioProgress {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        } else if case .ready = state.lmStudioProgress {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Image(systemName: "externaldrive.connected.to.line.below").foregroundStyle(.secondary)
        }
    }

    private var generationStatusText: String {
        let pending = state.sentencePractice.pendingGenerationCount
        if state.sentencePractice.isGenerating, pending > 0 {
            return "\(state.sentencePractice.generatedCount) ready · generating \(pending) more in batches of 5"
        }
        return state.lmStudioProgress.message
    }

    @ViewBuilder
    private var practiceContent: some View {
        if let item = state.sentencePractice.currentItem {
            testCard(item)

            if state.sentencePractice.result != nil {
                revealedAnswer(for: item)
            }
        } else if state.sentencePractice.isWaitingForInitialGeneration {
            GroupBox {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Preparing your first sentence…")
                        .font(.title3.weight(.semibold))
                    Text("Practice will start as soon as it’s ready.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .accessibilityIdentifier("sentences.preparing")
            }
        } else if state.sentencePractice.isWaitingForGeneration {
            GroupBox {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Waiting for the next sentences…")
                        .font(.title3.weight(.semibold))
                    Text("You finished everything ready so far. Generation is continuing in the background.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .accessibilityIdentifier("sentences.waiting")
            }
        } else if state.sentencePractice.isComplete {
            VStack(spacing: 16) {
                ContentUnavailableView {
                    Label("Sentence run complete", systemImage: "checkmark.circle")
                } description: {
                    Text("Answered \(state.sentencePractice.answeredCount) prompt\(state.sentencePractice.answeredCount == 1 ? "" : "s").")
                }
                .accessibilityIdentifier("sentences.complete")
                Button("Set up another run") {
                    state.abortSentencePractice()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("sentences.restart")
            }
            .frame(minHeight: 260)
        } else {
            ContentUnavailableView {
                Label("Test your German", systemImage: "text.badge.checkmark")
            } description: {
                Text("Choose a mode, then generate sentences from your vocabulary.")
            }
            .frame(minHeight: 260)
        }
    }

    private func testCard(_ item: SentencePracticeItem) -> some View {
        VStack(spacing: 22) {
            HStack(spacing: 5) {
                Text("Prompt \(state.sentencePractice.currentIndex + 1)")
                Text("· \(max(0, state.sentencePractice.items.count - state.sentencePractice.currentIndex - 1)) ready after this")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if isListeningPractice {
                VStack(spacing: 14) {
                    Image(systemName: "waveform")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Listen and write the sentence")
                        .font(.title2.weight(.semibold))
                    Button {
                        germanSpeech.speak(item.draft.german)
                    } label: {
                        Label("Replay", systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Replay the sentence — press Shift twice")
                    .accessibilityIdentifier("sentences.listening-replay")
                    KeyboardShortcutHint(.doubleShift)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .accessibilityIdentifier("sentences.listening-prompt")
            } else {
                Text(item.draft.translation)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("sentences.translation")

                if SentenceAnswerEvaluator.usesVocabularyBlanks(
                    for: item,
                    mode: state.sentencePractice.mode
                ) {
                    MaskedSentenceFlow(item: item)
                } else {
                    Label(
                        state.sentencePractice.mode == .vocabularyBlanks
                            ? "This retry has no linked vocabulary word. Write the full German sentence."
                            : "Write the full German sentence.",
                        systemImage: "pencil.line"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            if state.sentencePractice.result == nil {
                VStack(spacing: 14) {
                    TextField(answerPlaceholder(for: item), text: $answer)
                        .textFieldStyle(.plain)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .focused($focusedControl, equals: .answer)
                        .onSubmit { submitAnswer() }
                        .accessibilityIdentifier("sentences.answer")

                    Button("Check") { submitAnswer() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("sentences.check")
                }
                .frame(maxWidth: 560)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sentences.test-card")
    }

    private func revealedAnswer(for item: SentencePracticeItem) -> some View {
        VStack(spacing: 14) {
            HStack {
                switch state.sentencePractice.result {
                case .correct:
                    Label("Correct", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .incorrect:
                    Label("Not quite — this sentence was added to your retry queue", systemImage: "arrow.clockwise.circle.fill")
                        .foregroundStyle(.orange)
                case nil:
                    EmptyView()
                }
                Spacer()
                if state.sentencePractice.isUpdatingRetry {
                    ProgressView().controlSize(.small)
                }
                Button(nextButtonTitle) {
                    state.advanceSentencePractice()
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.sentencePractice.isUpdatingRetry)
                .accessibilityIdentifier("sentences.next")
            }
            .font(.headline)

            SentenceInspector(sentence: SentencePresentation(item: item))
                .id(item.id)
                .frame(minHeight: 520)
                .accessibilityIdentifier("sentences.revealed")
        }
    }

    private var nextButtonTitle: String {
        if state.sentencePractice.currentIndex + 1 < state.sentencePractice.items.count {
            return "Next"
        }
        return state.sentencePractice.isGenerating ? "Continue" : "Finish"
    }

    private func answerPlaceholder(for item: SentencePracticeItem) -> String {
        SentenceAnswerEvaluator.usesVocabularyBlanks(for: item, mode: state.sentencePractice.mode)
            ? "Missing word or words"
            : "German sentence"
    }

    private func submitAnswer() {
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        focusedControl = nil
        state.submitSentenceAnswer(answer)
    }

    private func focusPrimaryContent() {
        if state.sentencePractice.result != nil {
            focusedControl = nil
            NotificationCenter.default.post(name: .focusSentenceInspector, object: nil)
        } else if state.sentencePractice.currentItem != nil {
            focusedControl = .answer
        } else {
            focusedControl = .style
        }
    }

    private func updateGermanSpeechTarget() {
        let sentence = isListeningPractice || state.sentencePractice.result != nil
            ? state.sentencePractice.currentItem?.draft.german
            : nil
        germanSpeech.setTarget(sentence, in: .review)
    }

    private func applyForcedTestMode() {
        guard let forcedTestMode,
              state.sentencePractice.hasStarted,
              state.sentencePractice.mode != forcedTestMode
        else { return }
        state.setSentencePracticeMode(forcedTestMode)
    }

    private var selectedTestMode: SentenceTestMode {
        forcedTestMode ?? testMode
    }

    private var isListeningPractice: Bool {
        state.sentencePractice.hasStarted
            ? state.sentencePractice.mode == .listening
            : forcedTestMode == .listening
    }

    private var automaticListeningItemID: SentencePracticeItem.ID? {
        guard isListeningPractice, state.sentencePractice.result == nil else { return nil }
        return state.sentencePractice.currentItem?.id
    }

    private var generationCountBinding: Binding<Int> {
        Binding(
            get: { generationCount },
            set: { generationCount = min(max($0, 1), 50) }
        )
    }

    private var minimumWordsBinding: Binding<Int> {
        Binding(
            get: { generationOptions.minimumWords },
            set: {
                generationOptions.minimumWords = min(max($0, 2), generationOptions.maximumWords)
            }
        )
    }

    private var maximumWordsBinding: Binding<Int> {
        Binding(
            get: { generationOptions.maximumWords },
            set: {
                generationOptions.maximumWords = max(min($0, 30), generationOptions.minimumWords)
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
                .frame(width: 42)
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
                    if Int(text.wrappedValue) != newValue { text.wrappedValue = String(newValue) }
                }
        }
    }

    private func commitNumericInputs() {
        generationCount = min(max(Int(generationCountText) ?? generationCount, 1), 50)
        var options = generationOptions
        options.minimumWords = Int(minimumWordsText) ?? options.minimumWords
        options.maximumWords = Int(maximumWordsText) ?? options.maximumWords
        generationOptions = options.sanitized
        generationCountText = String(generationCount)
        minimumWordsText = String(generationOptions.minimumWords)
        maximumWordsText = String(generationOptions.maximumWords)
    }
}

private struct MaskedSentenceFlow: View {
    let item: SentencePracticeItem

    var body: some View {
        TokenFlowLayout(spacing: 7) {
            ForEach(item.draft.tokens) { token in
                Text(displayText(for: token))
                    .font(.title2.weight(token.cardID == nil ? .regular : .semibold))
                    .foregroundStyle(token.cardID == nil ? .primary : Color.accentColor)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, token.cardID == nil ? 0 : 6)
                    .padding(.vertical, 3)
                    .background(
                        token.cardID == nil ? Color.clear : Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .accessibilityLabel(token.cardID == nil ? token.surface : "Missing vocabulary word")
            }
        }
        .accessibilityIdentifier("sentences.masked-sentence")
    }

    private func displayText(for token: SentenceToken) -> String {
        guard token.cardID != nil else { return token.surface }
        let lexical = SentenceTokenizer.lookupTerm(from: token.surface)
        guard let range = token.surface.range(of: lexical), !lexical.isEmpty else { return "_____" }
        return String(token.surface[..<range.lowerBound]) + "_____" + String(token.surface[range.upperBound...])
    }
}

private struct SentencePresentation: Identifiable {
    let id: UUID
    let german: String
    let translation: String
    let tokens: [SentenceToken]
    let analysis: SentenceAnalysis?
    let sourceListName: String

    init(item: SentencePracticeItem) {
        id = item.id
        german = item.draft.german
        translation = item.draft.translation
        tokens = item.draft.tokens
        analysis = item.draft.analysis
        sourceListName = item.sourceListName
    }
}

private struct SentenceLookupContext: Hashable {
    let sentenceID: UUID
    let token: SentenceToken?
    let nounTokenIndices: Set<Int>
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
                    GermanPronunciationHint(german: sentence.german)
                    HStack(spacing: 4) {
                        KeyboardShortcutHint(.init(chords: [.init(.left), .init(.right)]))
                        Text("select word")
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
                                .fixedSize(horizontal: true, vertical: true)
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
                        .accessibilityElement(children: .ignore)
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
                                    Text("— " + TranslationPresentation.summary(
                                        of: entries[index].meanings,
                                        fallback: entries[index].english
                                    ))
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
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
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
        .onAppear { selectedTokenIndex = 0 }
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
        case .left, .up:
            selectedTokenIndex = max(0, selectedTokenIndex - 1)
        case .right, .down:
            selectedTokenIndex = min(sentence.tokens.count - 1, selectedTokenIndex + 1)
        @unknown default:
            break
        }
        focusedTokenIndex = selectedTokenIndex
    }
}

extension Notification.Name {
    static let focusSentenceInspector = Notification.Name("focusSentenceInspector")
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
        let result = layout(
            proposal: .init(width: bounds.width, height: proposal.height),
            subviews: subviews
        )
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func layout(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, points: [CGPoint], sizes: [CGSize]) {
        let maxWidth = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            // Each token keeps its ideal width, so short words never split into
            // multiple lines. Wrapping only happens between tokens.
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            sizes.append(size)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return (CGSize(width: min(usedWidth, maxWidth), height: y + lineHeight), points, sizes)
    }
}
