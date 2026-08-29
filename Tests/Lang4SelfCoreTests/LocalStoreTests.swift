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
}
