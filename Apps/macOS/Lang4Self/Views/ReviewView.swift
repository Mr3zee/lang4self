import SwiftUI
import Lang4SelfCore

struct ReviewView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var speech: SpeechRecognizer
    @EnvironmentObject private var germanSpeech: GermanSpeechController
    @State private var mode = ReviewTestMode.flashcard
    @State private var revealed = false
    @State private var answer = ""
    @State private var submittedAnswer: String?
    @State private var answerWasCorrect: Bool?
    @State private var translations = ReviewTranslationCarousel()
    @State private var carouselWordIDs = CarouselWordIDs()
    @FocusState private var focusedAction: FocusedAction?
    let automaticallyFocusContent: Bool

    private enum FocusedAction: Hashable {
        case carousel
        case reveal
        case answer
        case speech
        case gender(Int)
        case rating(Int)
        case restart
    }

    private enum CarouselSlot {
        case previousLanguage
        case previousTranslation
        case current
        case nextTranslation
        case nextLanguage
    }

    private struct CarouselWord: Identifiable {
        let id: Int
        let slot: CarouselSlot
        let item: ReviewTranslationCarousel.Item
    }

    private struct CarouselWordIDs {
        private(set) var previousLanguage = 0
        private(set) var previousTranslation = 1
        private(set) var current = 2
        private(set) var nextTranslation = 3
        private(set) var nextLanguage = 4
        private var nextID = 5

        mutating func moveTranslation(by offset: Int) {
            if offset < 0 {
                nextTranslation = current
                current = previousTranslation
                previousTranslation = takeNextID()
            } else {
                previousTranslation = current
                current = nextTranslation
                nextTranslation = takeNextID()
            }
        }

        mutating func moveLanguage(by offset: Int) {
            if offset < 0 {
                nextLanguage = current
                current = previousLanguage
                previousLanguage = takeNextID()
            } else {
                previousLanguage = current
                current = nextLanguage
                nextLanguage = takeNextID()
            }
        }

        func id(for slot: CarouselSlot) -> Int {
            switch slot {
            case .previousLanguage: previousLanguage
            case .previousTranslation: previousTranslation
            case .current: current
            case .nextTranslation: nextTranslation
            case .nextLanguage: nextLanguage
            }
        }

        private mutating func takeNextID() -> Int {
            defer { nextID += 1 }
            return nextID
        }
    }

    private var current: PersonalCard? {
        state.reviewCards.first { ReviewChallenge(card: $0, mode: mode) != nil }
    }

    private var challenge: ReviewChallenge? {
        current.flatMap { ReviewChallenge(card: $0, mode: mode) }
    }

    var body: some View {
        VStack(spacing: 0) {
            statsBar
            Divider()

            if let card = current {
                VStack(spacing: 24) {
                    Spacer()
                    Text(mode.title.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("review.mode-title")
                    PartOfSpeechBadge(kind: card.kind)
                        .accessibilityIdentifier("review.part-of-speech")
                    prompt(for: card)

                    if revealed {
                        Divider().frame(maxWidth: 460)
                        revealedAnswer(for: card)
                    } else {
                        responseControl
                    }
                    Spacer()

                    if revealed { ratingBar(card) }
                }
                .padding(32)
            } else {
                VStack(spacing: 0) {
                    PlaceholderView(
                        symbol: "checkmark.circle",
                        title: emptyReviewTitle,
                        detail: emptyReviewDetail
                    )
                    if state.reviewCards.isEmpty, state.stats.totalCards > 0 {
                        Button(state.isReviewingAll ? "Review All Again" : "Review All Cards") {
                            state.startReviewAll()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.bottom, 40)
                        .keyboardShortcut(.space, modifiers: [])
                        .focusable()
                        .focused($focusedAction, equals: .restart)
                        .accessibilityIdentifier("review.restart")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            Color.clear
                .frame(width: 1, height: 1)
                .focusable()
                .focused($focusedAction, equals: .carousel)
                .focusEffectDisabled()
                .accessibilityHidden(true)
        }
        .navigationTitle("Review")
        .onAppear {
            Task { await state.refreshStudyData() }
            resetTranslations(for: current)
            updateGermanSpeechTarget()
            if automaticallyFocusContent { focusPrimaryAction() }
        }
        .onDisappear {
            state.stopPreparingReviewTranslations()
            speech.reset()
            germanSpeech.setTarget(nil, in: .review)
        }
        .onReceive(NotificationCenter.default.publisher(for: .previousReviewMode)) { _ in
            mode = mode.advanced(by: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextReviewMode)) { _ in
            mode = mode.advanced(by: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusReviewContent)) { _ in
            focusCarousel()
        }
        .onChange(of: current?.id) { _, _ in
            resetResponse()
            resetTranslations(for: current)
            if automaticallyFocusContent || focusedAction != nil { focusPrimaryAction() }
        }
        .onChange(of: mode) { oldMode, _ in
            if oldMode.usesSpeech { speech.reset() }
            resetResponse()
            resetTranslations(for: current)
            updateGermanSpeechTarget()
            focusPrimaryAction()
        }
        .onChange(of: state.reviewDictionaryMeanings) { _, meanings in
            guard let card = current,
                  state.reviewDictionaryMeaningsCardID == card.id
            else { return }
            translations.replace(cardEnglish: card.english, dictionaryMeanings: meanings)
        }
        .onChange(of: state.selectedListID) { _, _ in resetResponse() }
        .onChange(of: state.isReviewingAll) { _, _ in resetResponse() }
        .onChange(of: speech.phase) { _, phase in
            guard mode.usesSpeech,
                  phase == .guess,
                  !revealed,
                  !speech.transcription.isEmpty
            else { return }
            submit(speech.transcription)
        }
        .onChange(of: revealed) { _, isRevealed in
            updateGermanSpeechTarget()
            DispatchQueue.main.async {
                focusedAction = isRevealed ? .rating(suggestedRating.rawValue) : primaryFocusedAction
            }
        }
        .onKeyPress(.leftArrow) {
            guard mode.usesTranslationCarousel,
                  translations.hasMultipleTranslations else { return .ignored }
            withAnimation(.snappy) {
                translations.moveTranslation(by: -1)
                carouselWordIDs.moveTranslation(by: -1)
            }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard mode.usesTranslationCarousel,
                  translations.hasMultipleTranslations else { return .ignored }
            withAnimation(.snappy) {
                translations.moveTranslation(by: 1)
                carouselWordIDs.moveTranslation(by: 1)
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard mode.usesTranslationCarousel,
                  translations.hasMultipleLanguages else { return .ignored }
            withAnimation(.snappy) {
                translations.moveLanguage(by: -1)
                carouselWordIDs.moveLanguage(by: -1)
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard mode.usesTranslationCarousel,
                  translations.hasMultipleLanguages else { return .ignored }
            withAnimation(.snappy) {
                translations.moveLanguage(by: 1)
                carouselWordIDs.moveLanguage(by: 1)
            }
            return .handled
        }
        .onChange(of: current?.german) { _, _ in updateGermanSpeechTarget() }
    }

    @ViewBuilder
    private func prompt(for card: PersonalCard) -> some View {
        if mode.usesTranslationCarousel {
            translationCarousel
        } else {
            VStack(spacing: 8) {
                switch mode {
                case .gender:
                    Text("Choose the article")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                case .conjugation:
                    Text("Present tense")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                case .plural:
                    Text("Write the plural")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                case .germanToEnglish, .germanToEnglishWriting:
                    Text("Translate into English")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                case .flashcard, .writing, .speaking:
                    EmptyView()
                }

                Text(card.german)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("review.prompt")

                if let pronoun = challenge?.conjugationPronoun {
                    Text("\(pronoun) …")
                        .font(.title2.weight(.semibold))
                        .accessibilityIdentifier("review.conjugation-pronoun")
                }

                GermanPronunciationHint(german: card.german)
            }
            .frame(minHeight: 180)
        }
    }

    @ViewBuilder
    private var responseControl: some View {
        if mode.requiresWrittenAnswer {
            HStack(spacing: 10) {
                TextField(writtenAnswerPlaceholder, text: $answer)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .focused($focusedAction, equals: .answer)
                    .onSubmit { submit(answer) }
                    .accessibilityIdentifier("review.answer")

                Button("Check") { submit(answer) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("review.check")
            }
            .frame(maxWidth: 520)
        } else if mode.usesSpeech {
            speechControl
        } else if mode.usesGenderChoices {
            HStack(spacing: 12) {
                ForEach(Array(Self.genderChoices.enumerated()), id: \.offset) { index, gender in
                    Button(gender.article) { submit(gender.article) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(minWidth: 84)
                        .focused($focusedAction, equals: .gender(index))
                        .accessibilityIdentifier("review.gender.\(gender.rawValue)")
                }
            }
        } else {
            Button("Show answer  Space") { revealed = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.space, modifiers: [])
                .focusable()
                .focused($focusedAction, equals: .reveal)
                .accessibilityIdentifier("review.reveal")
        }
    }

    @ViewBuilder
    private var speechControl: some View {
        VStack(spacing: 10) {
            if speech.hasRecordingPermission {
                Button(speechControlTitle) { toggleSpeechRecognition() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(speech.phase == .requestingPermission || speech.phase == .processing)
                    .focused($focusedAction, equals: .speech)
                    .accessibilityIdentifier("review.speech")
            } else {
                Button("Set up speech recognition") { speech.requestPermissions() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(speech.phase == .requestingPermission)
                    .focused($focusedAction, equals: .speech)
                    .accessibilityIdentifier("review.speech-permission")
            }

            if !speech.transcription.isEmpty {
                Text("Heard: \(speech.transcription)")
                    .font(.headline)
                    .accessibilityIdentifier("review.speech-transcription")
            } else {
                Text(speechStatusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("review.speech-status")
            }
        }
    }

    @ViewBuilder
    private func revealedAnswer(for card: PersonalCard) -> some View {
        if let answerWasCorrect {
            HStack(spacing: 6) {
                Image(systemName: answerWasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .accessibilityHidden(true)
                Text(answerWasCorrect ? "Correct" : "Not quite")
                    .accessibilityIdentifier("review.answer-result")
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(answerWasCorrect ? .green : .red)

            if !answerWasCorrect, let submittedAnswer {
                Text("Your answer: \(submittedAnswer)")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("review.submitted-answer")
            }
        }

        switch mode {
        case .flashcard, .writing, .speaking:
            GermanWordView(entry: entry(for: card), font: .system(size: 32, weight: .bold))
            GermanPronunciationHint(german: card.german)
            compactInfo(for: card)

        case .germanToEnglish, .germanToEnglishWriting:
            Text(challenge?.acceptedAnswers.joined(separator: " · ") ?? card.english)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .accessibilityIdentifier("review.correct-answer")

        case .gender:
            Text("\(challenge?.acceptedAnswers.first ?? card.gender.article) \(card.german)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .accessibilityIdentifier("review.correct-answer")

        case .conjugation:
            Text("\(challenge?.conjugationPronoun ?? "") \(challenge?.acceptedAnswers.first ?? "")")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .accessibilityIdentifier("review.correct-answer")

        case .plural:
            Text(challenge?.acceptedAnswers.joined(separator: " · ") ?? "")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .accessibilityIdentifier("review.correct-answer")
        }
    }

    private var translationCarousel: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let horizontalOffset = min(270, max(160, width * 0.36))
            let wordWidth = min(340, max(220, width * 0.48))

            ZStack {
                ForEach(carouselWords) { word in
                    carouselWord(word, width: wordWidth)
                        .position(
                            x: wordX(
                                for: word.slot,
                                width: width,
                                horizontalOffset: horizontalOffset
                            ),
                            y: wordY(for: word.slot, height: height)
                        )
                        .transition(.opacity)
                }

                carouselControls(width: width, height: height)
            }
        }
        .frame(maxWidth: 760)
        .frame(height: 250)
        .clipped()
        .textSelection(.enabled)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded(focusCarousel))
    }

    private var carouselWords: [CarouselWord] {
        var words: [CarouselWord] = []
        let items: [(CarouselSlot, ReviewTranslationCarousel.Item?)] = [
            (.previousLanguage, translations.previousLanguage),
            (.previousTranslation, translations.previousTranslation),
            (.current, translations.current),
            (.nextTranslation, translations.nextTranslation),
            (.nextLanguage, translations.nextLanguage)
        ]
        for (slot, item) in items {
            guard let item else { continue }
            words.append(CarouselWord(id: carouselWordIDs.id(for: slot), slot: slot, item: item))
        }
        return words
    }

    private func carouselWord(_ word: CarouselWord, width: CGFloat) -> some View {
        Text(word.item.translation)
            .font(.system(size: 36, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .lineLimit(word.slot == .current ? 3 : 2)
            .minimumScaleFactor(0.65)
            .frame(width: width)
            .scaleEffect(wordScale(for: word.slot))
            .foregroundStyle(word.slot == .current ? .primary : .secondary)
            .opacity(wordOpacity(for: word.slot))
            .zIndex(word.slot == .current ? 1 : 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: word))
            .accessibilityIdentifier(accessibilityIdentifier(for: word.slot))
    }

    @ViewBuilder
    private func carouselControls(width: CGFloat, height: CGFloat) -> some View {
        if translations.previousTranslation != nil {
            Image(systemName: "arrow.left")
                .foregroundStyle(.secondary)
                .position(x: 10, y: height / 2)
                .accessibilityHidden(true)
        }

        if translations.nextTranslation != nil {
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .position(x: width - 10, y: height / 2)
                .accessibilityHidden(true)
        }

        if let previous = translations.previousLanguage {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up")
                Text(previous.language.label.uppercased())
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .opacity(0.55)
            .position(x: width / 2, y: 10)
            .accessibilityHidden(true)
        }

        if let current = translations.current {
            Text(current.language.label.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .position(x: width / 2, y: height / 2 - 35)
                .accessibilityIdentifier("review.language.current")
        }

        if let next = translations.nextLanguage {
            HStack(spacing: 5) {
                Text(next.language.label.uppercased())
                Image(systemName: "arrow.down")
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .opacity(0.55)
            .position(x: width / 2, y: height - 10)
            .accessibilityHidden(true)
        }
    }

    private func wordX(
        for slot: CarouselSlot,
        width: CGFloat,
        horizontalOffset: CGFloat
    ) -> CGFloat {
        switch slot {
        case .previousTranslation: width / 2 - horizontalOffset
        case .nextTranslation: width / 2 + horizontalOffset
        case .previousLanguage, .current, .nextLanguage: width / 2
        }
    }

    private func wordY(for slot: CarouselSlot, height: CGFloat) -> CGFloat {
        switch slot {
        case .previousLanguage: 32
        case .nextLanguage: height - 32
        case .previousTranslation, .current, .nextTranslation: height / 2
        }
    }

    private func wordScale(for slot: CarouselSlot) -> CGFloat {
        switch slot {
        case .current: 1
        case .previousTranslation, .nextTranslation: 0.56
        case .previousLanguage, .nextLanguage: 0.43
        }
    }

    private func wordOpacity(for slot: CarouselSlot) -> Double {
        switch slot {
        case .current: 1
        case .previousTranslation, .nextTranslation: 0.45
        case .previousLanguage, .nextLanguage: 0.38
        }
    }

    private func accessibilityIdentifier(for slot: CarouselSlot) -> String {
        switch slot {
        case .previousLanguage: "review.translation.language-previous"
        case .previousTranslation: "review.translation.previous"
        case .current: "review.translation.current"
        case .nextTranslation: "review.translation.next"
        case .nextLanguage: "review.translation.language-next"
        }
    }

    private func accessibilityLabel(for word: CarouselWord) -> String {
        switch word.slot {
        case .previousLanguage, .nextLanguage:
            "\(word.item.language.label): \(word.item.translation)"
        case .previousTranslation, .current, .nextTranslation:
            word.item.translation
        }
    }

    private var statsBar: some View {
        HStack(spacing: 20) {
            Picker("List", selection: Binding(
                get: { state.selectedListID },
                set: { state.selectWordList($0) }
            )) {
                ForEach(state.wordLists) { list in Text(list.name).tag(list.id) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 180)
            .accessibilityIdentifier("review.list-picker")

            Picker("Mode", selection: $mode) {
                ForEach(ReviewTestMode.allCases) { testMode in
                    Text(testMode.title).tag(testMode)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 230)
            .help("Switch modes with Command-[ and Command-]")
            .accessibilityIdentifier("review.mode")

            stat(state.stats.dueCards, "Due")
            stat(state.stats.reviewsToday, "Today")
            stat(state.stats.streakDays, "Day streak")
            Spacer()
            Button(state.isReviewingAll ? "Due Only" : "Review All") {
                if state.isReviewingAll { state.showDueReviews() }
                else { state.startReviewAll() }
            }
            .disabled(state.stats.totalCards == 0)
            .accessibilityIdentifier("review.scope")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private var emptyReviewTitle: String {
        if !state.reviewCards.isEmpty { return "No matching cards" }
        return state.isReviewingAll ? "Review complete" : "All caught up"
    }

    private var emptyReviewDetail: String {
        if !state.reviewCards.isEmpty {
            return switch mode {
            case .gender: "No remaining nouns have a known singular gender. Switch modes with ⌘[ or ⌘]."
            case .conjugation: "No remaining cards are verbs with a usable conjugation. Switch modes with ⌘[ or ⌘]."
            case .plural: "No remaining nouns have a known plural. Switch modes with ⌘[ or ⌘]."
            case .germanToEnglish, .germanToEnglishWriting: "No remaining cards have an English meaning. Switch modes with ⌘[ or ⌘]."
            case .flashcard, .writing, .speaking: "No remaining cards can use this mode. Switch modes with ⌘[ or ⌘]."
            }
        }
        if state.stats.totalCards == 0 {
            return "Search for a word or phrase in Dictionary to start learning."
        }
        return state.isReviewingAll ? "You reviewed every active card in this list." : "No cards are due right now. You can still review the whole list."
    }

    private func stat(_ number: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(number.formatted()).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func ratingBar(_ card: PersonalCard) -> some View {
        HStack(spacing: 10) {
            ForEach(ReviewRating.allCases, id: \.rawValue) { rating in
                Button {
                    rate(card, rating)
                } label: {
                    VStack(spacing: 3) {
                        Text(rating.label).fontWeight(.semibold)
                        Image(systemName: "\(rating.rawValue).square")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 82)
                }
                .buttonStyle(.bordered)
                .tint(rating == .again ? .red : rating == .easy ? .green : .accentColor)
                .keyboardShortcut(KeyEquivalent(Character(String(rating.rawValue))), modifiers: [])
                .focusable()
                .focused($focusedAction, equals: .rating(rating.rawValue))
                .accessibilityIdentifier("review.rating.\(rating.rawValue)")
                .accessibilityLabel("\(rating.label), shortcut \(rating.rawValue)")
            }
        }
        .padding(.bottom, 12)
    }

    private func compactInfo(for card: PersonalCard) -> some View {
        let info = GermanMorphology.info(for: entry(for: card))
        return VStack(spacing: 5) {
            ForEach(EntryDetailInfoRows.supplemental(from: info.rows).prefix(3)) { row in
                HStack {
                    Text(row.label).foregroundStyle(.secondary)
                    Text(GermanTextPresentation.hyphenated(row.value))
                        .fontWeight(.medium)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
            }
        }
    }

    private func entry(for card: PersonalCard) -> DictionaryEntry {
        .init(
            id: card.dictionaryEntryID ?? 0,
            german: card.german,
            english: card.english,
            rawGerman: card.rawGerman,
            kind: card.kind,
            gender: card.gender,
            source: "My words",
            pluralForms: card.pluralForms,
            meanings: card.resolvedMeanings,
            forms: card.forms
        )
    }

    private func rate(_ card: PersonalCard, _ rating: ReviewRating) {
        resetResponse()
        state.rate(card, rating)
    }

    private func submit(_ value: String) {
        guard let challenge else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        answer = trimmed
        submittedAnswer = trimmed
        answerWasCorrect = challenge.accepts(trimmed)
        revealed = true
        if mode.usesSpeech, speech.isListening { speech.stop() }
    }

    private func resetResponse() {
        if mode.usesSpeech { speech.reset() }
        revealed = false
        answer = ""
        submittedAnswer = nil
        answerWasCorrect = nil
    }

    private func resetTranslations(for card: PersonalCard?) {
        translations = ReviewTranslationCarousel(
            cardEnglish: card?.english ?? "",
            dictionaryMeanings: card?.resolvedMeanings ?? []
        )
        carouselWordIDs = CarouselWordIDs()
        state.prepareReviewTranslations(for: card)
    }

    private func updateGermanSpeechTarget() {
        let germanIsVisible = revealed || !mode.usesTranslationCarousel
        germanSpeech.setTarget(germanIsVisible ? current?.german : nil, in: .review)
    }

    private func focusPrimaryAction() {
        let action = current == nil
            ? FocusedAction.restart
            : revealed ? .rating(suggestedRating.rawValue) : primaryFocusedAction

        focusedAction = nil
        DispatchQueue.main.async {
            focusedAction = action
        }
    }

    private func focusCarousel() {
        guard current != nil else {
            focusPrimaryAction()
            return
        }
        guard mode.usesTranslationCarousel, !mode.requiresWrittenAnswer, !mode.usesSpeech else {
            focusPrimaryAction()
            return
        }
        focusedAction = nil
        DispatchQueue.main.async { focusedAction = .carousel }
    }

    private var primaryFocusedAction: FocusedAction {
        if mode.requiresWrittenAnswer { return .answer }
        if mode.usesSpeech { return .speech }
        if mode.usesGenderChoices { return .gender(0) }
        return .reveal
    }

    private var suggestedRating: ReviewRating {
        switch answerWasCorrect {
        case .some(true): .good
        case .some(false): .again
        case .none: .again
        }
    }

    private var writtenAnswerPlaceholder: String {
        switch mode {
        case .germanToEnglishWriting: "Type the English meaning"
        case .conjugation: "Type the conjugated form"
        case .plural: "Type the plural form"
        case .writing: "Type the German word"
        case .flashcard, .speaking, .gender, .germanToEnglish: "Type your answer"
        }
    }

    private var speechControlTitle: String {
        switch speech.phase {
        case .listening: "Stop and check"
        case .processing: "Recognizing…"
        case .guess: "Speak again"
        case .requestingPermission: "Requesting access…"
        case .idle, .unavailable: "Start speaking"
        }
    }

    private var speechStatusText: String {
        switch speech.phase {
        case .idle: "Speak the German word"
        case .requestingPermission: "Checking speech access…"
        case .listening: "Listening…"
        case .processing: "Recognizing…"
        case .guess: "Ready to check"
        case .unavailable(let message): message
        }
    }

    private func toggleSpeechRecognition() {
        switch speech.phase {
        case .listening:
            speech.stop()
        case .idle:
            speech.start()
        case .guess, .unavailable:
            speech.rerecord()
        case .requestingPermission, .processing:
            break
        }
    }

    private static let genderChoices: [Gender] = [.masculine, .feminine, .neuter]
}

extension Notification.Name {
    static let focusReviewContent = Notification.Name("focusReviewContent")
    static let previousReviewMode = Notification.Name("previousReviewMode")
    static let nextReviewMode = Notification.Name("nextReviewMode")
}

struct ReviewTranslationCarousel: Equatable {
    struct Item: Equatable {
        let language: TranslationLanguage
        let translation: String
    }

    private struct Group: Equatable {
        let language: TranslationLanguage
        let translations: [String]
    }

    private var groups: [Group] = []
    private var languageIndex = 0
    private var translationIndices: [TranslationLanguage: Int] = [:]

    init(
        cardEnglish: String = "",
        dictionaryMeanings: [DictionaryMeaning] = []
    ) {
        replace(cardEnglish: cardEnglish, dictionaryMeanings: dictionaryMeanings)
    }

    var current: Item? { item(languageIndex: languageIndex) }
    var previousTranslation: Item? { translation(offset: -1) }
    var nextTranslation: Item? { translation(offset: 1) }
    var previousLanguage: Item? { language(offset: -1) }
    var nextLanguage: Item? { language(offset: 1) }

    var hasMultipleTranslations: Bool {
        guard groups.indices.contains(languageIndex) else { return false }
        return groups[languageIndex].translations.count > 1
    }

    var hasMultipleLanguages: Bool { groups.count > 1 }

    mutating func replace(
        cardEnglish: String,
        dictionaryMeanings: [DictionaryMeaning]
    ) {
        let previousLanguage = current?.language ?? .english
        var values: [TranslationLanguage: [String]] = [:]
        let allCardTranslations = TranslationPresentation.items(from: cardEnglish)
        let dictionaryEnglish = Set(dictionaryMeanings.lazy
            .filter { $0.language == .english }
            .flatMap { TranslationPresentation.items(from: $0.translation) })
        let dictionaryNonEnglish = Set(dictionaryMeanings.lazy
            .filter { $0.language != .english }
            .flatMap { TranslationPresentation.items(from: $0.translation) })
        let cardTranslations = allCardTranslations.filter {
            dictionaryEnglish.contains($0) || !dictionaryNonEnglish.contains($0)
        }
        if !cardTranslations.isEmpty { values[.english] = cardTranslations }

        for meaning in dictionaryMeanings {
            if meaning.language == .english, !cardTranslations.isEmpty { continue }
            Self.append(meaning.translation, to: meaning.language, in: &values)
        }

        groups = TranslationLanguage.allCases.compactMap { language in
            guard let translations = values[language], !translations.isEmpty else { return nil }
            return Group(language: language, translations: translations)
        }

        translationIndices = translationIndices.reduce(into: [:]) { result, selection in
            guard let group = groups.first(where: { $0.language == selection.key }) else { return }
            result[selection.key] = min(selection.value, group.translations.count - 1)
        }
        for group in groups where translationIndices[group.language] == nil {
            translationIndices[group.language] = 0
        }
        languageIndex = groups.firstIndex(where: { $0.language == previousLanguage })
            ?? groups.firstIndex(where: { $0.language == .english })
            ?? 0
    }

    mutating func moveTranslation(by offset: Int) {
        guard groups.indices.contains(languageIndex) else { return }
        let group = groups[languageIndex]
        guard group.translations.count > 1 else { return }
        let currentIndex = translationIndices[group.language] ?? 0
        translationIndices[group.language] = Self.wrapped(
            currentIndex + offset,
            count: group.translations.count
        )
    }

    mutating func moveLanguage(by offset: Int) {
        guard groups.count > 1 else { return }
        languageIndex = Self.wrapped(languageIndex + offset, count: groups.count)
    }

    private func translation(offset: Int) -> Item? {
        guard groups.indices.contains(languageIndex) else { return nil }
        let group = groups[languageIndex]
        guard group.translations.count > 1 else { return nil }
        let selectedIndex = translationIndices[group.language] ?? 0
        let index = Self.wrapped(selectedIndex + offset, count: group.translations.count)
        return Item(language: group.language, translation: group.translations[index])
    }

    private func language(offset: Int) -> Item? {
        guard groups.count > 1 else { return nil }
        return item(languageIndex: Self.wrapped(languageIndex + offset, count: groups.count))
    }

    private func item(languageIndex: Int) -> Item? {
        guard groups.indices.contains(languageIndex) else { return nil }
        let group = groups[languageIndex]
        let translationIndex = min(
            translationIndices[group.language] ?? 0,
            group.translations.count - 1
        )
        return Item(language: group.language, translation: group.translations[translationIndex])
    }

    private static func append(
        _ value: String,
        to language: TranslationLanguage,
        in values: inout [TranslationLanguage: [String]]
    ) {
        for translation in TranslationPresentation.items(from: value) {
            if values[language, default: []].contains(translation) { continue }
            values[language, default: []].append(translation)
        }
    }

    private static func wrapped(_ index: Int, count: Int) -> Int {
        ((index % count) + count) % count
    }
}
