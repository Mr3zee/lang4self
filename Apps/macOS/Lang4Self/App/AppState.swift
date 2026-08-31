import Foundation
import SwiftUI
import Lang4SelfCore

enum AppRoute: String, CaseIterable, Identifiable {
    case dictionary
    case review
    case library
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictionary: "Dictionary"
        case .review: "Review"
        case .library: "My words"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .dictionary: "character.book.closed"
        case .review: "rectangle.on.rectangle.angled"
        case .library: "books.vertical"
        case .settings: "gearshape"
        }
    }
}

private enum AppUndoError: LocalizedError {
    case mutationNoLongerAvailable

    var errorDescription: String? {
        "That change can no longer be undone."
    }
}

@MainActor
final class AppUndoOperation {
    typealias Perform = @MainActor () async throws -> AppUndoOperation

    let name: String
    private let performBlock: Perform

    init(name: String, perform: @escaping Perform) {
        self.name = name
        self.performBlock = perform
    }

    func perform() async throws -> AppUndoOperation {
        try await performBlock()
    }
}

@MainActor
final class AppUndoHistory: ObservableObject {
    @Published private(set) var undoActionName: String?
    @Published private(set) var redoActionName: String?
    @Published private(set) var isPerforming = false

    private var undoStack: [AppUndoOperation] = []
    private var redoStack: [AppUndoOperation] = []

    var canUndo: Bool { !isPerforming && !undoStack.isEmpty }
    var canRedo: Bool { !isPerforming && !redoStack.isEmpty }

    func record(_ operation: AppUndoOperation) {
        guard !isPerforming else { return }
        undoStack.append(operation)
        redoStack.removeAll()
        publishNames()
    }

    @discardableResult
    func undo() async throws -> String? {
        guard !isPerforming, let operation = undoStack.popLast() else { return nil }
        isPerforming = true
        publishNames()
        do {
            let inverse = try await operation.perform()
            redoStack.append(inverse)
            isPerforming = false
            publishNames()
            return operation.name
        } catch {
            undoStack.append(operation)
            isPerforming = false
            publishNames()
            throw error
        }
    }

    @discardableResult
    func redo() async throws -> String? {
        guard !isPerforming, let operation = redoStack.popLast() else { return nil }
        isPerforming = true
        publishNames()
        do {
            let inverse = try await operation.perform()
            undoStack.append(inverse)
            isPerforming = false
            publishNames()
            return operation.name
        } catch {
            redoStack.append(operation)
            isPerforming = false
            publishNames()
            throw error
        }
    }

    private func publishNames() {
        undoActionName = undoStack.last?.name
        redoActionName = redoStack.last?.name
    }
}

@MainActor
final class AppState: ObservableObject {
    private struct AddedDictionaryEntryPlacement {
        let cardID: PersonalCard.ID
        let listID: WordList.ID
    }

    @Published var route: AppRoute = .dictionary
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [DictionaryEntry] = []
    @Published private(set) var isSearchingDictionary = false
    @Published private(set) var dictionaryTranslationPhase: DictionaryTranslationPhase = .idle
    @Published var selectedEntry: DictionaryEntry?
    @Published private(set) var wordLists: [WordList] = []
    @Published private(set) var selectedListID: WordList.ID = WordList.defaultID
    @Published private(set) var cards: [PersonalCard] = []
    @Published private(set) var dueCards: [PersonalCard] = []
    @Published private(set) var reviewCards: [PersonalCard] = []
    @Published private(set) var reviewDictionaryMeanings: [DictionaryMeaning] = []
    @Published private(set) var reviewDictionaryMeaningsCardID: PersonalCard.ID?
    @Published private(set) var isReviewingAll = false
    @Published private(set) var stats = StudyStats()
    @Published private(set) var dictionaryCount = 0
    @Published private(set) var hasCompleteDictionary = false
    @Published private(set) var installedTranslationLanguages: Set<TranslationLanguage> = []
    @Published private(set) var explanationCount = 0
    @Published private(set) var isBootstrapComplete = false
    @Published private(set) var importProgress: ImportProgress?
    @Published private(set) var isImporting = false
    @Published private(set) var explanationImportProgress: ExplanationImportProgress?
    @Published private(set) var isImportingExplanations = false
    @Published private(set) var banner: String?
    @Published var libraryQuery = ""
    @Published private(set) var sentenceRetries: [SavedSentence] = []
    @Published private(set) var sentencePractice = SentencePracticeSession()
    @Published private(set) var lmStudioProgress: LMStudioProgress = .idle
    @Published private(set) var installedLMStudioModels: [LMStudioModel] = []
    @Published private(set) var isRefreshingLMStudioModels = false
    @Published private(set) var lmStudioSettings: LMStudioSettings
    @Published var isShowingKeyboardShortcuts = false
    @Published private var addedDictionaryEntryPlacements: [DictionaryEntry.ID: AddedDictionaryEntryPlacement] = [:]

