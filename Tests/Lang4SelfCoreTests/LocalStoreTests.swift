import Foundation
import SQLite3
import XCTest
@testable import Lang4SelfCore

final class LocalStoreTests: XCTestCase {
    func testAdoptsLegacyDatabaseAndRecordsSchemaVersion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("legacy.sqlite3")
        try executeSQLite(at: databaseURL, sql: """
            CREATE TABLE dictionary_entries (
              id INTEGER PRIMARY KEY,
              german TEXT NOT NULL,
              english TEXT NOT NULL,
              normalized_german TEXT NOT NULL,
              normalized_english TEXT NOT NULL,
              raw_german TEXT NOT NULL,
              raw_english TEXT NOT NULL,
              kind TEXT NOT NULL,
              gender TEXT NOT NULL,
              usage TEXT,
              source TEXT NOT NULL,
              UNIQUE(raw_german, raw_english)
            );
            INSERT INTO dictionary_entries (
              german, english, normalized_german, normalized_english,
              raw_german, raw_english, kind, gender, source
            ) VALUES ('Haus', 'house', 'haus', 'house', 'Haus {n}', 'house', 'noun', 'neuter', 'starter');
            """)

        let store = try LocalStore(url: databaseURL)
        let count = try await store.dictionaryCount()

        XCTAssertEqual(count, 1)
        XCTAssertEqual(try readSchemaVersion(at: databaseURL), LocalStore.latestSchemaVersion)
    }

    func testRejectsDatabaseFromNewerAppVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("future.sqlite3")
        try executeSQLite(at: databaseURL, sql: "PRAGMA user_version = 999")

        XCTAssertThrowsError(try LocalStore(url: databaseURL)) { error in
            guard case LocalStoreError.unsupportedSchema(let found, let latest) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(found, 999)
            XCTAssertEqual(latest, LocalStore.latestSchemaVersion)
        }
    }

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

    func testRussianImportIsAdditiveAndSearchable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let english = directory.appendingPathComponent("english.txt")
        let russian = directory.appendingPathComponent("russian.txt")
        try "# DE-EN vocabulary database\nHaus {n}\thouse\tnoun\t\nlernen\tto learn\tverb\t\n"
            .write(to: english, atomically: true, encoding: .utf8)
        try "# DE-RU vocabulary database\nHaus {n}\tдом {м}\tnoun\t\nlernen\tучиться [несов.]\tverb\t\n"
            .write(to: russian, atomically: true, encoding: .utf8)

        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        _ = try await store.importDictionary(from: english)
        _ = try await store.importDictionary(from: russian)

        let installedLanguages = try await store.installedTranslationLanguages()
        XCTAssertEqual(installedLanguages, [.english, .russian])
        let results = try await store.searchDictionary("дом")
        let house = try XCTUnwrap(results.first { $0.german == "Haus" })
        XCTAssertEqual(house.meanings.map(\.language), [.english, .russian])
        XCTAssertEqual(house.meanings.map(\.translation), ["house", "дом"])
        XCTAssertEqual(house.kind, .noun)
    }

    func testImportsLectorExplanationsAndHidesTranslationDuplicates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let dictionary = directory.appendingPathComponent("dict.txt")
        let explanations = directory.appendingPathComponent("dictionary-de.db")
        try "Bank {f} [Finanzen]\tbank\nBank {f} [Sitzmöbel]\tbench\n"
            .write(to: dictionary, atomically: true, encoding: .utf8)
        try createLectorFixture(at: explanations)

        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        _ = try await store.importDictionary(from: dictionary)
        let imported = try await store.importExplanations(from: explanations)

        XCTAssertEqual(imported, 3)
        let explanationCount = try await store.explanationCount()
        let results = try await store.searchDictionary("Bank")
        XCTAssertEqual(explanationCount, 3)
        let bank = try XCTUnwrap(results.first)
        XCTAssertEqual(
            bank.distinctExplanations.map(\.text),
            ["bank (financial institution)", "bench (which people sit on)"]
        )
        XCTAssertTrue(bank.source.contains("Wiktionary via Lector"))
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

    func testSentencesPersistMappedWordsAndIgnoreDuplicates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("test.sqlite3")

        let store = try LocalStore(url: databaseURL)
        try await store.seedStarterDictionaryIfNeeded()
        let houseResults = try await store.searchDictionary("Haus")
        let house = try XCTUnwrap(houseResults.first)
        let travel = try await store.createWordList(name: "Travel")
        let card = try await store.addCard(from: house, listID: travel.id)
        let draft = SentenceDraft(
            german: "Das Haus ist groß.",
            translation: "The house is big.",
            tokens: [
                .init(index: 0, surface: "Das", lookupTerm: "Das"),
                .init(index: 1, surface: "Haus", lookupTerm: "Haus", cardID: card.id),
                .init(index: 2, surface: "ist", lookupTerm: "sein"),
                .init(index: 3, surface: "groß.", lookupTerm: "groß")
            ]
        )

        let inserted = try await store.saveSentences([draft], sourceList: travel)
        XCTAssertEqual(inserted.count, 1)
        let duplicateInsert = try await store.saveSentences([draft], sourceList: travel)
        XCTAssertTrue(duplicateInsert.isEmpty)

        let reopened = try LocalStore(url: databaseURL)
        let reopenedSentences = try await reopened.savedSentences()
        let saved = try XCTUnwrap(reopenedSentences.first)
        XCTAssertEqual(saved.german, draft.german)
        XCTAssertEqual(saved.tokens[1].cardID, card.id)
        XCTAssertEqual(saved.sourceListID, travel.id)

        try await reopened.deleteWordList(id: travel.id)
        let afterListDeletion = try await reopened.savedSentences()
        XCTAssertNil(afterListDeletion.first?.sourceListID)
        try await reopened.deleteSentence(id: saved.id)
        let afterSentenceDeletion = try await reopened.savedSentences()
        XCTAssertTrue(afterSentenceDeletion.isEmpty)
    }

    func testSentenceTokenizerKeepsDisplayPunctuationOutOfLookupTerm() {
        let tokens = SentenceTokenizer.tokens(in: "„Das Haus“, sagte Anna.")

        XCTAssertEqual(tokens.map(\.surface), ["„Das", "Haus“,", "sagte", "Anna."])
        XCTAssertEqual(tokens.map(\.lookupTerm), ["Das", "Haus", "sagte", "Anna"])
    }
}

