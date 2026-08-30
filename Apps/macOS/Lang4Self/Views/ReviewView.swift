import SwiftUI
import Lang4SelfCore

struct ReviewView: View {
    @EnvironmentObject private var state: AppState
    @State private var revealed = false
    @State private var translations = ReviewTranslationCarousel()
    @State private var carouselWordIDs = CarouselWordIDs()
    @FocusState private var focusedAction: FocusedAction?
    let automaticallyFocusContent: Bool

    private enum FocusedAction: Hashable {
        case reveal
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

    private var current: PersonalCard? { state.reviewCards.first }

    var body: some View {
        VStack(spacing: 0) {
            statsBar
            Divider()

            if let card = current {
                VStack(spacing: 24) {
                    Spacer()
                    Text("TRANSLATIONS → GERMAN")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    PartOfSpeechBadge(kind: card.kind)
                        .accessibilityIdentifier("review.part-of-speech")
                    translationCarousel

                    if revealed {
                        Divider().frame(maxWidth: 460)
                        GermanWordView(entry: entry(for: card), font: .system(size: 32, weight: .bold))
                        compactInfo(for: card)
                    } else {
                        Button("Show answer  Space") { revealed = true }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .keyboardShortcut(.space, modifiers: [])
                            .focusable()
                            .focused($focusedAction, equals: .reveal)
                            .accessibilityIdentifier("review.reveal")
                    }
                    Spacer()

                    if revealed { ratingBar(card) }
                }
                .padding(32)
            } else {
                VStack(spacing: 0) {
                    PlaceholderView(
                        symbol: "checkmark.circle",
                        title: state.isReviewingAll ? "Review complete" : "All caught up",
                        detail: emptyReviewDetail
                    )
                    if state.stats.totalCards > 0 {
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
        .navigationTitle("Review")
        .onAppear {
            Task { await state.refreshStudyData() }
            resetTranslations(for: current)
            if automaticallyFocusContent { focusPrimaryAction() }
        }
        .onDisappear { state.stopPreparingReviewTranslations() }
        .onChange(of: current?.id) { _, _ in
            revealed = false
            resetTranslations(for: current)
            if automaticallyFocusContent || focusedAction != nil { focusPrimaryAction() }
        }
        .onChange(of: state.reviewDictionaryMeanings) { _, meanings in
            guard let card = current,
                  state.reviewDictionaryMeaningsCardID == card.id
            else { return }
            translations.replace(cardEnglish: card.english, dictionaryMeanings: meanings)
        }
        .onChange(of: state.selectedListID) { _, _ in revealed = false }
        .onChange(of: state.isReviewingAll) { _, _ in revealed = false }
        .onChange(of: revealed) { _, isRevealed in
            DispatchQueue.main.async {
                focusedAction = isRevealed ? .rating(ReviewRating.allCases.first?.rawValue ?? 1) : .reveal
            }
        }
        .onKeyPress(.leftArrow) {
            guard translations.hasMultipleTranslations else { return .ignored }
            withAnimation(.snappy) {
                translations.moveTranslation(by: -1)
                carouselWordIDs.moveTranslation(by: -1)
            }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard translations.hasMultipleTranslations else { return .ignored }
            withAnimation(.snappy) {
                translations.moveTranslation(by: 1)
                carouselWordIDs.moveTranslation(by: 1)
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard translations.hasMultipleLanguages else { return .ignored }
            withAnimation(.snappy) {
                translations.moveLanguage(by: -1)
                carouselWordIDs.moveLanguage(by: -1)
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard translations.hasMultipleLanguages else { return .ignored }
            withAnimation(.snappy) {
                translations.moveLanguage(by: 1)
                carouselWordIDs.moveLanguage(by: 1)
            }
            return .handled
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

    private var emptyReviewDetail: String {
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
                    Text(row.value).fontWeight(.medium)
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
            meanings: card.resolvedMeanings,
            forms: card.forms
        )
    }

    private func rate(_ card: PersonalCard, _ rating: ReviewRating) {
        revealed = false
        state.rate(card, rating)
    }

    private func resetTranslations(for card: PersonalCard?) {
        translations = ReviewTranslationCarousel(
            cardEnglish: card?.english ?? "",
            dictionaryMeanings: card?.resolvedMeanings ?? []
        )
        carouselWordIDs = CarouselWordIDs()
        state.prepareReviewTranslations(for: card)
    }

    private func focusPrimaryAction() {
        DispatchQueue.main.async {
            focusedAction = current == nil ? .restart : .reveal
        }
    }
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
