import Foundation
import XCTest
@testable import Lang4SelfCore

final class LocalStoreTests: XCTestCase {
    func testSearchCardsAndReviewPersistLocally() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        try await store.seedStarterDictionaryIfNeeded()
        let count = try await store.dictionaryCount()
        XCTAssertGreaterThan(count, 20)

        let results = try await store.searchDictionary("hau")
        let house = try XCTUnwrap(results.first { $0.german == "Haus" })
        let card = try await store.addCard(from: house)
        let initiallyDue = try await store.dueCards()
        XCTAssertEqual(initiallyDue.map(\.id), [card.id])

        let reviewed = try await store.review(card: card, rating: .good)
        XCTAssertEqual(reviewed.repetitions, 1)
        let dueAfterReview = try await store.dueCards()
        let stats = try await store.stats()
        XCTAssertTrue(dueAfterReview.isEmpty)
        XCTAssertEqual(stats.totalCards, 1)
    }

    func testImportsTabDelimitedFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = directory.appendingPathComponent("dict.txt")
        try "Katze {f}\tcat\nrennen {vi}\tto run\n".write(to: fixture, atomically: true, encoding: .utf8)

        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        let imported = try await store.importDictionary(from: fixture)
        XCTAssertEqual(imported, 2)
        let results = try await store.searchDictionary("cat")
        XCTAssertEqual(results.first?.german, "Katze")
        XCTAssertEqual(results.first?.gender, .feminine)
    }

    func testAutoDetectsEnglishFirstFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = directory.appendingPathComponent("dict.txt")
        try "cat\tKatze {f}\nto run\trennen {vi}\n".write(to: fixture, atomically: true, encoding: .utf8)

        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        _ = try await store.importDictionary(from: fixture)
        let results = try await store.searchDictionary("Katze")
        XCTAssertEqual(results.first?.german, "Katze")
        XCTAssertEqual(results.first?.english, "cat")
    }

    func testGroupsMeaningsForTheSameWordAndKind() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = directory.appendingPathComponent("dict.txt")
        try """
        Bank {f} [Finanzen]\tbank
        Bank {f} [Sitzmöbel]\tbench
        Bank {vi}\tto bank
        """.write(to: fixture, atomically: true, encoding: .utf8)

        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        _ = try await store.importDictionary(from: fixture)
        let results = try await store.searchDictionary("Bank")
        let bankEntries = results.filter { $0.german == "Bank" }
        XCTAssertEqual(bankEntries.count, 2)

        let noun = try XCTUnwrap(bankEntries.first { $0.kind == .noun })
        XCTAssertEqual(noun.meanings.map(\.english), ["bank", "bench"])
        XCTAssertEqual(noun.english, "bank; bench")

        let verb = try XCTUnwrap(bankEntries.first { $0.kind == .verb })
        XCTAssertEqual(verb.meanings.map(\.english), ["to bank"])

        let englishResults = try await store.searchDictionary("bench")
        let nounFromEnglishSearch = try XCTUnwrap(englishResults.first { $0.kind == .noun })
        XCTAssertEqual(nounFromEnglishSearch.id, noun.id)
        XCTAssertEqual(nounFromEnglishSearch.meanings.map(\.english), ["bank", "bench"])
    }

    func testDoesNotGroupWordsThatOnlyDifferByDiacritics() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = directory.appendingPathComponent("dict.txt")
        try "schon {adv}\talready\nschön {adv}\tbeautifully\n".write(to: fixture, atomically: true, encoding: .utf8)

        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        _ = try await store.importDictionary(from: fixture)
        let results = try await store.searchDictionary("schon")

        XCTAssertEqual(Set(results.map(\.german)), ["schon", "schön"])
    }

    func testCardCanBelongToMultipleListsAndBeRemovedFromOne() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("test.sqlite3")

        let store = try LocalStore(url: databaseURL)
        try await store.seedStarterDictionaryIfNeeded()
        let results = try await store.searchDictionary("Haus")
        let house = try XCTUnwrap(results.first)
        let travel = try await store.createWordList(name: "Travel")
        let card = try await store.addCard(from: house)
        _ = try await store.addCard(from: house, listID: travel.id)

        let initialDefaultCards = try await store.cards()
        let initialTravelCards = try await store.cards(listID: travel.id)
        XCTAssertEqual(initialDefaultCards.map(\.id), [card.id])
        XCTAssertEqual(initialTravelCards.map(\.id), [card.id])

        try await store.removeCard(card.id, fromList: WordList.defaultID)
        let defaultCards = try await store.cards()
        let travelCards = try await store.cards(listID: travel.id)
        XCTAssertEqual(defaultCards, [])
        XCTAssertEqual(travelCards.map(\.id), [card.id])

        let reopened = try LocalStore(url: databaseURL)
        let reopenedDefaultCards = try await reopened.cards()
        let reopenedTravelCards = try await reopened.cards(listID: travel.id)
        XCTAssertEqual(reopenedDefaultCards, [])
        XCTAssertEqual(reopenedTravelCards.map(\.id), [card.id])
    }

    func testReviewCardsIncludesCardsThatAreNotDue() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        try await store.seedStarterDictionaryIfNeeded()
        let results = try await store.searchDictionary("Haus")
        let house = try XCTUnwrap(results.first)
        let card = try await store.addCard(from: house)
        _ = try await store.review(card: card, rating: .good)

        let dueCards = try await store.dueCards()
        let reviewCards = try await store.reviewCards()
        XCTAssertTrue(dueCards.isEmpty)
        XCTAssertEqual(reviewCards.map(\.id), [card.id])
    }
}
