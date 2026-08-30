import Foundation

public protocol DictionaryStoring: Sendable {
    var databaseURL: URL { get }

    func dictionaryCount() async throws -> Int
    func hasCompleteDictionary() async throws -> Bool
    func installedTranslationLanguages() async throws -> Set<TranslationLanguage>
    func explanationCount() async throws -> Int
    func seedStarterDictionaryIfNeeded() async throws
    func searchDictionary(_ query: String, limit: Int) async throws -> [DictionaryEntry]
    func importDictionary(
        from url: URL,
        progress: @escaping @Sendable (ImportProgress) -> Void
    ) async throws -> Int
    func importExplanations(
        from url: URL,
        progress: @escaping @Sendable (ExplanationImportProgress) -> Void
    ) async throws -> Int
}

public protocol WordLibraryStoring: Sendable {
    func addCard(from entry: DictionaryEntry, listID: Int64) async throws -> PersonalCard
    func cards(search: String, listID: Int64, limit: Int) async throws -> [PersonalCard]
    func wordLists() async throws -> [WordList]
    func createWordList(name: String) async throws -> WordList
    func renameWordList(id: Int64, name: String) async throws
    func deleteWordList(id: Int64) async throws
    func addCard(_ cardID: Int64, toList listID: Int64) async throws
    func removeCard(_ cardID: Int64, fromList listID: Int64) async throws
    func moveCard(_ cardID: Int64, fromList sourceListID: Int64, toList destinationListID: Int64) async throws
    func updateCard(_ card: PersonalCard) async throws
    func personalCard(id: PersonalCard.ID) async throws -> PersonalCard?
}

public protocol SentenceStoring: Sendable {
    func savedSentences(limit: Int) async throws -> [SavedSentence]
    func saveSentences(_ drafts: [SentenceDraft], sourceList: WordList) async throws -> [SavedSentence]
    func deleteSentence(id: SavedSentence.ID) async throws
}

public protocol StudyStoring: Sendable {
    func dueCards(listID: Int64, limit: Int, now: Date) async throws -> [PersonalCard]
    func reviewCards(listID: Int64) async throws -> [PersonalCard]
    func review(card: PersonalCard, rating: ReviewRating, now: Date, calendar: Calendar) async throws -> PersonalCard
    func stats(listID: Int64, now: Date, calendar: Calendar) async throws -> StudyStats
}

/// Persistence operations that return enough data to reverse user-facing
/// additions and removals without losing IDs, timestamps, or study history.
public protocol ReversibleMutationStoring: Sendable {
    func addCardRecordingChange(
        from entry: DictionaryEntry,
        listID: WordList.ID
    ) async throws -> AddedCardMutation
    func addCardRecordingChange(
        _ cardID: PersonalCard.ID,
        toList listID: WordList.ID
    ) async throws -> Bool
    func removeCardRecordingChange(
        _ cardID: PersonalCard.ID,
        fromList listID: WordList.ID
    ) async throws -> RemovedCardMutation?
    func restoreRemovedCard(_ mutation: RemovedCardMutation) async throws
    func deleteWordListRecordingChange(id: WordList.ID) async throws -> DeletedWordListMutation
    func restoreDeletedWordList(_ mutation: DeletedWordListMutation) async throws
    func deleteSentences(ids: [SavedSentence.ID]) async throws
    func restoreSentences(_ sentences: [SavedSentence]) async throws
}

/// The composed boundary needed by the top-level app coordinator. Feature services should
/// depend on one of the narrower capability protocols above whenever possible.
public protocol AppDataStore:
    DictionaryStoring,
    WordLibraryStoring,
    SentenceStoring,
    StudyStoring,
    ReversibleMutationStoring
{}

public extension DictionaryStoring {
    func searchDictionary(_ query: String) async throws -> [DictionaryEntry] {
        try await searchDictionary(query, limit: 80)
    }

    func importDictionary(from url: URL) async throws -> Int {
        try await importDictionary(from: url, progress: { _ in })
    }

    func importExplanations(from url: URL) async throws -> Int {
        try await importExplanations(from: url, progress: { _ in })
    }
}

public extension WordLibraryStoring {
    func addCard(from entry: DictionaryEntry) async throws -> PersonalCard {
        try await addCard(from: entry, listID: WordList.defaultID)
    }

    func cards() async throws -> [PersonalCard] {
        try await cards(search: "", listID: WordList.defaultID, limit: 500)
    }

    func cards(listID: Int64) async throws -> [PersonalCard] {
        try await cards(search: "", listID: listID, limit: 500)
    }

    func cards(listID: Int64, limit: Int) async throws -> [PersonalCard] {
        try await cards(search: "", listID: listID, limit: limit)
    }

    func cards(search: String, listID: Int64) async throws -> [PersonalCard] {
        try await cards(search: search, listID: listID, limit: 500)
    }
}

public extension SentenceStoring {
    func savedSentences() async throws -> [SavedSentence] {
        try await savedSentences(limit: 500)
    }
}

public extension StudyStoring {
    func dueCards(listID: Int64) async throws -> [PersonalCard] {
        try await dueCards(listID: listID, limit: 100, now: .now)
    }

    func review(card: PersonalCard, rating: ReviewRating) async throws -> PersonalCard {
        try await review(card: card, rating: rating, now: .now, calendar: .current)
    }

    func stats(listID: Int64) async throws -> StudyStats {
        try await stats(listID: listID, now: .now, calendar: .current)
    }
}

extension LocalStore: AppDataStore {}
