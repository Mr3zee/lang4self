import Foundation
import SwiftUI
import Lang4SelfCore

enum AppRoute: String, CaseIterable, Identifiable {
    case dictionary
    case speak
    case review
    case library
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictionary: "Dictionary"
        case .speak: "Speak"
        case .review: "Review"
        case .library: "My words"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .dictionary: "character.book.closed"
        case .speak: "waveform"
        case .review: "rectangle.on.rectangle.angled"
        case .library: "books.vertical"
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
    @Published private(set) var importProgress: ImportProgress?
    @Published private(set) var isImporting = false
    @Published private(set) var banner: String?
    @Published var libraryQuery = ""

    let store: LocalStore
    private var searchTask: Task<Void, Never>?
    private var libraryTask: Task<Void, Never>?
    private var bannerDismissTask: Task<Void, Never>?

    var selectedWordList: WordList? { wordLists.first { $0.id == selectedListID } }

    init(store: LocalStore? = nil) throws {
        self.store = try store ?? LocalStore()
        Task { await bootstrap() }
    }

    func bootstrap() async {
        do {
            try await store.seedStarterDictionaryIfNeeded()
            async let count = store.dictionaryCount()
            async let complete = store.hasCompleteDictionary()
            async let loadedLists = store.wordLists()
            async let loadedCards = store.cards(listID: selectedListID)
            async let loadedDue = store.dueCards(listID: selectedListID)
            async let loadedStats = store.stats(listID: selectedListID)
            dictionaryCount = try await count
            hasCompleteDictionary = try await complete
            wordLists = try await loadedLists
            cards = try await loadedCards
            dueCards = try await loadedDue
            reviewCards = dueCards
            stats = try await loadedStats
        } catch {
            show(error)
        }
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