    let undoHistory = AppUndoHistory()

    private let store: any AppDataStore
    private let dictionarySearch: any DictionarySearching
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = UUID()
    private var libraryTask: Task<Void, Never>?
    private var reviewDictionaryTask: Task<Void, Never>?
    private var sentenceGenerationTask: Task<Void, Never>?
    private var sentenceGenerationID = UUID()
    private var bannerDismissTask: Task<Void, Never>?
    private var hasBootstrapped = false
    private let lmStudio: any SentenceGenerating
    private let sentenceAnalyzer: any SentenceAnalyzing
    private let dictionaryFilePreparer: any DictionaryFilePreparing
    private let settingsStore: any LMStudioSettingsStoring
    private let isUITesting: Bool
    private let uiTestingDictionaryURLs: [URL]
    private let now: () -> Date
    private let calendar: Calendar

    var selectedWordList: WordList? { wordLists.first { $0.id == selectedListID } }
    var databaseURL: URL { store.databaseURL }
    var isUITestSession: Bool { isUITesting }

    init(
        store: any AppDataStore,
        dictionarySearch: any DictionarySearching,
        sentenceGenerator: any SentenceGenerating,
        sentenceAnalyzer: any SentenceAnalyzing,
        dictionaryFilePreparer: any DictionaryFilePreparing,
        settingsStore: any LMStudioSettingsStoring,
        isUITesting: Bool,
        uiTestingDictionaryURLs: [URL],
        now: @escaping () -> Date,
        calendar: Calendar
    ) {
        self.store = store
        self.dictionarySearch = dictionarySearch
        self.lmStudio = sentenceGenerator
        self.sentenceAnalyzer = sentenceAnalyzer
        self.dictionaryFilePreparer = dictionaryFilePreparer
        self.settingsStore = settingsStore
        self.isUITesting = isUITesting
        self.uiTestingDictionaryURLs = uiTestingDictionaryURLs
        self.now = now
        self.calendar = calendar
        self.lmStudioSettings = isUITesting ? .defaults : settingsStore.load()
        lmStudio.progressDidChange = { [weak self] progress in
            self?.lmStudioProgress = progress
        }
        dictionarySearch.translationPhaseDidChange = { [weak self] phase in
            self?.dictionaryTranslationPhase = phase
        }
    }

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        defer { isBootstrapComplete = true }
        do {
            try await store.seedStarterDictionaryIfNeeded()
            if isUITesting { try await seedUITestDataIfNeeded() }
            async let count = store.dictionaryCount()
            async let complete = store.hasCompleteDictionary()
            async let languages = store.installedTranslationLanguages()
            async let explanations = store.explanationCount()
            async let loadedLists = store.wordLists()
            async let loadedCards = store.cards(listID: selectedListID)
            let currentDate = now()
            async let loadedDue = store.dueCards(listID: selectedListID, limit: 100, now: currentDate)
            async let loadedStats = store.stats(listID: selectedListID, now: currentDate, calendar: calendar)
            async let loadedSentenceRetries = store.savedSentences()
            dictionaryCount = try await count
            hasCompleteDictionary = try await complete
            installedTranslationLanguages = try await languages
            explanationCount = try await explanations
            wordLists = try await loadedLists
            cards = try await loadedCards
            dueCards = try await loadedDue
            reviewCards = dueCards
            stats = try await loadedStats
            sentenceRetries = try await loadedSentenceRetries
        } catch {
            show(error)
        }
    }

    private func seedUITestDataIfNeeded() async throws {
        guard try await store.cards().isEmpty else { return }

        for url in uiTestingDictionaryURLs {
            _ = try await store.importDictionary(from: url)
        }

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
        let generatedSeparable = "Das Blatt fällt ab."
        let separableTokens = SentenceTokenizer.tokens(in: generatedSeparable).map { token in
            guard token.surface == "fällt" else { return token }
            return SentenceToken(
                index: token.index,
                surface: token.surface,
                lookupTerm: "abfallen"
            )
        }
        let sourceList = WordList(id: WordList.defaultID, name: "My words")
        sentencePractice.start(
            mode: .vocabularyBlanks,
            requestedCount: 3,
            retries: [],
            sourceList: sourceList
        )
        sentencePractice.appendGenerated([
            SentenceDraft(
                german: generatedGerman,
                translation: "The house is big.",
                tokens: sentenceTokens(
                    in: generatedGerman,
                    targetSurface: "Haus",
                    card: fixtureCards.first
                )
            ),
            SentenceDraft(
                german: generatedLearning,
                translation: "We learn every day.",
                tokens: sentenceTokens(
                    in: generatedLearning,
                    targetSurface: "lernen",
                    card: fixtureCards.dropFirst().first
                )
            ),
            SentenceDraft(
                german: generatedSeparable,
                translation: "The leaf falls off.",
                tokens: separableTokens
            )
        ])
        sentencePractice.finishGeneration()
    }

    private func sentenceTokens(
        in sentence: String,
        targetSurface: String,
        card: PersonalCard?
    ) -> [SentenceToken] {
        SentenceTokenizer.tokens(in: sentence).map { token in
            guard token.lookupTerm == targetSurface, let card else { return token }
            return SentenceToken(
                index: token.index,
                surface: token.surface,
                lookupTerm: card.german,
                cardID: card.id
            )
        }
    }

    func search(_ value: String, immediate: Bool = false, selectFirstResult: Bool = false) {
        searchQuery = value
        searchTask?.cancel()
        dictionaryTranslationPhase = .idle
        let generation = UUID()
        searchGeneration = generation
        if selectFirstResult { selectedEntry = nil }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            selectedEntry = nil
            isSearchingDictionary = false
            return
        }
        isSearchingDictionary = true
        searchTask = Task {
            if !immediate { try? await Task.sleep(nanoseconds: 160_000_000) }
            guard !Task.isCancelled else { return }
            do {
                let results = try await dictionarySearch.search(value, limit: 80)
                guard !Task.isCancelled, searchGeneration == generation else { return }
                searchResults = results
                if selectFirstResult || selectedEntry == nil || !results.contains(where: { $0.id == selectedEntry?.id }) {
                    selectedEntry = results.first
                }
                isSearchingDictionary = false
            } catch {
                guard searchGeneration == generation else { return }
                isSearchingDictionary = false
                show(error)
            }
        }
    }

    func addToPersonalDictionary(_ entry: DictionaryEntry, announce: Bool = true) {
        guard !undoHistory.isPerforming else { return }
        let listID = selectedListID
        let listName = wordLists.first { $0.id == listID }?.name ?? "My words"
        Task {
            do {
                let addition = if entry.isAppleTranslation {
                    try await store.cacheTranslationAndAddCardRecordingChange(
                        from: entry,
                        listID: listID
                    )
                } else {
                    try await store.addCardRecordingChange(from: entry, listID: listID)
                }
                let card = addition.card
                addedDictionaryEntryPlacements[entry.id] = .init(cardID: card.id, listID: listID)
                await refreshStudyData()
                if addition.didAddToList {
                    undoHistory.record(removeCardOperation(
                        cardID: card.id,
                        listID: listID,
                        actionName: "Add “\(entry.german)”",
                        dictionaryEntryID: entry.id
                    ))
                }
                if announce { showBanner("Added “\(entry.german)” to \(listName)") }
            } catch {
                show(error)
            }
        }
    }

    func addedListID(for entry: DictionaryEntry) -> WordList.ID? {
        guard let placement = addedDictionaryEntryPlacements[entry.id],
              wordLists.contains(where: { $0.id == placement.listID })
        else { return nil }
        return placement.listID
    }

    func switchListForAddedEntry(
        _ entry: DictionaryEntry,
        to destinationListID: WordList.ID
    ) async -> Bool {
        guard !undoHistory.isPerforming else { return false }
        guard let placement = addedDictionaryEntryPlacements[entry.id],
              placement.listID != destinationListID,
              let destination = wordLists.first(where: { $0.id == destinationListID })
        else { return false }

        do {
            try await store.moveCard(
                placement.cardID,
                fromList: placement.listID,
                toList: destinationListID
            )
            guard addedDictionaryEntryPlacements[entry.id]?.cardID == placement.cardID,
                  addedDictionaryEntryPlacements[entry.id]?.listID == placement.listID
            else { return false }
            addedDictionaryEntryPlacements[entry.id] = .init(
                cardID: placement.cardID,
                listID: destinationListID
            )
            undoHistory.record(moveCardOperation(
                cardID: placement.cardID,
                fromListID: destinationListID,
                toListID: placement.listID,
                actionName: "Move “\(entry.german)”",
                dictionaryEntryID: entry.id
            ))
            if selectedListID == destinationListID {
                await refreshStudyData()
            } else {
                selectWordList(destinationListID)
            }
            showBanner("Moved “\(entry.german)” to \(destination.name)")
            return true
        } catch {
            show(error)
            return false
        }
    }

    func createListForAddedEntry(_ entry: DictionaryEntry, named name: String) async -> Bool {
        guard !undoHistory.isPerforming else { return false }
        guard let placement = addedDictionaryEntryPlacements[entry.id] else { return false }

        do {
            let destination = try await store.createWordList(
                name: name,
                movingCard: placement.cardID,
                fromList: placement.listID
            )
            guard addedDictionaryEntryPlacements[entry.id]?.cardID == placement.cardID,
                  addedDictionaryEntryPlacements[entry.id]?.listID == placement.listID
            else { return false }

            wordLists = try await store.wordLists()
            addedDictionaryEntryPlacements[entry.id] = .init(
                cardID: placement.cardID,
                listID: destination.id
            )
            undoHistory.record(moveCardOperation(
                cardID: placement.cardID,
                fromListID: destination.id,
                toListID: placement.listID,
                actionName: "Move “\(entry.german)”",
                dictionaryEntryID: entry.id
            ))
            selectWordList(destination.id)
            showBanner("Created “\(destination.name)” and moved “\(entry.german)”")
            return true
        } catch {
            show(error)
            return false
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
        guard !undoHistory.isPerforming else { return }
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
                undoHistory.record(deleteWordListOperation(
                    listID: list.id,
                    actionName: "Create “\(list.name)”"
                ))
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
        guard !undoHistory.isPerforming else { return }
        let listID = selectedListID
        guard listID != WordList.defaultID else { return }
        Task {
            do {
                let mutation = try await store.deleteWordListRecordingChange(id: listID)
                wordLists = try await store.wordLists()
                selectedListID = WordList.defaultID
                isReviewingAll = false
                libraryQuery = ""
                cards = []
                dueCards = []
                reviewCards = []
                stats = StudyStats()
                await refreshStudyData()
                sentenceRetries = try await store.savedSentences()
                undoHistory.record(restoreWordListOperation(
                    mutation,
                    actionName: "Delete “\(mutation.list.name)”"
                ))
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
        guard !undoHistory.isPerforming else { return }
        let listID = selectedListID
        let listName = selectedWordList?.name ?? "list"
        Task {
            do {
                guard let mutation = try await store.removeCardRecordingChange(
                    card.id,
                    fromList: listID
                ) else { return }
                if selectedListID == listID { cards.removeAll { $0.id == card.id } }
                await refreshStudyData()
                undoHistory.record(restoreCardOperation(
                    mutation,
                    actionName: "Remove “\(card.german)”",
                    dictionaryEntryID: nil
                ))
                showBanner("Removed “\(card.german)” from \(listName)")
            } catch { show(error) }
        }
    }

    func addCard(_ card: PersonalCard, to list: WordList) {
        guard !undoHistory.isPerforming else { return }
        Task {
            do {
                let didAdd = try await store.addCardRecordingChange(card.id, toList: list.id)
                if didAdd {
                    undoHistory.record(removeCardOperation(
                        cardID: card.id,
                        listID: list.id,
                        actionName: "Add “\(card.german)” to “\(list.name)”",
                        dictionaryEntryID: nil
                    ))
                }
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

    func prepareReviewTranslations(for card: PersonalCard?) {
        reviewDictionaryTask?.cancel()
        reviewDictionaryTask = nil
        reviewDictionaryMeaningsCardID = card?.id
        reviewDictionaryMeanings = card?.resolvedMeanings ?? []
        guard let card else { return }
        guard card.meanings == nil else { return }

        reviewDictionaryTask = Task {
            do {
                let entry = try await reviewDictionaryEntry(for: card)
                guard !Task.isCancelled,
                      reviewDictionaryMeaningsCardID == card.id,
                      reviewCards.contains(where: { $0.id == card.id })
                else { return }
                reviewDictionaryMeanings = entry?.meanings ?? []
                reviewDictionaryTask = nil
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, reviewDictionaryMeaningsCardID == card.id else { return }
                reviewDictionaryTask = nil
            }
        }
    }

    func stopPreparingReviewTranslations() {
        reviewDictionaryTask?.cancel()
        reviewDictionaryTask = nil
    }

    private func reviewDictionaryEntry(for card: PersonalCard) async throws -> DictionaryEntry? {
        if let id = card.dictionaryEntryID,
           let entry = try await store.dictionaryEntry(id: id) {
            return entry
        }
        let normalizedGerman = DictCCParser.normalized(card.german)
        return try await store.searchDictionary(card.german, limit: 20).first {
            $0.kind == card.kind && DictCCParser.normalized($0.german) == normalizedGerman
        }
    }

    func showDueReviews() {
        isReviewingAll = false
        let listID = selectedListID
        Task {
            do {
                let loadedDue = try await store.dueCards(listID: listID, limit: 100, now: now())
                guard selectedListID == listID else { return }
                dueCards = loadedDue
                reviewCards = loadedDue
            } catch { show(error) }
        }
    }

    func rate(_ card: PersonalCard, _ rating: ReviewRating) {
        Task {
            do {
                _ = try await store.review(card: card, rating: rating, now: now(), calendar: calendar)
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
                let prepared = try await dictionaryFilePreparer.prepare(url)
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
                showBanner("Imported \(imported.formatted()) explanations and available word forms")
            } catch {
                isImportingExplanations = false
                explanationImportProgress = nil
                show(error)
            }
        }
    }

    func startSentencePractice(
        count requestedCount: Int,
        mode: SentenceTestMode,
        options: SentenceGenerationOptions
    ) {
        guard !sentencePractice.isGenerating, let sourceList = selectedWordList else { return }
        let count = min(max(requestedCount, 1), 50)
        let options = options.sanitized
        sentenceGenerationTask?.cancel()
        let generationID = UUID()
        sentenceGenerationID = generationID
        sentencePractice.start(
            mode: mode,
            requestedCount: count,
            retries: sentenceRetries,
            sourceList: sourceList
        )
        sentenceGenerationTask = Task {
            do {
                let vocabulary = try await store.cards(listID: sourceList.id, limit: 600)
                guard !vocabulary.isEmpty else { throw SentenceFeatureError.emptyWordList }
                var excluded = sentenceRetries.map(\.german)
                var generatedOffset = 0

                for batchSize in SentenceGenerationBatchPlan(requestedCount: count).batches {
                    let drafts: [SentenceDraft]
                    if isUITesting {
                        drafts = uiTestingSentenceDrafts(
                            count: batchSize,
                            offset: generatedOffset,
                            vocabulary: vocabulary
                        )
                    } else {
                        drafts = try await lmStudio.generate(
                            vocabulary: vocabulary,
                            count: batchSize,
                            options: options,
                            settings: lmStudioSettings,
                            excluding: excluded
                        )
                    }
                    try Task.checkCancellation()

                    let analyzedDrafts: [SentenceDraft]
                    if isUITesting {
                        analyzedDrafts = drafts
                    } else {
                        let analyses = try await sentenceAnalyzer.analyze(sentences: drafts.map(\.german))
                        try Task.checkCancellation()
                        guard analyses.count == drafts.count else {
                            throw CoNLLUParsingError.sentenceCount(
                                expected: drafts.count,
                                actual: analyses.count
                            )
                        }
                        analyzedDrafts = zip(drafts, analyses).map { draft, analysis in
                            draft.withAnalysis(analysis)
                        }
                    }

                    guard sentenceGenerationID == generationID else { throw CancellationError() }
                    sentencePractice.appendGenerated(analyzedDrafts)
                    excluded += analyzedDrafts.map(\.german)
                    generatedOffset += analyzedDrafts.count
                    await Task.yield()
                }
            } catch is CancellationError {
                // Closing the app or replacing the task is an expected cancellation.
            } catch {
                guard sentenceGenerationID == generationID else { return }
                show(error)
            }
            guard sentenceGenerationID == generationID else { return }
            sentencePractice.finishGeneration()
            sentenceGenerationTask = nil
        }
    }

    func submitSentenceAnswer(_ answer: String) {
        guard let item = sentencePractice.currentItem,
              let result = sentencePractice.submit(answer: answer) else { return }
        let matchingRetries = sentenceRetries.filter {
            $0.german == item.draft.german && $0.translation == item.draft.translation
        }

        switch result {
        case .incorrect:
            guard matchingRetries.isEmpty, let sourceList = sentencePractice.sourceList else { return }
            sentencePractice.setUpdatingRetry(true)
            Task {
                do {
                    _ = try await store.saveSentences([item.draft], sourceList: sourceList)
                    sentenceRetries = try await store.savedSentences()
                } catch {
                    show(error)
                }
                sentencePractice.setUpdatingRetry(false)
            }
        case .correct:
            guard !matchingRetries.isEmpty else { return }
            sentencePractice.setUpdatingRetry(true)
            Task {
                do {
                    try await store.deleteSentences(ids: matchingRetries.map(\.id))
                    sentenceRetries = try await store.savedSentences()
                } catch {
                    show(error)
                }
                sentencePractice.setUpdatingRetry(false)
            }
        }
    }

    func advanceSentencePractice() {
        sentencePractice.advance()
    }

    func setSentencePracticeMode(_ mode: SentenceTestMode) {
        sentencePractice.setMode(mode)
    }

    func abortSentencePractice() {
        sentenceGenerationID = UUID()
        sentenceGenerationTask?.cancel()
        sentenceGenerationTask = nil
        sentencePractice.abort()
    }

    private func uiTestingSentenceDrafts(
        count: Int,
        offset: Int,
        vocabulary: [PersonalCard]
    ) -> [SentenceDraft] {
        let examples = [
            ("Das Haus hat ein rotes Dach.", "The house has a red roof.", "Haus"),
            ("Wir lernen jeden Morgen Deutsch.", "We learn German every morning.", "lernen"),
            ("Hinter dem Haus wächst ein Baum.", "A tree grows behind the house.", "Haus"),
            ("Die Kinder lernen heute zusammen.", "The children study together today.", "lernen"),
            ("Das Haus steht neben dem Park.", "The house stands next to the park.", "Haus"),
            ("Im Kurs lernen wir neue Wörter.", "We learn new words in class.", "lernen"),
            ("Vor dem Haus wartet ein Taxi.", "A taxi is waiting in front of the house.", "Haus"),
            ("Mit Freunden lernen wir besonders gern.", "We especially enjoy studying with friends.", "lernen"),
            ("Unser Haus hat einen kleinen Garten.", "Our house has a small garden.", "Haus"),
            ("Beim Lesen lernen Kinder sehr schnell.", "Children learn very quickly by reading.", "lernen")
        ]

        return (0..<count).map { index in
            let example = examples[(offset + index) % examples.count]
            let card = vocabulary.first {
                SentenceTokenizer.normalized($0.german) == SentenceTokenizer.normalized(example.2)
            } ?? vocabulary.first
            let target = card.flatMap { selectedCard -> String? in
                let candidate = SentenceTokenizer.tokens(in: example.0).first {
                    SentenceTokenizer.normalized($0.lookupTerm) ==
                        SentenceTokenizer.normalized(selectedCard.german)
                }
                return candidate?.lookupTerm
            }
            let tokens = SentenceTokenizer.tokens(in: example.0).map { token in
                guard let card, let target,
                      SentenceTokenizer.normalized(token.lookupTerm) ==
                        SentenceTokenizer.normalized(target) else { return token }
                return SentenceToken(
                    index: token.index,
                    surface: token.surface,
                    lookupTerm: card.german,
                    cardID: card.id
                )
            }
            return SentenceDraft(german: example.0, translation: example.1, tokens: tokens)
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
        if !isUITesting { settingsStore.save(lmStudioSettings) }
    }

    func shutdown() async {
        sentenceGenerationTask?.cancel()
        await lmStudio.shutdown()
    }

    var configuredLMStudioModel: LMStudioModel? {
        if lmStudioSettings.modelKey.isEmpty { return installedLMStudioModels.first }
        return installedLMStudioModels.first { $0.modelKey == lmStudioSettings.modelKey }
    }

    func translationEntries(
        for selectedToken: SentenceToken,
        sentence: String,
        in sentenceTokens: [SentenceToken],
        analysis: SentenceAnalysis?,
        nounTokenIndices: Set<Int>
    ) async -> [DictionaryEntry] {
        do {
            let relatedToken = SentenceRelations.contextualLookupToken(
                for: selectedToken,
                sentence: sentence,
                tokens: sentenceTokens,
                analysis: analysis,
                nounTokenIndices: nounTokenIndices
            )
            let fallbackToken = SentenceTokenizer.contextualLookupToken(
                for: selectedToken,
                in: sentenceTokens,
                nounTokenIndices: nounTokenIndices
            )
            var lookupTokens = [relatedToken]
            if SentenceTokenizer.normalized(fallbackToken.lookupTerm) !=
                SentenceTokenizer.normalized(relatedToken.lookupTerm) {
                lookupTokens.append(fallbackToken)
            }

            for token in lookupTokens {
                var entries: [DictionaryEntry] = []
                if let cardID = token.cardID, let card = try await store.personalCard(id: cardID) {
                    entries.append(.init(
                        id: card.dictionaryEntryID ?? 0,
                        german: card.german,
                        english: card.english,
                        rawGerman: card.rawGerman,
                        kind: card.kind,
                        gender: card.gender,
                        source: "My words",
                        meanings: card.resolvedMeanings,
                        forms: card.forms
                    ))
                }
                let dictionaryEntries = try await store.searchDictionary(token.lookupTerm, limit: 12)
                for entry in dictionaryEntries where !entries.contains(where: {
                    $0.id == entry.id ||
                    (SentenceTokenizer.normalized($0.german) == SentenceTokenizer.normalized(entry.german) && $0.english == entry.english)
                }) {
                    entries.append(entry)
                }
                if !entries.isEmpty { return entries }
            }
            return []
        } catch {
            show(error)
            return []
        }
    }

    func sentenceGenders(for tokens: [SentenceToken]) async -> [Int: Gender] {
        var result: [Int: Gender] = [:]
        var resolved: [String: Gender] = [:]
        for token in tokens where token.lookupTerm.first?.isUppercase == true
            && !GermanMorphology.isDeterminer(token.lookupTerm) {
            let key = SentenceTokenizer.normalized(token.lookupTerm)
            if let gender = resolved[key] {
                if gender != .unknown { result[token.index] = gender }
                continue
            }

            do {
                let gender: Gender
                if let cardID = token.cardID,
                   let card = try await store.personalCard(id: cardID),
                   card.kind == .noun {
                    gender = card.gender
                } else {
                    let entries = try await store.searchDictionary(token.lookupTerm, limit: 8)
                    gender = entries.first(where: {
                        $0.kind == .noun && $0.gender != .unknown
                    })?.gender ?? .unknown
                }
                resolved[key] = gender
                if gender != .unknown { result[token.index] = gender }
            } catch {
                resolved[key] = .unknown
            }
        }
        return result
    }

    func undo() {
        guard undoHistory.canUndo else { return }
        Task {
            do {
                if let name = try await undoHistory.undo() {
                    showBanner("Undo: \(name)")
                }
            } catch {
                show(error)
            }
        }
    }

    func redo() {
        guard undoHistory.canRedo else { return }
        Task {
            do {
                if let name = try await undoHistory.redo() {
                    showBanner("Redo: \(name)")
                }
            } catch {
                show(error)
            }
        }
    }

    private func removeCardOperation(
        cardID: PersonalCard.ID,
        listID: WordList.ID,
        actionName: String,
        dictionaryEntryID: DictionaryEntry.ID?
    ) -> AppUndoOperation {
        AppUndoOperation(name: actionName) { [weak self] in
            guard let self else { throw CancellationError() }
            guard let mutation = try await self.store.removeCardRecordingChange(
                cardID,
                fromList: listID
            ) else {
                throw AppUndoError.mutationNoLongerAvailable
            }
            if let dictionaryEntryID,
               self.addedDictionaryEntryPlacements[dictionaryEntryID]?.cardID == cardID,
               self.addedDictionaryEntryPlacements[dictionaryEntryID]?.listID == listID {
                self.addedDictionaryEntryPlacements[dictionaryEntryID] = nil
            }
            await self.refreshStudyData()
            return self.restoreCardOperation(
                mutation,
                actionName: actionName,
                dictionaryEntryID: dictionaryEntryID
            )
        }
    }

    private func restoreCardOperation(
        _ mutation: RemovedCardMutation,
        actionName: String,
        dictionaryEntryID: DictionaryEntry.ID?
    ) -> AppUndoOperation {
        AppUndoOperation(name: actionName) { [weak self] in
            guard let self else { throw CancellationError() }
            try await self.store.restoreRemovedCard(mutation)
            if let dictionaryEntryID {
                self.addedDictionaryEntryPlacements[dictionaryEntryID] = .init(
                    cardID: mutation.card.id,
                    listID: mutation.listID
                )
            }
            await self.refreshStudyData()
            return self.removeCardOperation(
                cardID: mutation.card.id,
                listID: mutation.listID,
                actionName: actionName,
                dictionaryEntryID: dictionaryEntryID
            )
        }
    }

    private func moveCardOperation(
        cardID: PersonalCard.ID,
        fromListID: WordList.ID,
        toListID: WordList.ID,
        actionName: String,
        dictionaryEntryID: DictionaryEntry.ID
    ) -> AppUndoOperation {
        AppUndoOperation(name: actionName) { [weak self] in
            guard let self else { throw CancellationError() }
            try await self.store.moveCard(
                cardID,
                fromList: fromListID,
                toList: toListID
            )
            self.addedDictionaryEntryPlacements[dictionaryEntryID] = .init(
                cardID: cardID,
                listID: toListID
            )
            await self.activateWordList(toListID)
            return self.moveCardOperation(
                cardID: cardID,
                fromListID: toListID,
                toListID: fromListID,
                actionName: actionName,
                dictionaryEntryID: dictionaryEntryID
            )
        }
    }

    private func deleteWordListOperation(
        listID: WordList.ID,
        actionName: String
    ) -> AppUndoOperation {
        AppUndoOperation(name: actionName) { [weak self] in
            guard let self else { throw CancellationError() }
            let mutation = try await self.store.deleteWordListRecordingChange(id: listID)
            self.wordLists = try await self.store.wordLists()
            self.sentenceRetries = try await self.store.savedSentences()
            if self.selectedListID == listID {
                await self.activateWordList(WordList.defaultID)
            } else {
                await self.refreshStudyData()
            }
            return self.restoreWordListOperation(mutation, actionName: actionName)
        }
    }

    private func restoreWordListOperation(
        _ mutation: DeletedWordListMutation,
        actionName: String
    ) -> AppUndoOperation {
        AppUndoOperation(name: actionName) { [weak self] in
            guard let self else { throw CancellationError() }
            try await self.store.restoreDeletedWordList(mutation)
            self.wordLists = try await self.store.wordLists()
            self.sentenceRetries = try await self.store.savedSentences()
            await self.activateWordList(mutation.list.id)
            return self.deleteWordListOperation(
                listID: mutation.list.id,
                actionName: actionName
            )
        }
    }

    private func activateWordList(_ listID: WordList.ID) async {
        selectedListID = listID
        isReviewingAll = false
        libraryQuery = ""
        cards = []
        dueCards = []
        reviewCards = []
        stats = StudyStats()
        libraryTask?.cancel()
        await refreshStudyData()
    }

    func refreshStudyData() async {
        let listID = selectedListID
        do {
            let currentDate = now()
            async let loadedCards = store.cards(search: libraryQuery, listID: listID)
            async let loadedDue = store.dueCards(listID: listID, limit: 100, now: currentDate)
            async let loadedStats = store.stats(listID: listID, now: currentDate, calendar: calendar)
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
