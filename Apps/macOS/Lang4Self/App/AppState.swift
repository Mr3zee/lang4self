import Foundation
import SwiftUI
import Lang4SelfCore

enum AppRoute: String, CaseIterable, Identifiable {
    case dictionary
    case speak
    case review
    case library
    case sentences
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictionary: "Dictionary"
        case .speak: "Speak"
        case .review: "Review"
        case .library: "My words"
        case .sentences: "Sentences"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .dictionary: "character.book.closed"
        case .speak: "waveform"
        case .review: "rectangle.on.rectangle.angled"
        case .library: "books.vertical"
        case .sentences: "text.quote"
        case .settings: "gearshape"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var route: AppRoute = .dictionary
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [DictionaryEntry] = []
    @Published var selectedEntry: DictionaryEntry?
    @Published private(set) var wordLists: [WordList] = []
    @Published private(set) var selectedListID: WordList.ID = WordList.defaultID
    @Published private(set) var cards: [PersonalCard] = []
    @Published private(set) var dueCards: [PersonalCard] = []
    @Published private(set) var reviewCards: [PersonalCard] = []
    @Published private(set) var isReviewingAll = false
    @Published private(set) var stats = StudyStats()
    @Published private(set) var dictionaryCount = 0
    @Published private(set) var hasCompleteDictionary = false
    @Published private(set) var installedTranslationLanguages: Set<TranslationLanguage> = []
    @Published private(set) var explanationCount = 0
    @Published private(set) var importProgress: ImportProgress?
    @Published private(set) var isImporting = false
    @Published private(set) var explanationImportProgress: ExplanationImportProgress?
    @Published private(set) var isImportingExplanations = false
    @Published private(set) var banner: String?
    @Published var libraryQuery = ""
    @Published private(set) var savedSentences: [SavedSentence] = []
    @Published private(set) var generatedSentences: [SentenceDraft] = []
    @Published private(set) var selectedGeneratedSentenceIDs: Set<SentenceDraft.ID> = []
    @Published private(set) var generatedSourceList: WordList?
    @Published private(set) var lmStudioProgress: LMStudioProgress = .idle
    @Published private(set) var isGeneratingSentences = false
    @Published private(set) var installedLMStudioModels: [LMStudioModel] = []
    @Published private(set) var isRefreshingLMStudioModels = false
    @Published private(set) var lmStudioSettings = LMStudioSettings.load()
    @Published var isShowingKeyboardShortcuts = false

    let store: LocalStore
    private var searchTask: Task<Void, Never>?
    private var libraryTask: Task<Void, Never>?
    private var sentenceGenerationTask: Task<Void, Never>?
    private var bannerDismissTask: Task<Void, Never>?
    private let lmStudio = LMStudioService.shared
    private let isUITesting: Bool

    var selectedWordList: WordList? { wordLists.first { $0.id == selectedListID } }

    init(store: LocalStore? = nil) throws {
        self.store = try store ?? LocalStore()
        self.isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        if isUITesting { lmStudioSettings = .defaults }
        lmStudio.progressDidChange = { [weak self] progress in
            self?.lmStudioProgress = progress
        }
        Task { await bootstrap() }
    }

    func bootstrap() async {
        do {
            try await store.seedStarterDictionaryIfNeeded()
            if isUITesting { try await seedUITestDataIfNeeded() }
            async let count = store.dictionaryCount()
            async let complete = store.hasCompleteDictionary()
            async let languages = store.installedTranslationLanguages()
            async let explanations = store.explanationCount()
            async let loadedLists = store.wordLists()
            async let loadedCards = store.cards(listID: selectedListID)
            async let loadedDue = store.dueCards(listID: selectedListID)
            async let loadedStats = store.stats(listID: selectedListID)
            async let loadedSentences = store.savedSentences()
            dictionaryCount = try await count
            hasCompleteDictionary = try await complete
            installedTranslationLanguages = try await languages
            explanationCount = try await explanations
            wordLists = try await loadedLists
            cards = try await loadedCards
            dueCards = try await loadedDue
            reviewCards = dueCards
            stats = try await loadedStats
            savedSentences = try await loadedSentences
        } catch {
            show(error)
        }
    }

