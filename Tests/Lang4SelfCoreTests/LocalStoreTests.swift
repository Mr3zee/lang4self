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

    func testMigratesAnnotatedDeterminersAndLinkedCards() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("version-one.sqlite3")
        try createVersionOneClassificationFixture(at: databaseURL)

        _ = try LocalStore(url: databaseURL)

        XCTAssertEqual(try readSchemaVersion(at: databaseURL), LocalStore.latestSchemaVersion)
        XCTAssertEqual(
            try readTextValues(at: databaseURL, sql: "SELECT kind FROM dictionary_entries ORDER BY id"),
            ["determiner", "other"]
        )
        XCTAssertEqual(
            try readTextValues(at: databaseURL, sql: "SELECT kind FROM personal_cards ORDER BY id"),
            ["determiner", "other"]
        )
        XCTAssertEqual(
            try readTextValues(at: databaseURL, sql: "SELECT notes FROM personal_cards ORDER BY id"),
            ["keep me", "also keep me"]
        )
    }

    func testClassificationMigrationRollsBackAllWrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("version-one.sqlite3")
        try createVersionOneClassificationFixture(at: databaseURL)
        try executeSQLite(at: databaseURL, sql: """
            CREATE TRIGGER reject_card_kind_migration
            BEFORE UPDATE OF kind ON personal_cards
            BEGIN
              SELECT RAISE(ABORT, 'forced classification migration failure');
            END;
            """)

        XCTAssertThrowsError(try LocalStore(url: databaseURL))

        XCTAssertEqual(try readSchemaVersion(at: databaseURL), 1)
        XCTAssertEqual(
            try readTextValues(at: databaseURL, sql: "SELECT kind FROM dictionary_entries ORDER BY id"),
            ["other", "other"]
        )
        XCTAssertEqual(
            try readTextValues(at: databaseURL, sql: "SELECT kind FROM personal_cards ORDER BY id"),
            ["other", "other"]
        )
    }

    func testMigratesSearchIndexToNormalizedDictionaryText() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("version-two.sqlite3")
        try createVersionTwoSearchFixture(at: databaseURL)

        let store = try LocalStore(url: databaseURL)
        let results = try await store.searchDictionary("Weiß")

        XCTAssertEqual(try readSchemaVersion(at: databaseURL), LocalStore.latestSchemaVersion)
        XCTAssertEqual(results.first?.german, "Weiß")
        XCTAssertEqual(results.first?.meanings.map(\.translation), ["white"])
    }

    func testSearchIndexMigrationRollsBackAllWrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("invalid-version-two.sqlite3")
        try createVersionTwoSearchFixture(at: databaseURL, omitNormalizedEnglish: true)

        XCTAssertThrowsError(try LocalStore(url: databaseURL))

        XCTAssertEqual(try readSchemaVersion(at: databaseURL), 2)
        XCTAssertEqual(
            try readTextValues(
                at: databaseURL,
                sql: """
                    SELECT d.german
                    FROM dictionary_fts
                    JOIN dictionary_entries d ON d.id = dictionary_fts.rowid
                    WHERE dictionary_fts MATCH '\"weiß\"'
                    """
            ),
            ["Weiß"]
        )
    }

    func testMigratesVersionThreeAndPreservesDataWhileAddingInflections() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("version-three.sqlite3")
        try executeSQLite(at: databaseURL, sql: """
            PRAGMA user_version = 3;
            CREATE TABLE preserved_value (value TEXT NOT NULL);
            INSERT INTO preserved_value VALUES ('keep me');
            """)

        _ = try LocalStore(url: databaseURL)

        XCTAssertEqual(try readSchemaVersion(at: databaseURL), LocalStore.latestSchemaVersion)
        XCTAssertEqual(
            try readTextValues(at: databaseURL, sql: "SELECT value FROM preserved_value"),
            ["keep me"]
        )
        XCTAssertEqual(
            try readTextValues(
                at: databaseURL,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'dictionary_inflections'"
            ),
            ["dictionary_inflections"]
        )
    }

    func testMigratesVersionFourAndPreservesInflectionsWhileAddingFormIndex() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("version-four.sqlite3")
        try executeSQLite(at: databaseURL, sql: """
            PRAGMA user_version = 4;
            CREATE TABLE dictionary_inflections (
              id INTEGER PRIMARY KEY,
              lemma_key TEXT NOT NULL,
              form TEXT NOT NULL,
              tags TEXT NOT NULL,
              source TEXT NOT NULL,
              UNIQUE(lemma_key, form, tags, source)
            );
            CREATE INDEX dictionary_inflections_lemma ON dictionary_inflections(lemma_key);
            INSERT INTO dictionary_inflections (lemma_key, form, tags, source)
            VALUES ('haus', 'häuser', 'noun,plural', 'Wiktionary via Lector');
            """)

        _ = try LocalStore(url: databaseURL)

        XCTAssertEqual(try readSchemaVersion(at: databaseURL), LocalStore.latestSchemaVersion)
        XCTAssertEqual(
            try readTextValues(at: databaseURL, sql: "SELECT lemma_key || ':' || form FROM dictionary_inflections"),
            ["haus:häuser"]
        )
        XCTAssertEqual(
            try readTextValues(
                at: databaseURL,
                sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'dictionary_inflections_form'"
            ),
            ["dictionary_inflections_form"]
        )
    }

    func testMigratesVersionFiveAndPreservesSentencesWhileAddingAnalysisCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("version-five.sqlite3")
        try executeSQLite(at: databaseURL, sql: """
            PRAGMA user_version = 5;
            CREATE TABLE saved_sentences (
              id INTEGER PRIMARY KEY,
              german TEXT NOT NULL,
              translation TEXT NOT NULL,
              source_list_id INTEGER,
              source_list_name TEXT NOT NULL,
              tokens_json TEXT NOT NULL,
              created_at REAL NOT NULL,
              UNIQUE(german, translation)
            );
            INSERT INTO saved_sentences (
              german, translation, source_list_name, tokens_json, created_at
            ) VALUES ('Der Hund schläft.', 'The dog sleeps.', 'Travel', '[]', 1234);
            """)

        let store = try LocalStore(url: databaseURL)
        let sentences = try await store.savedSentences()

        XCTAssertEqual(try readSchemaVersion(at: databaseURL), LocalStore.latestSchemaVersion)
        XCTAssertTrue(
            try readTextValues(
                at: databaseURL,
                sql: "SELECT name FROM pragma_table_info('saved_sentences')"
            ).contains("analysis_json")
        )
        XCTAssertEqual(sentences.first?.german, "Der Hund schläft.")
        XCTAssertNil(sentences.first?.analysis)
    }

    func testMigratesVersionSixAndPreservesStoredDataWhileAddingDictionaryDetails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("version-six.sqlite3")
        try executeSQLite(at: databaseURL, sql: """
            PRAGMA user_version = 6;
            CREATE TABLE dictionary_entries (
              id INTEGER PRIMARY KEY, german TEXT NOT NULL, english TEXT NOT NULL,
              normalized_german TEXT NOT NULL, normalized_english TEXT NOT NULL,
              raw_german TEXT NOT NULL, raw_english TEXT NOT NULL, kind TEXT NOT NULL,
              gender TEXT NOT NULL, usage TEXT, source TEXT NOT NULL,
              translation_language TEXT NOT NULL DEFAULT 'en', explanation TEXT
            );
            CREATE TABLE personal_cards (
              id INTEGER PRIMARY KEY, dictionary_entry_id INTEGER, german TEXT NOT NULL,
              english TEXT NOT NULL, raw_german TEXT NOT NULL, kind TEXT NOT NULL,
              gender TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '', tags TEXT NOT NULL DEFAULT '',
              created_at REAL NOT NULL, due_at REAL NOT NULL, last_reviewed_at REAL,
              interval_days REAL NOT NULL DEFAULT 0, ease_factor REAL NOT NULL DEFAULT 2.5,
              repetitions INTEGER NOT NULL DEFAULT 0, lapses INTEGER NOT NULL DEFAULT 0,
              is_starred INTEGER NOT NULL DEFAULT 0, is_suspended INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE dictionary_inflections (
              id INTEGER PRIMARY KEY, lemma_key TEXT NOT NULL, form TEXT NOT NULL,
              tags TEXT NOT NULL, source TEXT NOT NULL,
              UNIQUE(lemma_key, form, tags, source)
            );
            INSERT INTO dictionary_entries VALUES
              (1, 'Haus', 'house', 'haus', 'house', 'Haus {n}', 'house', 'noun', 'neuter', NULL, 'dict.cc', 'en', NULL);
            INSERT INTO personal_cards
              (id, dictionary_entry_id, german, english, raw_german, kind, gender, notes,
               created_at, due_at)
            VALUES (1, 1, 'Haus', 'house', 'Haus {n}', 'noun', 'neuter', 'keep me', 1, 1);
            INSERT INTO dictionary_inflections (lemma_key, form, tags, source)
            VALUES ('haus', 'häuser', 'noun,plural', 'Wiktionary via Lector');
            """)

        _ = try LocalStore(url: databaseURL)

        XCTAssertEqual(try readSchemaVersion(at: databaseURL), LocalStore.latestSchemaVersion)
        XCTAssertEqual(
            try readTextValues(at: databaseURL, sql: "SELECT notes FROM personal_cards"),
            ["keep me"]
        )
        XCTAssertEqual(
            try readTextValues(at: databaseURL, sql: "SELECT kind FROM dictionary_inflections"),
            ["noun"]
        )
        for column in ["grammar", "subject"] {
            XCTAssertTrue(try readTextValues(
                at: databaseURL,
                sql: "SELECT name FROM pragma_table_info('dictionary_entries')"
            ).contains(column))
        }
        XCTAssertTrue(try readTextValues(
            at: databaseURL,
            sql: "SELECT name FROM pragma_table_info('personal_cards')"
        ).contains("meanings_json"))
        XCTAssertEqual(
            try readTextValues(
                at: databaseURL,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'dictionary_%forms' ORDER BY name"
            ),
            ["dictionary_related_forms"]
        )
    }

    func testVersionSevenMigrationRollsBackAllSchemaAndDataChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("version-six.sqlite3")
        try executeSQLite(at: databaseURL, sql: """
            PRAGMA user_version = 6;
            CREATE TABLE dictionary_entries (id INTEGER PRIMARY KEY);
            CREATE TABLE personal_cards (id INTEGER PRIMARY KEY);
            CREATE TABLE dictionary_inflections (
              id INTEGER PRIMARY KEY, lemma_key TEXT NOT NULL, form TEXT NOT NULL,
              tags TEXT NOT NULL, source TEXT NOT NULL
            );
            INSERT INTO dictionary_inflections (lemma_key, form, tags, source)
            VALUES ('haus', 'häuser', 'noun,plural', 'Wiktionary via Lector');
            CREATE TRIGGER reject_inflection_kind_migration
            BEFORE UPDATE ON dictionary_inflections
            BEGIN
              SELECT RAISE(ABORT, 'forced version seven migration failure');
            END;
            """)

        XCTAssertThrowsError(try LocalStore(url: databaseURL))

        XCTAssertEqual(try readSchemaVersion(at: databaseURL), 6)
        XCTAssertFalse(try readTextValues(
            at: databaseURL,
            sql: "SELECT name FROM pragma_table_info('dictionary_entries')"
        ).contains("grammar"))
        XCTAssertFalse(try readTextValues(
            at: databaseURL,
            sql: "SELECT name FROM pragma_table_info('personal_cards')"
        ).contains("meanings_json"))
        XCTAssertFalse(try readTextValues(
            at: databaseURL,
            sql: "SELECT name FROM pragma_table_info('dictionary_inflections')"
        ).contains("kind"))
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

    func testFailedReviewRollsBackCardUpdate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("test.sqlite3")

        let store = try LocalStore(url: databaseURL)
        try await store.seedStarterDictionaryIfNeeded()
        let houseResults = try await store.searchDictionary("Haus")
        let house = try XCTUnwrap(houseResults.first)
        let card = try await store.addCard(from: house)
        try executeSQLite(at: databaseURL, sql: """
            CREATE TRIGGER reject_review
            BEFORE INSERT ON review_log
            BEGIN
              SELECT RAISE(ABORT, 'forced review-log failure');
            END;
            """)

        do {
            _ = try await store.review(card: card, rating: .good)
            XCTFail("Expected the review-log insert to fail")
        } catch {}

        let persistedCard = try await store.personalCard(id: card.id)
        let persisted = try XCTUnwrap(persistedCard)
        XCTAssertNil(persisted.lastReviewedAt)
        XCTAssertEqual(persisted.repetitions, 0)
        XCTAssertEqual(persisted.intervalDays, 0)
    }

    func testStatsUseTheSuppliedCalendarForStreakDays() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        try await store.seedStarterDictionaryIfNeeded()
        let houseResults = try await store.searchDictionary("Haus")
        let house = try XCTUnwrap(houseResults.first)
        let card = try await store.addCard(from: house)
        let reviewedAt = Date(timeIntervalSince1970: 1_704_151_800) // 2024-01-01 23:30 UTC
        let now = Date(timeIntervalSince1970: 1_704_155_400) // 2024-01-02 00:30 UTC
        _ = try await store.review(card: card, rating: .good, now: reviewedAt)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 2 * 60 * 60))

        let stats = try await store.stats(now: now, calendar: calendar)

        XCTAssertEqual(stats.reviewsToday, 1)
        XCTAssertEqual(stats.streakDays, 1)
    }

    func testStatsExcludeReviewsOutsideTheSuppliedDay() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        try await store.seedStarterDictionaryIfNeeded()
        let houseResults = try await store.searchDictionary("Haus")
        let house = try XCTUnwrap(houseResults.first)
        let card = try await store.addCard(from: house)
        let tomorrow = Date(timeIntervalSince1970: 1_704_240_000)
        _ = try await store.review(card: card, rating: .good, now: tomorrow)
        let today = Date(timeIntervalSince1970: 1_704_153_600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let stats = try await store.stats(now: today, calendar: calendar)

        XCTAssertEqual(stats.reviewsToday, 0)
        XCTAssertEqual(stats.streakDays, 0)
    }

    func testInjectedClockControlsStoredCreationDates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let store = try LocalStore(
            url: directory.appendingPathComponent("test.sqlite3"),
            now: { fixedDate }
        )
        try await store.seedStarterDictionaryIfNeeded()
        let list = try await store.createWordList(name: "Fixed time")
        let houseResults = try await store.searchDictionary("Haus")
        let house = try XCTUnwrap(houseResults.first)
        let card = try await store.addCard(from: house, listID: list.id)

        XCTAssertEqual(list.createdAt, fixedDate)
        XCTAssertEqual(card.createdAt, fixedDate)
        XCTAssertEqual(card.dueAt, fixedDate)
        let noCards = try await store.cards(listID: list.id, limit: 0)
        let noDueCards = try await store.dueCards(listID: list.id, limit: -1, now: fixedDate)
        XCTAssertTrue(noCards.isEmpty)
        XCTAssertTrue(noDueCards.isEmpty)
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

    func testImportCombinesMetadataFromDuplicateDictCCRows() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = directory.appendingPathComponent("dict.txt")
        try """
        Bank {f}\tbank\tnoun common\tfinance
        Bank {f}\tbank\tnoun archaic\thistory
        """.write(to: fixture, atomically: true, encoding: .utf8)

        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        let imported = try await store.importDictionary(from: fixture)
        XCTAssertEqual(imported, 2)

        let results = try await store.searchDictionary("Bank")
        let bank = try XCTUnwrap(results.first)
        let meaning = try XCTUnwrap(bank.meanings.first)
        XCTAssertEqual(meaning.grammar, "noun common · noun archaic")
        XCTAssertEqual(meaning.subject, "finance · history")
    }

    func testBulkImportSearchesEszettUsingNormalizedSpelling() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = directory.appendingPathComponent("dict.txt")
        try "Weiß {n}\twhite\nwissen {vi}\tto know\n"
            .write(to: fixture, atomically: true, encoding: .utf8)

        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        _ = try await store.importDictionary(from: fixture)
        let results = try await store.searchDictionary("Weiß")

        XCTAssertEqual(results.first?.german, "Weiß")
        XCTAssertEqual(results.first?.meanings.map(\.translation), ["white"])
    }

    func testSmartGermanSearchPrefersBaseWordsForSpeechForms() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = directory.appendingPathComponent("dict.txt")
        try """
        Hund {m}\tdog
        Hunde {pl}\tdogs
        Hundedermatologie {f}\tcanine dermatology
        Familie der Hunde {f}\tcanidae
        lernen {vt}\tto learn
        fallen {vi}\tto fall
        ab|fallen {vi}\tto drop off
        """.write(to: fixture, atomically: true, encoding: .utf8)
        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        _ = try await store.importDictionary(from: fixture)

        let withArticle = try await store.searchDictionary("Der Hund")
        let plural = try await store.searchDictionary("Hunde")
        let conjugated = try await store.searchDictionary("lernt")
        let irregular = try await store.searchDictionary("fällt")
        let separated = try await store.searchDictionary("fällt ab")
        let participle = try await store.searchDictionary("abgefallen")
        XCTAssertEqual(withArticle.first?.german, "Hund")
        XCTAssertEqual(withArticle.first.map(GermanMorphology.pluralForms), [])
        XCTAssertEqual(plural.first?.german, "Hund")
        XCTAssertEqual(conjugated.first?.german, "lernen")
        XCTAssertEqual(irregular.first?.german, "fallen")
        XCTAssertEqual(separated.first?.german, "abfallen")
        XCTAssertEqual(participle.first?.german, "abfallen")
    }

    func testSearchMergesOnlyDatasetLinkedNounPluralsAcrossPluralPatterns() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = directory.appendingPathComponent("dict-en.txt")
        let russianFixture = directory.appendingPathComponent("dict-ru.txt")
        let lectorFixture = directory.appendingPathComponent("dictionary-de.db")
        try """
        # DE-EN vocabulary database
        Hund {m}\tdog
        Hund {m}\thound
        Hunde {pl}\tdogs
        Hunde {pl}\thounds
        Buch {n}\tbook
        Bücher {pl}\tbooks
        Mutter {f}\tmother
        Mütter {pl}\tmothers
        Museum {n}\tmuseum
        Museen {pl}\tmuseums
        Datum {n}\tdate
        Daten {pl}\tdata
        Kaktus {m}\tcactus
        Kakteen {pl}\tcacti
        Thema {n}\ttopic
        Themen {pl}\ttopics
        Themata {pl}\ttopics [formal]
        Lehrer {m}\tteacher
        Lehrer {pl}\tteachers
        Bank {f}\tbank
        Banken {pl}\tbanks
        Bank {vi}\tto bank
        Album {n}\talbum
        Alb {m}\telf
        Albe {f}\talb
        Alben {pl}\talbums
        Maus {f}\tmouse
        Mäuse {pl}\tmice
        """.write(to: fixture, atomically: true, encoding: .utf8)
        try """
        # DE-RU vocabulary database
        Hund {m}\tсобака
        Hunde {pl}\tсобаки
        Museum {n}\tмузей
        Museen {pl}\tмузеи
        """.write(to: russianFixture, atomically: true, encoding: .utf8)
        try createLectorPluralFixture(at: lectorFixture)

        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        _ = try await store.importDictionary(from: fixture)
        _ = try await store.importDictionary(from: russianFixture)
        _ = try await store.importExplanations(from: lectorFixture)

        let cases: [(singular: String, plurals: [String])] = [
            ("Hund", ["Hunde"]),                 // suffix
            ("Buch", ["Bücher"]),               // umlaut + suffix
            ("Mutter", ["Mütter"]),             // umlaut only
            ("Museum", ["Museen"]),             // stem replacement
            ("Datum", ["Daten"]),               // irregular stem
            ("Kaktus", ["Kakteen"]),            // foreign-word plural
            ("Thema", ["Themata", "Themen"]),  // multiple valid plurals
            ("Lehrer", ["Lehrer"]),             // unchanged spelling
            ("Bank", ["Banken"]),               // noun/verb homonym
        ]
        for item in cases {
            for query in [item.singular] + item.plurals {
                let familySpellings = Set([item.singular] + item.plurals)
                let results = try await store.searchDictionary(query)
                let nounGroups = results.filter {
                    $0.kind == .noun && familySpellings.contains($0.german)
                }
                let entry = try XCTUnwrap(nounGroups.first, "query: \(query)")

                XCTAssertEqual(nounGroups.count, 1, "query: \(query)")
                XCTAssertEqual(entry.german, item.singular, "query: \(query)")
                XCTAssertEqual(Set(entry.pluralForms), Set(item.plurals), "query: \(query)")
            }
        }

        let russianPluralResults = try await store.searchDictionary("собаки")
        let dog = try XCTUnwrap(russianPluralResults.first)
        XCTAssertEqual(dog.german, "Hund")
        XCTAssertEqual(dog.gender, .masculine)
        XCTAssertEqual(dog.meanings.map(\.language), [
            .english, .english, .russian, .english, .english, .russian
        ])
        XCTAssertEqual(dog.meanings.map(\.translation), [
            "dog", "hound", "собака", "dogs", "hounds", "собаки"
        ])

        let bankResults = try await store.searchDictionary("Banken")
        XCTAssertEqual(Set(bankResults.filter { $0.german == "Bank" }.map(\.kind)), [.noun, .verb])

        let ambiguousResults = try await store.searchDictionary("Alben")
        XCTAssertTrue(ambiguousResults.contains { $0.german == "Alben" && $0.gender == .plural })
        XCTAssertFalse(ambiguousResults.contains {
            $0.gender != .plural && $0.pluralForms.contains("Alben")
        })

        let unlinkedMouseResults = try await store.searchDictionary("Mäuse")
        let unlinkedMouseFamily = unlinkedMouseResults.filter {
            $0.kind == .noun && ($0.german == "Maus" || $0.german == "Mäuse")
        }
        XCTAssertEqual(unlinkedMouseFamily.count, 2, "Unlinked spellings must not be guessed into one group")
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

    func testLoadsAGroupedMultilingualDictionaryEntryByID() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let english = directory.appendingPathComponent("dict-en.txt")
        let russian = directory.appendingPathComponent("dict-ru.txt")
        try "# DE-EN vocabulary database\nMädchen {n}\tgirl\nMädchen {n}\tmaiden\n"
            .write(to: english, atomically: true, encoding: .utf8)
        try "# DE-RU vocabulary database\nMädchen {n}\tдевочка\n"
            .write(to: russian, atomically: true, encoding: .utf8)

        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        _ = try await store.importDictionary(from: english)
        _ = try await store.importDictionary(from: russian)
        let searchResults = try await store.searchDictionary("Mädchen")
        let searchEntry = try XCTUnwrap(searchResults.first)
        let storedEntry = try await store.dictionaryEntry(id: searchEntry.id)
        let loadedEntry = try XCTUnwrap(storedEntry)

        XCTAssertEqual(loadedEntry.id, searchEntry.id)
        XCTAssertEqual(loadedEntry.meanings.map(\.translation), ["girl", "maiden", "девочка"])
        XCTAssertEqual(loadedEntry.meanings.map(\.language), [.english, .english, .russian])
        let missingEntry = try await store.dictionaryEntry(id: 999_999)
        XCTAssertNil(missingEntry)
    }

    func testInflectedVerbSearchPrefersTheBaseVerbOverLiteralHomonyms() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = directory.appendingPathComponent("dict.txt")
        try """
        bin\tam
        Sein {n}\tbeing
        sein {vi}\tto be
        sein\this
        """.write(to: fixture, atomically: true, encoding: .utf8)

        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        _ = try await store.importDictionary(from: fixture)
        let results = try await store.searchDictionary("bin")

        XCTAssertEqual(GermanMorphology.lookupTerms(for: "bin"), ["bin", "sein"])
        XCTAssertEqual(results.first?.german, "sein")
        XCTAssertEqual(results.first?.kind, .verb)
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

    func testSavedCardKeepsTranslationLanguagesAndDictCCMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let english = directory.appendingPathComponent("english.txt")
        let russian = directory.appendingPathComponent("russian.txt")
        let databaseURL = directory.appendingPathComponent("test.sqlite3")
        try "# DE-EN vocabulary database\nHaus {n} [building]\thouse <building>\tnoun common\tarchitecture\n"
            .write(to: english, atomically: true, encoding: .utf8)
        try "# DE-RU vocabulary database\nHaus {n}\tдом {м}\tnoun\tarchitecture\n"
            .write(to: russian, atomically: true, encoding: .utf8)

        let store = try LocalStore(url: databaseURL)
        _ = try await store.importDictionary(from: english)
        _ = try await store.importDictionary(from: russian)
        let entryResults = try await store.searchDictionary("Haus")
        let entry = try XCTUnwrap(entryResults.first)
        let saved = try await store.addCard(from: entry)
        var updated = saved
        updated.notes = "remember this"
        try await store.updateCard(updated)
        let storedCard = try await store.personalCard(id: saved.id)
        let reloaded = try XCTUnwrap(storedCard)

        XCTAssertEqual(reloaded.resolvedMeanings.map(\.language), [.english, .russian])
        XCTAssertEqual(reloaded.resolvedMeanings.map(\.translation), ["house", "дом"])
        XCTAssertEqual(reloaded.resolvedMeanings.first?.grammar, "noun common")
        XCTAssertEqual(reloaded.resolvedMeanings.first?.subject, "architecture")
        XCTAssertEqual(reloaded.notes, "remember this")
    }

    func testImportsRichLectorDetailsAndBroadMorphologyWithoutAddingHeadwords() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let dictionary = directory.appendingPathComponent("dict.txt")
        let lector = directory.appendingPathComponent("dictionary-de.db")
        try "Haus {n}\thouse\tnoun\t\nlaufen\tto run\tverb\t\nhoch\thigh\tadj\t\nzwei\ttwo\tnum\t\n"
            .write(to: dictionary, atomically: true, encoding: .utf8)
        try createRichLectorFixture(at: lector)

        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        _ = try await store.importDictionary(from: dictionary)
        _ = try await store.importExplanations(from: lector)

        let houseResults = try await store.searchDictionary("Haus")
        let house = try XCTUnwrap(houseResults.first)
        XCTAssertEqual(house.ipa, "[haʊ̯s]")
        XCTAssertEqual(house.etymology, "From Middle High German hūs.")
        XCTAssertEqual(Set(house.relatedForms.map(\.word)), ["Häuschen", "häuslich"])
        XCTAssertTrue(house.forms.contains { $0.form == "hauses" && $0.tags.contains("genitive") })
        let genitiveResults = try await store.searchDictionary("hauses")
        XCTAssertEqual(genitiveResults.first?.german, "Haus")

        let laufenResults = try await store.searchDictionary("laufen")
        let laufen = try XCTUnwrap(laufenResults.first)
        XCTAssertTrue(laufen.forms.contains { $0.form == "liefe" && $0.tags.contains("subjunctive") })
        XCTAssertTrue(laufen.forms.contains { $0.form == "lauf" && $0.tags.contains("imperative") })
        let subjunctiveResults = try await store.searchDictionary("liefe")
        XCTAssertEqual(subjunctiveResults.first?.german, "laufen")

        let hochResults = try await store.searchDictionary("hoch")
        let hoch = try XCTUnwrap(hochResults.first)
        XCTAssertTrue(hoch.forms.contains { $0.form == "hohem" && $0.tags.contains("dative") })
        let declinedResults = try await store.searchDictionary("hohem")
        XCTAssertEqual(declinedResults.first?.german, "hoch")
        let numeralResults = try await store.searchDictionary("zweien")
        XCTAssertEqual(numeralResults.first?.german, "zwei")
        XCTAssertTrue(numeralResults.first?.forms.contains { $0.form == "zweien" } == true)
        XCTAssertFalse(house.forms.contains { $0.form == "de-ndecl" })
        let relatedHeadwordResults = try await store.searchDictionary("Häuschen")
        XCTAssertTrue(relatedHeadwordResults.isEmpty)
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

    func testImportsLectorVerbAndAdjectiveFormsAndEnrichesExistingCards() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let dictionary = directory.appendingPathComponent("dict.txt")
        let lector = directory.appendingPathComponent("dictionary-de.db")
        try """
        wohnen\tto live\tverb\t
        gehen\tto go\tverb\t
        haben\tto have\tverb\t
        auf|stehen\tto get up\tverb\t
        gut\tgood\tadj\t
        klein\tsmall\tadj\t
        viel\tmuch\tadj\t
        besser\tpreferably\tadv\t
        besten\tthe best ones\tother\t
        kleiner\ta small one\tother\t
        ging\ta thing\tother\t
        """.write(to: dictionary, atomically: true, encoding: .utf8)
        try createLectorMorphologyFixture(at: lector)

        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        _ = try await store.importDictionary(from: dictionary)
        let wohnenBeforeResults = try await store.searchDictionary("wohnen")
        let wohnenBeforeImport = try XCTUnwrap(wohnenBeforeResults.first)
        let existingCard = try await store.addCard(from: wohnenBeforeImport)
        XCTAssertTrue(existingCard.forms.isEmpty)

        _ = try await store.importExplanations(from: lector)

        let wohnenResults = try await store.searchDictionary("wohnen")
        let wohnen = try XCTUnwrap(wohnenResults.first)
        let wohnenInfo = GermanMorphology.info(for: wohnen)
        XCTAssertEqual(wohnenInfo.rows.map(\.value), [
            "wohnen",
            "ich wohne · du wohnst · er/sie wohnt · wir wohnen · ihr wohnt · sie wohnen",
            "wohnte",
            "haben gewohnt",
            "werden + wohnen"
        ])
        XCTAssertFalse(wohnenInfo.isEstimated)

        let participleResults = try await store.searchDictionary("gewohnt")
        XCTAssertEqual(participleResults.first?.german, "wohnen")
        XCTAssertEqual(participleResults.first?.kind, .verb)

        let auxiliaryResults = try await store.searchDictionary("haben")
        XCTAssertEqual(auxiliaryResults.first?.german, "haben")

        let gehenResults = try await store.searchDictionary("gehen")
        let gehen = try XCTUnwrap(gehenResults.first)
        XCTAssertTrue(gehen.forms.contains { $0.form == "ging" && $0.tags == ["past"] })
        XCTAssertEqual(GermanMorphology.info(for: gehen).rows.first { $0.label == "Perfect" }?.value, "sein gegangen")

        let pastResults = try await store.searchDictionary("ging")
        XCTAssertEqual(pastResults.first?.german, "gehen")
        XCTAssertEqual(pastResults.first?.kind, .verb)

        let aufstehenResults = try await store.searchDictionary("aufstehen")
        let aufstehen = try XCTUnwrap(aufstehenResults.first)
        let aufstehenInfo = GermanMorphology.info(for: aufstehen)
        XCTAssertEqual(
            aufstehenInfo.rows.first { $0.label == "Present" }?.value,
            "ich stehe auf · du stehst auf · er/sie steht auf · wir stehen auf · ihr steht auf · sie stehen auf"
        )
        XCTAssertEqual(aufstehenInfo.rows.first { $0.label == "Simple past" }?.value, "stand auf")
        XCTAssertEqual(aufstehenInfo.rows.first { $0.label == "Perfect" }?.value, "haben/sein aufgestanden")
        XCTAssertFalse(aufstehenInfo.isEstimated)

        for (lemma, expected) in [
            ("gut", ["gut", "besser", "am besten"]),
            ("klein", ["klein", "kleiner", "am kleinsten"]),
            ("viel", ["viel", "mehr", "am meisten"])
        ] {
            let results = try await store.searchDictionary(lemma)
            let entry = try XCTUnwrap(results.first)
            let info = GermanMorphology.info(for: entry)
            XCTAssertEqual(info.rows.map(\.value), expected, lemma)
            XCTAssertFalse(info.isEstimated, lemma)
        }

        for (query, lemma) in [
            ("besser", "gut"),
            ("besten", "gut"),
            ("am besten", "gut"),
            ("kleiner", "klein"),
            ("kleinsten", "klein"),
            ("kleinst", "klein"),
            ("am kleinsten", "klein"),
            ("mehr", "viel"),
            ("meisten", "viel"),
            ("am meisten", "viel")
        ] {
            let results = try await store.searchDictionary(query)
            XCTAssertEqual(results.first?.german, lemma, query)
            XCTAssertEqual(results.first?.kind, .adjective, query)
        }

        let cards = try await store.cards()
        let enrichedCard = try XCTUnwrap(cards.first)
        XCTAssertEqual(enrichedCard.id, existingCard.id)
        XCTAssertTrue(enrichedCard.forms.contains { $0.form == "gewohnt" })
    }

    func testLectorInflectionImportFailureRollsBackExplanationsAndForms() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("test.sqlite3")
        let lector = directory.appendingPathComponent("dictionary-de.db")
        try createLectorMorphologyFixture(at: lector)
        let store = try LocalStore(url: databaseURL)
        _ = try await store.importExplanations(from: lector)
        let oldExplanations = try readTextValues(
            at: databaseURL,
            sql: "SELECT explanation FROM dictionary_explanations ORDER BY explanation"
        )
        let oldForms = try readTextValues(
            at: databaseURL,
            sql: "SELECT lemma_key || ':' || form || ':' || tags FROM dictionary_inflections ORDER BY lemma_key, form, tags"
        )
        try executeSQLite(at: databaseURL, sql: """
            CREATE TRIGGER reject_lector_inflection
            BEFORE INSERT ON dictionary_inflections
            BEGIN
              SELECT RAISE(ABORT, 'forced inflection import failure');
            END;
            """)

        do {
            _ = try await store.importExplanations(from: lector)
            XCTFail("The forced inflection failure should fail the whole import")
        } catch {
            // Expected: explanation and inflection replacement share one transaction.
        }

        XCTAssertEqual(
            try readTextValues(at: databaseURL, sql: "SELECT explanation FROM dictionary_explanations ORDER BY explanation"),
            oldExplanations
        )
        XCTAssertEqual(
            try readTextValues(
                at: databaseURL,
                sql: "SELECT lemma_key || ':' || form || ':' || tags FROM dictionary_inflections ORDER BY lemma_key, form, tags"
            ),
            oldForms
        )
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

    func testMovingCardBetweenListsIsAtomic() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        try await store.seedStarterDictionaryIfNeeded()
        let houseResults = try await store.searchDictionary("Haus")
        let house = try XCTUnwrap(houseResults.first)
        let travel = try await store.createWordList(name: "Travel")
        let card = try await store.addCard(from: house)

        do {
            try await store.moveCard(card.id, fromList: WordList.defaultID, toList: Int64.max)
            XCTFail("Moving to a missing list should fail")
        } catch {
            // Expected: the foreign-key failure must roll back the entire move.
        }
        let defaultCardsAfterFailure = try await store.cards()
        let travelCardsAfterFailure = try await store.cards(listID: travel.id)
        XCTAssertEqual(defaultCardsAfterFailure.map(\.id), [card.id])
        XCTAssertEqual(travelCardsAfterFailure, [])

        try await store.moveCard(card.id, fromList: WordList.defaultID, toList: travel.id)
        let defaultCardsAfterMove = try await store.cards()
        let travelCardsAfterMove = try await store.cards(listID: travel.id)
        XCTAssertEqual(defaultCardsAfterMove, [])
        XCTAssertEqual(travelCardsAfterMove.map(\.id), [card.id])
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

    func testSentenceAnalysisPersistsThroughReloadAndUndoRestore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("test.sqlite3")
        let analysis = sentenceAnalysisFixture()
        let sentence = "Ich komme rein."

        let store = try LocalStore(url: databaseURL)
        let list = try await store.createWordList(name: "Travel")
        let inserted = try await store.saveSentences([
            SentenceDraft(
                german: sentence,
                translation: "I come in.",
                tokens: SentenceTokenizer.tokens(in: sentence),
                analysis: analysis
            )
        ], sourceList: list)
        let saved = try XCTUnwrap(inserted.first)
        XCTAssertEqual(saved.analysis, analysis)

        let reopened = try LocalStore(url: databaseURL)
        let reloadedSentences = try await reopened.savedSentences()
        XCTAssertEqual(reloadedSentences.first?.analysis, analysis)

        try await reopened.deleteSentence(id: saved.id)
        try await reopened.restoreSentences([saved])
        let restoredSentences = try await reopened.savedSentences()
        XCTAssertEqual(restoredSentences.first?.analysis, analysis)
    }

    func testSavingAnalyzedSentenceBatchRollsBackTogether() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("test.sqlite3")
        let store = try LocalStore(url: databaseURL)
        let list = try await store.createWordList(name: "Travel")
        try executeSQLite(at: databaseURL, sql: """
            CREATE TRIGGER reject_second_analyzed_sentence
            BEFORE INSERT ON saved_sentences
            WHEN new.german = 'Satz zwei.'
            BEGIN
              SELECT RAISE(ABORT, 'forced analyzed sentence failure');
            END;
            """)
        let drafts = ["Satz eins.", "Satz zwei."].map {
            SentenceDraft(
                german: $0,
                translation: $0,
                tokens: SentenceTokenizer.tokens(in: $0),
                analysis: sentenceAnalysisFixture()
            )
        }

        do {
            _ = try await store.saveSentences(drafts, sourceList: list)
            XCTFail("Expected sentence batch to fail")
        } catch {}

        let savedAfterFailure = try await store.savedSentences()
        XCTAssertTrue(savedAfterFailure.isEmpty)
    }

    func testRemovedCardCanBeRestoredWithStudyHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reviewedAt = Date(timeIntervalSince1970: 1_704_153_600)
        let store = try LocalStore(
            url: directory.appendingPathComponent("test.sqlite3"),
            now: { reviewedAt }
        )
        try await store.seedStarterDictionaryIfNeeded()
        let houseResults = try await store.searchDictionary("Haus")
        let house = try XCTUnwrap(houseResults.first)
        let card = try await store.addCard(from: house)
        let reviewed = try await store.review(
            card: card,
            rating: .good,
            now: reviewedAt,
            calendar: .current
        )

        let removal = try await store.removeCardRecordingChange(
            card.id,
            fromList: WordList.defaultID
        )
        let mutation = try XCTUnwrap(removal)
        let cardAfterRemoval = try await store.personalCard(id: card.id)
        XCTAssertNil(cardAfterRemoval)

        try await store.restoreRemovedCard(mutation)

        let restoredCard = try await store.personalCard(id: card.id)
        let restored = try XCTUnwrap(restoredCard)
        let restoredCards = try await store.cards()
        let restoredStats = try await store.stats(
            listID: WordList.defaultID,
            now: reviewedAt,
            calendar: .current
        )
        XCTAssertEqual(restored, reviewed)
        XCTAssertEqual(restoredCards.map(\.id), [card.id])
        XCTAssertEqual(restoredStats.reviewsToday, 1)
    }

    func testDeletedListCanBeRestoredWithCardsAndSentenceLinks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite3"))
        try await store.seedStarterDictionaryIfNeeded()
        let houseResults = try await store.searchDictionary("Haus")
        let house = try XCTUnwrap(houseResults.first)
        let travel = try await store.createWordList(name: "Travel")
        let card = try await store.addCard(from: house, listID: travel.id)
        let draft = SentenceDraft(
            german: "Das Haus ist groß.",
            translation: "The house is big.",
            tokens: SentenceTokenizer.tokens(in: "Das Haus ist groß.")
        )
        let insertedSentences = try await store.saveSentences([draft], sourceList: travel)
        let sentence = try XCTUnwrap(insertedSentences.first)

        let mutation = try await store.deleteWordListRecordingChange(id: travel.id)
        let deletedCard = try await store.personalCard(id: card.id)
        let sentencesAfterDeletion = try await store.savedSentences()
        XCTAssertNil(deletedCard)
        XCTAssertNil(sentencesAfterDeletion.first?.sourceListID)

        try await store.restoreDeletedWordList(mutation)

        let restoredLists = try await store.wordLists()
        let restoredCards = try await store.cards(listID: travel.id)
        let restoredSentences = try await store.savedSentences()
        XCTAssertTrue(restoredLists.contains { $0.id == travel.id && $0.name == travel.name })
        XCTAssertEqual(restoredCards.map(\.id), [card.id])
        XCTAssertEqual(restoredSentences.first?.id, sentence.id)
        XCTAssertEqual(restoredSentences.first?.sourceListID, travel.id)
    }

    func testRestoringDeletedListRollsBackEveryWriteOnFailure() async throws {
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
        let mutation = try await store.deleteWordListRecordingChange(id: travel.id)
        try executeSQLite(at: databaseURL, sql: """
            CREATE TRIGGER reject_restored_membership
            BEFORE INSERT ON card_lists
            BEGIN
              SELECT RAISE(ABORT, 'forced membership failure');
            END;
            """)

        do {
            try await store.restoreDeletedWordList(mutation)
            XCTFail("Expected list restoration to fail")
        } catch {}

        let listsAfterFailure = try await store.wordLists()
        let cardAfterFailure = try await store.personalCard(id: card.id)
        XCTAssertFalse(listsAfterFailure.contains { $0.id == travel.id })
        XCTAssertNil(cardAfterFailure)
    }

    func testDeletingMultipleSentencesRollsBackAsOneMutation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("test.sqlite3")
        let store = try LocalStore(url: databaseURL)
        let source = try await store.createWordList(name: "Travel")
        let drafts = [
            SentenceDraft(german: "Satz eins.", translation: "Sentence one.", tokens: SentenceTokenizer.tokens(in: "Satz eins.")),
            SentenceDraft(german: "Satz zwei.", translation: "Sentence two.", tokens: SentenceTokenizer.tokens(in: "Satz zwei."))
        ]
        let sentences = try await store.saveSentences(drafts, sourceList: source)
        let rejectedID = try XCTUnwrap(sentences.last?.id)
        try executeSQLite(at: databaseURL, sql: """
            CREATE TRIGGER reject_second_sentence_delete
            BEFORE DELETE ON saved_sentences
            WHEN old.id = \(rejectedID)
            BEGIN
              SELECT RAISE(ABORT, 'forced sentence failure');
            END;
            """)

        do {
            try await store.deleteSentences(ids: sentences.map(\.id))
            XCTFail("Expected sentence deletion to fail")
        } catch {}

        let sentencesAfterFailure = try await store.savedSentences()
        XCTAssertEqual(sentencesAfterFailure.count, 2)
    }

    func testSentenceTokenizerKeepsDisplayPunctuationOutOfLookupTerm() {
        let tokens = SentenceTokenizer.tokens(in: "„Das Haus“, sagte Anna.")

        XCTAssertEqual(tokens.map(\.surface), ["„Das", "Haus“,", "sagte", "Anna."])
        XCTAssertEqual(tokens.map(\.lookupTerm), ["Das", "Haus", "sagte", "Anna"])
    }

    func testSentenceTokenizerUsesMappedSeparableVerbForDetachedPrefix() {
        let tokens = [
            SentenceToken(index: 0, surface: "Das", lookupTerm: "Das"),
            SentenceToken(index: 1, surface: "Blatt", lookupTerm: "Blatt"),
            SentenceToken(index: 2, surface: "fällt", lookupTerm: "abfallen", cardID: 42),
            SentenceToken(index: 3, surface: "ab.", lookupTerm: "ab")
        ]

        let resolved = SentenceTokenizer.contextualLookupToken(for: tokens[3], in: tokens)

        XCTAssertEqual(resolved.surface, "ab.")
        XCTAssertEqual(resolved.lookupTerm, "abfallen")
        XCTAssertEqual(resolved.cardID, 42)
        XCTAssertEqual(
            SentenceTokenizer.relatedTokenIndices(for: tokens[2], in: tokens),
            [2, 3]
        )
        XCTAssertEqual(
            SentenceTokenizer.relatedTokenIndices(for: tokens[3], in: tokens),
            [2, 3]
        )
    }

    func testSentenceTokenizerLinksDeterminerAndNounInBothDirections() {
        let tokens = [
            SentenceToken(index: 0, surface: "Der", lookupTerm: "Der"),
            SentenceToken(index: 1, surface: "große", lookupTerm: "groß"),
            SentenceToken(index: 2, surface: "Hund", lookupTerm: "Hund", cardID: 24),
            SentenceToken(index: 3, surface: "schläft.", lookupTerm: "schlafen")
        ]

        let resolvedArticle = SentenceTokenizer.contextualLookupToken(
            for: tokens[0],
            in: tokens,
            nounTokenIndices: [2]
        )

        XCTAssertEqual(resolvedArticle.lookupTerm, "Hund")
        XCTAssertEqual(resolvedArticle.cardID, 24)
        XCTAssertEqual(
            SentenceTokenizer.relatedTokenIndices(
                for: tokens[0],
                in: tokens,
                nounTokenIndices: [2]
            ),
            [0, 2]
        )
        XCTAssertEqual(
            SentenceTokenizer.relatedTokenIndices(
                for: tokens[2],
                in: tokens,
                nounTokenIndices: [2]
            ),
            [0, 2]
        )
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

private func createLectorPluralFixture(at url: URL) throws {
    try executeSQLite(at: url, sql: """
        CREATE TABLE entries (word TEXT PRIMARY KEY);
        CREATE TABLE senses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          word TEXT NOT NULL,
          pos TEXT,
          gloss TEXT NOT NULL,
          sort_order INTEGER DEFAULT 0
        );
        CREATE TABLE inflections (
          inflected_form TEXT NOT NULL,
          lemma TEXT NOT NULL,
          type TEXT,
          PRIMARY KEY (inflected_form, lemma)
        );
        INSERT INTO entries (word) VALUES
          ('hund'), ('hunde'), ('buch'), ('bücher'), ('mutter'), ('mütter'),
          ('museum'), ('museen'), ('datum'), ('daten'), ('kaktus'), ('kakteen'),
          ('thema'), ('themata'), ('themen'), ('lehrer'), ('bank'), ('banken'),
          ('album'), ('alb'), ('albe'), ('alben'), ('gehen');
        INSERT INTO senses (word, pos, gloss) VALUES
          ('hund', 'noun', 'dog'),
          ('hunde', 'noun', 'dogs'),
          ('buch', 'noun', 'book'),
          ('bücher', 'noun', 'books'),
          ('mutter', 'noun', 'mother'),
          ('mütter', 'noun', 'mothers'),
          ('museum', 'noun', 'museum'),
          ('museen', 'noun', 'museums'),
          ('datum', 'noun', 'date'),
          ('daten', 'noun', 'data'),
          ('kaktus', 'noun', 'cactus'),
          ('kakteen', 'noun', 'cacti'),
          ('thema', 'noun', 'topic'),
          ('themata', 'noun', 'formal topics'),
          ('themen', 'noun', 'topics'),
          ('lehrer', 'noun', 'teacher'),
          ('bank', 'noun', 'bank'),
          ('banken', 'noun', 'banks'),
          ('album', 'noun', 'album'),
          ('alb', 'noun', 'elf'),
          ('albe', 'noun', 'alb'),
          ('alben', 'noun', 'albums'),
          ('gehen', 'verb', 'to go');
        INSERT INTO inflections (inflected_form, lemma, type) VALUES
          ('hunde', 'hund', 'plural'),
          ('bücher', 'buch', 'plural'),
          ('mütter', 'mutter', 'plural'),
          ('museen', 'museum', 'plural'),
          ('daten', 'datum', 'plural'),
          ('kakteen', 'kaktus', 'plural'),
          ('themata', 'thema', 'honorific,plural'),
          ('themen', 'thema', 'plural'),
          ('banken', 'bank', 'plural'),
          ('alben', 'album', 'plural'),
          ('alben', 'alb', 'plural'),
          ('alben', 'albe', 'plural'),
          ('gehen', 'gehen', 'first-person,present,plural');
        """)
}

private func createLectorMorphologyFixture(at url: URL) throws {
    try executeSQLite(at: url, sql: """
        CREATE TABLE entries (word TEXT PRIMARY KEY);
        CREATE TABLE senses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          word TEXT NOT NULL,
          pos TEXT,
          gloss TEXT NOT NULL,
          sort_order INTEGER DEFAULT 0
        );
        CREATE TABLE inflections (
          inflected_form TEXT NOT NULL,
          lemma TEXT NOT NULL,
          type TEXT,
          PRIMARY KEY (inflected_form, lemma)
        );
        INSERT INTO entries (word) VALUES
          ('besser'), ('besten'), ('kleiner'), ('kleinsten'), ('kleinst'), ('mehr'), ('meisten');
        INSERT INTO senses (word, pos, gloss, sort_order) VALUES
          ('besser', 'adj', 'comparative degree of gut; better', 0),
          ('besten', 'adj', 'superlative degree of gut: (best)', 0),
          ('kleiner', 'adj', 'comparative degree of klein', 0),
          ('kleinsten', 'adj', 'superlative degree of klein', 0),
          ('kleinst', 'adj', 'superlative degree of klein: smallest', 1),
          ('mehr', 'det', 'comparative degree of viel: more', 0),
          ('meisten', 'adj', 'superlative degree of viel', 0);
        INSERT INTO inflections (inflected_form, lemma, type) VALUES
          ('haben', 'wohnen', 'auxiliary'),
          ('wohne', 'wohnen', 'first-person,indicative,present,singular'),
          ('wohnst', 'wohnen', 'indicative,present,second-person,singular'),
          ('wohnt', 'wohnen', 'present,singular,third-person'),
          ('wohnte', 'wohnen', 'past'),
          ('gewohnt', 'wohnen', 'participle,past'),
          ('sein', 'gehen', 'auxiliary'),
          ('gehe', 'gehen', 'first-person,indicative,present,singular'),
          ('gehst', 'gehen', 'indicative,present,second-person,singular'),
          ('geht', 'gehen', 'present,singular,third-person'),
          ('ging', 'gehen', 'past'),
          ('gegangen', 'gehen', 'participle,past'),
          ('haben', 'aufstehen', 'auxiliary'),
          ('sein', 'aufstehen', 'auxiliary'),
          ('aufstehe', 'aufstehen', 'first-person,indicative,present,singular,subordinate-clause'),
          ('aufstehst', 'aufstehen', 'indicative,present,second-person,singular,subordinate-clause'),
          ('aufsteht', 'aufstehen', 'present,singular,third-person,subordinate-clause'),
          ('aufstand', 'aufstehen', 'first-person,indicative,preterite,singular,subordinate-clause'),
          ('aufgestanden', 'aufstehen', 'participle,past');
        """)
}

private func createRichLectorFixture(at url: URL) throws {
    try executeSQLite(at: url, sql: """
        CREATE TABLE entries (
          word TEXT PRIMARY KEY,
          rank INTEGER,
          ipa TEXT,
          etymology TEXT
        );
        CREATE TABLE senses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          word TEXT NOT NULL,
          pos TEXT,
          gloss TEXT NOT NULL,
          sort_order INTEGER DEFAULT 0
        );
        CREATE TABLE inflections (
          inflected_form TEXT NOT NULL,
          lemma TEXT NOT NULL,
          type TEXT
        );
        CREATE TABLE related_forms (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          word TEXT NOT NULL,
          related_word TEXT NOT NULL,
          relation TEXT NOT NULL
        );
        INSERT INTO entries (word, ipa, etymology) VALUES
          ('haus', '[haʊ̯s]', 'From Middle High German hūs.'),
          ('laufen', '[ˈlaʊ̯fn̩]', 'From Middle High German loufen.'),
          ('hoch', '[hoːx]', 'From Old High German hōh.'),
          ('zwei', '[t͡svaɪ̯]', NULL),
          ('häuschen', NULL, NULL),
          ('häuslich', NULL, NULL);
        INSERT INTO senses (word, pos, gloss) VALUES
          ('haus', 'noun', 'house'),
          ('laufen', 'verb', 'to run'),
          ('hoch', 'adj', 'high'),
          ('zwei', 'num', 'two'),
          ('häuschen', 'noun', 'small house'),
          ('häuslich', 'adj', 'domestic');
        INSERT INTO inflections (inflected_form, lemma, type) VALUES
          ('häuser', 'haus', 'nominative,plural'),
          ('hauses', 'haus', 'genitive,singular'),
          ('hause', 'haus', 'dative,singular'),
          ('liefe', 'laufen', 'first-person,singular,subjunctive,preterite'),
          ('lauf', 'laufen', 'imperative,singular'),
          ('gelaufen', 'laufen', 'participle,past'),
          ('hohem', 'hoch', 'dative,masculine,singular,strong'),
          ('höher', 'hoch', 'comparative'),
          ('zweien', 'zwei', 'dative'),
          ('de-ndecl', 'haus', 'inflection-template'),
          ('strong', 'hoch', 'table-tags');
        INSERT INTO related_forms (word, related_word, relation) VALUES
          ('haus', 'Häuschen', 'diminutive'),
          ('haus', 'häuslich', 'derived');
        """)
}

private func createVersionOneClassificationFixture(at url: URL) throws {
    try executeSQLite(at: url, sql: """
        PRAGMA user_version = 1;
        CREATE TABLE dictionary_entries (
          id INTEGER PRIMARY KEY,
          german TEXT NOT NULL,
          english TEXT NOT NULL,
          normalized_german TEXT NOT NULL,
          normalized_english TEXT NOT NULL,
          raw_german TEXT NOT NULL,
          raw_english TEXT NOT NULL,
          kind TEXT NOT NULL
        );
        CREATE VIRTUAL TABLE dictionary_fts USING fts5(
          german, english, content='dictionary_entries', content_rowid='id',
          tokenize='unicode61 remove_diacritics 2'
        );
        CREATE TABLE personal_cards (
          id INTEGER PRIMARY KEY,
          dictionary_entry_id INTEGER,
          kind TEXT NOT NULL,
          notes TEXT NOT NULL
        );
        INSERT INTO dictionary_entries (
          id, german, english, normalized_german, normalized_english,
          raw_german, raw_english, kind
        ) VALUES
          (1, 'sein', 'his', 'sein', 'his', 'sein', 'his [determiner]', 'other'),
          (2, 'Hallo', 'hello', 'hallo', 'hello', 'Hallo', 'hello', 'other');
        INSERT INTO dictionary_fts(dictionary_fts) VALUES ('rebuild');
        INSERT INTO personal_cards (id, dictionary_entry_id, kind, notes) VALUES
          (1, 1, 'other', 'keep me'),
          (2, 2, 'other', 'also keep me');
    """)
}

private func createVersionTwoSearchFixture(at url: URL, omitNormalizedEnglish: Bool = false) throws {
    let normalizedEnglishColumn = omitNormalizedEnglish ? "" : "normalized_english TEXT NOT NULL,"
    let normalizedEnglishName = omitNormalizedEnglish ? "" : ", normalized_english"
    let normalizedEnglishValue = omitNormalizedEnglish ? "" : ", 'white'"
    try executeSQLite(at: url, sql: """
        PRAGMA user_version = 2;
        CREATE TABLE dictionary_entries (
          id INTEGER PRIMARY KEY,
          german TEXT NOT NULL,
          english TEXT NOT NULL,
          normalized_german TEXT NOT NULL,
          \(normalizedEnglishColumn)
          raw_german TEXT NOT NULL,
          raw_english TEXT NOT NULL,
          kind TEXT NOT NULL,
          gender TEXT NOT NULL,
          usage TEXT,
          source TEXT NOT NULL,
          translation_language TEXT NOT NULL DEFAULT 'en',
          explanation TEXT
        );
        CREATE VIRTUAL TABLE dictionary_fts USING fts5(
          german, english, content='dictionary_entries', content_rowid='id',
          tokenize='unicode61 remove_diacritics 2'
        );
        CREATE TABLE dictionary_explanations (
          id INTEGER PRIMARY KEY,
          german_key TEXT NOT NULL,
          kind TEXT NOT NULL,
          explanation TEXT NOT NULL,
          source TEXT NOT NULL,
          sort_order INTEGER NOT NULL DEFAULT 0
        );
        INSERT INTO dictionary_entries (
          id, german, english, normalized_german\(normalizedEnglishName),
          raw_german, raw_english, kind, gender, source
        ) VALUES (
          1, 'Weiß', 'white', 'weiss'\(normalizedEnglishValue),
          'Weiß {n}', 'white', 'noun', 'neuter', 'dict.cc'
        );
        INSERT INTO dictionary_fts(dictionary_fts) VALUES ('rebuild');
    """)
}

private func sentenceAnalysisFixture() -> SentenceAnalysis {
    SentenceAnalysis(
        engine: "UDPipe 2",
        model: "german-hdt-test",
        tokens: [
            SentenceAnalysisToken(
                id: 1,
                surface: "komme",
                lemma: "kommen",
                universalPartOfSpeech: "VERB",
                languageSpecificPartOfSpeech: "VVFIN",
                morphologicalFeatures: ["Tense": "Pres"],
                headID: nil,
                dependencyRelation: "root",
                startUTF16: 4,
                lengthUTF16: 5
            )
        ],
        rawCoNLLU: "1\tkomme\tkommen\tVERB\tVVFIN\tTense=Pres\t0\troot\t_\t_\n"
    )
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

private func readTextValues(at url: URL, sql: String) throws -> [String] {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        sqlite3_close(database)
        throw NSError(domain: "LocalStoreTests", code: 8)
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
        throw NSError(domain: "LocalStoreTests", code: 9)
    }
    defer { sqlite3_finalize(statement) }
    var values: [String] = []
    while true {
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return values }
        guard step == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else {
            throw NSError(domain: "LocalStoreTests", code: 10)
        }
        values.append(String(cString: value))
    }
}
