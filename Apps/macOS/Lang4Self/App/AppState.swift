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
    @Published private(set) var cards: [PersonalCard] = []
    @Published private(set) var dueCards: [PersonalCard] = []
    @Published private(set) var stats = StudyStats()
    @Published private(set) var dictionaryCount = 0
    @Published private(set) var hasCompleteDictionary = false
    @Published private(set) var importProgress: ImportProgress?
    @Published private(set) var isImporting = false
    @Published var banner: String?
    @Published var libraryQuery = ""

    let store: LocalStore
    private var searchTask: Task<Void, Never>?
    private var libraryTask: Task<Void, Never>?

    init(store: LocalStore? = nil) throws {
        self.store = try store ?? LocalStore()
        Task { await bootstrap() }
    }

    func bootstrap() async {
        do {
            try await store.seedStarterDictionaryIfNeeded()
            async let count = store.dictionaryCount()
            async let complete = store.hasCompleteDictionary()
            async let loadedCards = store.cards()
            async let loadedDue = store.dueCards()
            async let loadedStats = store.stats()
            dictionaryCount = try await count
            hasCompleteDictionary = try await complete
            cards = try await loadedCards
            dueCards = try await loadedDue
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
        Task {
            do {
                let card = try await store.addCard(from: entry)
                if !cards.contains(where: { $0.id == card.id }) { cards.insert(card, at: 0) }
                await refreshStudyData()
                if announce { banner = "Added “\(entry.german)” to My words" }
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
        libraryTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            do { cards = try await store.cards(search: query) }
            catch { show(error) }
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

    func deleteCard(_ card: PersonalCard) {
        Task {
            do {
                try await store.deleteCard(id: card.id)
                cards.removeAll { $0.id == card.id }
                await refreshStudyData()
                banner = "Removed “\(card.german)”"
            } catch { show(error) }
        }
    }

    func rate(_ card: PersonalCard, _ rating: ReviewRating) {
        Task {
            do {
                _ = try await store.review(card: card, rating: rating)
                dueCards.removeAll { $0.id == card.id }
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
                banner = "Imported \(imported.formatted()) dictionary entries"
            } catch {
                isImporting = false
                importProgress = nil
                show(error)
            }
        }
    }

    func refreshStudyData() async {
        do {
            async let loadedCards = store.cards(search: libraryQuery)
            async let loadedDue = store.dueCards()
            async let loadedStats = store.stats()
            cards = try await loadedCards
            dueCards = try await loadedDue
            stats = try await loadedStats
        } catch { show(error) }
    }

    func dismissBanner() { banner = nil }

    private func show(_ error: Error) {
        banner = error.localizedDescription
    }
}