    private func seedUITestDataIfNeeded() async throws {
        guard try await store.cards().isEmpty else { return }

        var fixtureCards: [PersonalCard] = []
        for term in ["Haus", "lernen"] {
            if let entry = try await store.searchDictionary(term, limit: 1).first {
                fixtureCards.append(try await store.addCard(from: entry))
            }
        }

        let travel = try await store.createWordList(name: "Travel")
        if let house = fixtureCards.first {
            try await store.addCard(house.id, toList: travel.id)
        }

        let savedGerman = "Das Kind liest ein Buch."
        let saved = SentenceDraft(
            german: savedGerman,
            translation: "The child reads a book.",
            tokens: SentenceTokenizer.tokens(in: savedGerman)
        )
        _ = try await store.saveSentences([saved], sourceList: travel)

        let generatedGerman = "Das Haus ist groß."
        let generatedLearning = "Wir lernen jeden Tag."
        generatedSentences = [
            SentenceDraft(
                german: generatedGerman,
                translation: "The house is big.",
                tokens: SentenceTokenizer.tokens(in: generatedGerman)
            ),
            SentenceDraft(
                german: generatedLearning,
                translation: "We learn every day.",
                tokens: SentenceTokenizer.tokens(in: generatedLearning)
            )
        ]
        selectedGeneratedSentenceIDs = Set(generatedSentences.map(\.id))
        generatedSourceList = WordList(id: WordList.defaultID, name: "My words")
    }