private func createLectorFixture(at url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
        sqlite3_close(database)
        throw NSError(domain: "LocalStoreTests", code: 1)
    }
    defer { sqlite3_close(database) }
    let sql = """
        CREATE TABLE entries (word TEXT PRIMARY KEY, rank INTEGER, ipa TEXT, etymology TEXT);
        CREATE TABLE senses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          word TEXT NOT NULL,
          pos TEXT,
          gloss TEXT NOT NULL,
          sort_order INTEGER DEFAULT 0
        );
        INSERT INTO entries (word) VALUES ('bank');
        INSERT INTO senses (word, pos, gloss, sort_order) VALUES
          ('bank', 'noun', 'bank', 0),
          ('bank', 'noun', 'bank (financial institution)', 1),
          ('bank', 'noun', 'bench (which people sit on)', 2);
        """
    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
        let message = error.map { String(cString: $0) } ?? "unknown SQLite error"
        sqlite3_free(error)
        throw NSError(domain: "LocalStoreTests", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private func executeSQLite(at url: URL, sql: String) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
        sqlite3_close(database)
        throw NSError(domain: "LocalStoreTests", code: 3)
    }
    defer { sqlite3_close(database) }
    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
        let message = error.map { String(cString: $0) } ?? "unknown SQLite error"
        sqlite3_free(error)
        throw NSError(domain: "LocalStoreTests", code: 4, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private func readSchemaVersion(at url: URL) throws -> Int {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        sqlite3_close(database)
        throw NSError(domain: "LocalStoreTests", code: 5)
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else {
        throw NSError(domain: "LocalStoreTests", code: 6)
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
        throw NSError(domain: "LocalStoreTests", code: 7)
    }
    return Int(sqlite3_column_int(statement, 0))
}