    func search(_ value: String, immediate: Bool = false) {
        searchQuery = value
        searchTask?.cancel()
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            selectedEntry = nil
            return
        }
        searchTask = Task {
            if !immediate { try? await Task.sleep(nanoseconds: 160_000_000) }
            guard !Task.isCancelled else { return }
            do {
                let results = try await store.searchDictionary(value)
                guard !Task.isCancelled else { return }
                searchResults = results
                if selectedEntry == nil || !results.contains(where: { $0.id == selectedEntry?.id }) {
                    selectedEntry = results.first
                }
            } catch {
                show(error)
            }
        }
    }

    func addToPersonalDictionary(_ entry: DictionaryEntry, announce: Bool = true) {
        let listID = selectedListID
        let listName = wordLists.first { $0.id == listID }?.name ?? "My words"
        Task {
            do {
                _ = try await store.addCard(from: entry, listID: listID)
                await refreshStudyData()
                if announce { showBanner("Added “\(entry.german)” to \(listName)") }
            } catch {
                show(error)
            }
        }
    }

    func confirmSpokenEntry() {
        guard let selectedEntry else { return }
        addToPersonalDictionary(selectedEntry)
    }

    func loadLibrary(search: String? = nil) {
        if let search { libraryQuery = search }
        libraryTask?.cancel()
        let query = libraryQuery
        let listID = selectedListID
        libraryTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            do {
                let loadedCards = try await store.cards(search: query, listID: listID)
                guard !Task.isCancelled, selectedListID == listID else { return }
                cards = loadedCards
            }
            catch { show(error) }
        }
    }

    func selectWordList(_ id: WordList.ID) {
        guard id != selectedListID, wordLists.contains(where: { $0.id == id }) else { return }
        selectedListID = id
        isReviewingAll = false
        cards = []
        dueCards = []
        reviewCards = []
        stats = StudyStats()
        libraryTask?.cancel()
        Task { await refreshStudyData() }
    }

    func createWordList(name: String) {
        Task {
            do {
                let list = try await store.createWordList(name: name)
                wordLists = try await store.wordLists()
                selectedListID = list.id
                isReviewingAll = false
                libraryQuery = ""
                cards = []
                dueCards = []
                reviewCards = []
                stats = StudyStats()
                await refreshStudyData()
                showBanner("Created “\(list.name)”")
            } catch { show(error) }
        }
    }

    func renameSelectedWordList(to name: String) {
        let listID = selectedListID
        Task {
            do {
                try await store.renameWordList(id: listID, name: name)
                wordLists = try await store.wordLists()
            } catch { show(error) }
        }
    }

    func deleteSelectedWordList() {
        let listID = selectedListID
        guard listID != WordList.defaultID else { return }
        Task {
            do {
                try await store.deleteWordList(id: listID)
                wordLists = try await store.wordLists()
                selectedListID = WordList.defaultID
                isReviewingAll = false
                libraryQuery = ""
                cards = []
                dueCards = []
                reviewCards = []
                stats = StudyStats()
                await refreshStudyData()
                showBanner("Deleted list")
            } catch { show(error) }
        }
    }

    func updateCard(_ card: PersonalCard) {
        Task {
            do {
                try await store.updateCard(card)
                if let index = cards.firstIndex(where: { $0.id == card.id }) { cards[index] = card }
                await refreshStudyData()
            } catch { show(error) }
        }
    }

    func removeCardFromSelectedList(_ card: PersonalCard) {
        let listID = selectedListID
        let listName = selectedWordList?.name ?? "list"
        Task {
            do {
                try await store.removeCard(card.id, fromList: listID)
                if selectedListID == listID { cards.removeAll { $0.id == card.id } }
                await refreshStudyData()
                showBanner("Removed “\(card.german)” from \(listName)")
            } catch { show(error) }
        }
    }

    func addCard(_ card: PersonalCard, to list: WordList) {
        Task {
            do {
                try await store.addCard(card.id, toList: list.id)
                showBanner("Added “\(card.german)” to \(list.name)")
            } catch { show(error) }
        }
    }

    func startReviewAll() {
        let listID = selectedListID
        Task {
            do {
                let loadedCards = try await store.reviewCards(listID: listID)
                guard selectedListID == listID else { return }
                isReviewingAll = true
                reviewCards = loadedCards
            } catch { show(error) }
        }
    }

    func showDueReviews() {
        isReviewingAll = false
        let listID = selectedListID
        Task {
            do {
                let loadedDue = try await store.dueCards(listID: listID)
                guard selectedListID == listID else { return }
                dueCards = loadedDue
                reviewCards = loadedDue
            } catch { show(error) }
        }
    }

    func rate(_ card: PersonalCard, _ rating: ReviewRating) {
        Task {
            do {
                _ = try await store.review(card: card, rating: rating)
                dueCards.removeAll { $0.id == card.id }
                reviewCards.removeAll { $0.id == card.id }
                await refreshStudyData()
            } catch { show(error) }
        }
    }

    func importDictionary(from url: URL) {
        guard !isImporting else { return }
        isImporting = true
        importProgress = .init(imported: 0, bytesRead: 0, totalBytes: 1)
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let prepared = try await DictionaryArchive.prepare(url)
                defer { prepared.cleanUp() }
                let imported = try await store.importDictionary(from: prepared.url) { progress in
                    Task { @MainActor [weak self] in self?.importProgress = progress }
                }
                dictionaryCount = try await store.dictionaryCount()
                hasCompleteDictionary = try await store.hasCompleteDictionary()
                installedTranslationLanguages = try await store.installedTranslationLanguages()
                isImporting = false
                importProgress = nil
                showBanner("Imported \(imported.formatted()) dictionary entries")
            } catch {
                isImporting = false
                importProgress = nil
                show(error)
            }
        }
    }

    func importExplanations(from url: URL) {
        guard !isImportingExplanations else { return }
        isImportingExplanations = true
        explanationImportProgress = .init(imported: 0, total: 1)
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let imported = try await store.importExplanations(from: url) { progress in
                    Task { @MainActor [weak self] in self?.explanationImportProgress = progress }
                }
                explanationCount = try await store.explanationCount()
                isImportingExplanations = false
                explanationImportProgress = nil
                if !searchQuery.isEmpty { search(searchQuery, immediate: true) }
                showBanner("Imported \(imported.formatted()) explanations")
            } catch {
                isImportingExplanations = false
                explanationImportProgress = nil
                show(error)
            }
        }
    }

    func generateSentences(count: Int) {
        guard !isGeneratingSentences, let sourceList = selectedWordList else { return }
        if isUITesting {
            let examples = [
                ("Das Haus hat ein rotes Dach.", "The house has a red roof."),
                ("Wir lernen jeden Morgen Deutsch.", "We learn German every morning."),
                ("Das Kind liest ein interessantes Buch.", "The child reads an interesting book."),
                ("Heute ist das Wetter sehr schön.", "The weather is very nice today."),
                ("Ich trinke gern heißen Tee.", "I like drinking hot tea."),
                ("Der Zug kommt pünktlich an.", "The train arrives on time."),
                ("Sie kauft frisches Brot.", "She buys fresh bread."),
                ("Am Abend kochen wir zusammen.", "In the evening we cook together."),
                ("Mein Freund wohnt in Berlin.", "My friend lives in Berlin."),
                ("Morgen besuchen wir das Museum.", "Tomorrow we visit the museum.")
            ]
            generatedSentences = examples.prefix(count).map { german, translation in
                SentenceDraft(
                    german: german,
                    translation: translation,
                    tokens: SentenceTokenizer.tokens(in: german)
                )
            }
            selectedGeneratedSentenceIDs = Set(generatedSentences.map(\.id))
            generatedSourceList = sourceList
            return
        }
        sentenceGenerationTask?.cancel()
        isGeneratingSentences = true
        sentenceGenerationTask = Task {
            do {
                let vocabulary = try await store.cards(listID: sourceList.id, limit: 600)
                guard !vocabulary.isEmpty else { throw SentenceFeatureError.emptyWordList }
                let drafts = try await lmStudio.generate(
                    vocabulary: vocabulary,
                    count: count,
                    settings: lmStudioSettings
                )
                try Task.checkCancellation()
                generatedSentences = drafts
                selectedGeneratedSentenceIDs = Set(drafts.map(\.id))
                generatedSourceList = sourceList
            } catch is CancellationError {
                // Closing the app or replacing the task is an expected cancellation.
            } catch {
                show(error)
            }
            isGeneratingSentences = false
            sentenceGenerationTask = nil
        }
    }

    func setGeneratedSentence(_ id: SentenceDraft.ID, selected: Bool) {
        if selected { selectedGeneratedSentenceIDs.insert(id) }
        else { selectedGeneratedSentenceIDs.remove(id) }
    }

    func selectAllGeneratedSentences(_ selected: Bool) {
        selectedGeneratedSentenceIDs = selected ? Set(generatedSentences.map(\.id)) : []
    }

    func saveSelectedGeneratedSentences() {
        guard let sourceList = generatedSourceList else { return }
        let selected = generatedSentences.filter { selectedGeneratedSentenceIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        let selectedIDs = Set(selected.map(\.id))
        Task {
            do {
                let inserted = try await store.saveSentences(selected, sourceList: sourceList)
                savedSentences = try await store.savedSentences()
                generatedSentences.removeAll { selectedIDs.contains($0.id) }
                selectedGeneratedSentenceIDs.subtract(selectedIDs)
                if inserted.isEmpty {
                    showBanner("These sentences were already saved")
                } else {
                    showBanner("Saved \(inserted.count) sentence\(inserted.count == 1 ? "" : "s")")
                }
            } catch { show(error) }
        }
    }

    func deleteSentence(_ sentence: SavedSentence) {
        Task {
            do {
                try await store.deleteSentence(id: sentence.id)
                savedSentences.removeAll { $0.id == sentence.id }
                showBanner("Deleted sentence")
            } catch { show(error) }
        }
    }

    func refreshLMStudioModels() {
        guard !isRefreshingLMStudioModels else { return }
        if isUITesting {
            installedLMStudioModels = [
                LMStudioModel(
                    type: "llm",
                    modelKey: "lang4self/ui-test-model",
                    displayName: "UI Test Model",
                    sizeBytes: 1_000_000_000,
                    paramsString: "1B",
                    quantization: nil,
                    maxContextLength: 131_072
                )
            ]
            return
        }
        isRefreshingLMStudioModels = true
        Task {
            do {
                installedLMStudioModels = try await lmStudio.installedModels()
            } catch {
                show(error)
            }
            isRefreshingLMStudioModels = false
        }
    }

    func updateLMStudioSettings(_ settings: LMStudioSettings) {
        lmStudioSettings = settings.sanitized
        if !isUITesting { lmStudioSettings.save() }
    }

    var configuredLMStudioModel: LMStudioModel? {
        if lmStudioSettings.modelKey.isEmpty { return installedLMStudioModels.first }
        return installedLMStudioModels.first { $0.modelKey == lmStudioSettings.modelKey }
    }

    func translationEntries(for token: SentenceToken) async -> [DictionaryEntry] {
        do {
            var entries: [DictionaryEntry] = []
            if let cardID = token.cardID, let card = try await store.personalCard(id: cardID) {
                entries.append(.init(
                    id: card.dictionaryEntryID ?? 0,
                    german: card.german,
                    english: card.english,
                    rawGerman: card.rawGerman,
                    kind: card.kind,
                    gender: card.gender,
                    source: "My words"
                ))
            }
            let dictionaryEntries = try await store.searchDictionary(token.lookupTerm, limit: 12)
            for entry in dictionaryEntries where !entries.contains(where: {
                $0.id == entry.id ||
                (SentenceTokenizer.normalized($0.german) == SentenceTokenizer.normalized(entry.german) && $0.english == entry.english)
            }) {
                entries.append(entry)
            }
            return entries
        } catch {
            show(error)
            return []
        }
    }

    func refreshStudyData() async {
        let listID = selectedListID
        do {
            async let loadedCards = store.cards(search: libraryQuery, listID: listID)
            async let loadedDue = store.dueCards(listID: listID)
            async let loadedStats = store.stats(listID: listID)
            let (newCards, newDue, newStats) = try await (loadedCards, loadedDue, loadedStats)
            guard selectedListID == listID else { return }
            cards = newCards
            dueCards = newDue
            if !isReviewingAll { reviewCards = newDue }
            stats = newStats
        } catch { show(error) }
    }

    func showBanner(_ message: String) {
        bannerDismissTask?.cancel()
        banner = message
        bannerDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                self?.banner = nil
                self?.bannerDismissTask = nil
            } catch {}
        }
    }

    func dismissBanner() {
        bannerDismissTask?.cancel()
        bannerDismissTask = nil
        banner = nil
    }

    private func show(_ error: Error) {
        showBanner(error.localizedDescription)
    }
}

private enum SentenceFeatureError: LocalizedError {
    case emptyWordList

    var errorDescription: String? {
        "The selected list has no words. Add words before generating sentences."
    }
}
