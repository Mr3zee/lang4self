import Foundation
import SQLite3

public struct ImportProgress: Sendable, Equatable {
    public let imported: Int
    public let bytesRead: Int64
    public let totalBytes: Int64

    public init(imported: Int, bytesRead: Int64, totalBytes: Int64) {
        self.imported = imported
        self.bytesRead = bytesRead
        self.totalBytes = totalBytes
    }

    public var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(bytesRead) / Double(totalBytes))
    }
}

public enum LocalStoreError: LocalizedError {
    case open(String)
    case sqlite(String)
    case invalidDictionaryFile
    case invalidListName
    case duplicateListName
    case cannotDeleteDefaultList

    public var errorDescription: String? {
        switch self {
        case .open(let message): "Could not open the local database: \(message)"
        case .sqlite(let message): "Local database error: \(message)"
        case .invalidDictionaryFile: "This does not look like a tab-delimited dict.cc translation file."
        case .invalidListName: "List names cannot be empty."
        case .duplicateListName: "A list with that name already exists."
        case .cannotDeleteDefaultList: "The My words list cannot be deleted."
        }
    }
}

public actor LocalStore {
    private var database: OpaquePointer?
    public nonisolated let databaseURL: URL
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(url: URL? = nil) throws {
        let resolved: URL
        if let url {
            resolved = url
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("Lang4Self", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            resolved = support.appendingPathComponent("Lang4Self.sqlite3")
        }

        var pointer: OpaquePointer?
        let result = sqlite3_open_v2(
            resolved.path,
            &pointer,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let pointer else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(pointer)
            throw LocalStoreError.open(message)
        }

        do {
            try Self.configure(pointer)
            self.database = pointer
            self.databaseURL = resolved
        } catch {
            sqlite3_close(pointer)
            throw error
        }
    }

    deinit {
        sqlite3_close(database)
    }

    public func dictionaryCount() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM dictionary_entries")
    }

    public func hasCompleteDictionary() throws -> Bool {
        try scalarInt("SELECT COUNT(*) FROM dictionary_entries WHERE source = 'dict.cc'") > 100_000
    }

    public func seedStarterDictionaryIfNeeded() throws {
        guard try dictionaryCount() == 0 else { return }
        let starter = [
            "Haus {n}\thouse", "Frau {f}\twoman", "Mann {m}\tman", "Kind {n}\tchild",
            "Zeit {f}\ttime", "Tag {m}\tday", "Wasser {n}\twater", "Buch {n}\tbook",
            "Stadt {f}\tcity", "Sprache {f}\tlanguage", "gut {adj}\tgood", "groß {adj}\tbig",
            "klein {adj}\tsmall", "neu {adj}\tnew", "alt {adj}\told", "sein {vi}\tto be",
            "haben {vt}\tto have", "gehen {vi}\tto go", "kommen {vi}\tto come", "lernen {vt}\tto learn",
            "sprechen {vt}\tto speak", "verstehen {vt}\tto understand", "auf|stehen {vi}\tto get up",
            "an|rufen {vt}\tto call", "mit|kommen {vi}\tto come along", "Guten Morgen\tgood morning",
            "Danke\tthank you", "Bitte\tplease / you're welcome"
        ]
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            for line in starter {
                if var entry = DictCCParser.parse(line: line) {
                    entry = DictionaryEntry(
                        german: entry.german,
                        english: entry.english,
                        rawGerman: entry.rawGerman,
                        rawEnglish: entry.rawEnglish,
                        kind: entry.kind,
                        gender: entry.gender,
                        usage: entry.usage,
                        source: "starter"
                    )
                    try insertDictionaryEntry(entry)
                }
            }
            try Self.execute(database, "COMMIT")
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    public func searchDictionary(_ query: String, limit: Int = 80) throws -> [DictionaryEntry] {
        let normalized = DictCCParser.normalized(query)
        guard !normalized.isEmpty, limit > 0 else { return [] }
        let tokens = normalized
            .split(whereSeparator: { $0.isWhitespace })
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }
            .joined(separator: " ")
        let sql = """
            SELECT d.id, d.german, d.english, d.raw_german, d.raw_english,
                   d.kind, d.gender, d.usage, d.source
            FROM dictionary_fts
            JOIN dictionary_entries d ON d.id = dictionary_fts.rowid
            WHERE dictionary_fts MATCH ?
            ORDER BY CASE
                       WHEN d.normalized_german = ? THEN 0
                       WHEN d.normalized_english = ? THEN 1
                       ELSE 2
                     END,
                     bm25(dictionary_fts, 1.0, 0.65),
                     length(d.german)
            LIMIT ?
            """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(tokens, to: 1, in: statement)
        bind(normalized, to: 2, in: statement)
        bind(normalized, to: 3, in: statement)
        let requestedLimit = Int32(clamping: limit)
        let candidateLimit = requestedLimit > Int32.max / 8 ? Int32.max : requestedLimit * 8
        sqlite3_bind_int(statement, 4, candidateLimit)
        let matches = try readEntries(statement)
        var seen = Set<DictionaryGroupKey>()
        let representatives = matches.filter { entry in
            seen.insert(DictionaryGroupKey(entry)).inserted
        }.prefix(limit)
        return try representatives.map { try dictionaryGroup(representedBy: $0) }
    }

    @discardableResult
    public func importDictionary(
        from url: URL,
        progress: @escaping @Sendable (ImportProgress) -> Void = { _ in }
    ) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let totalBytes = Int64(values.fileSize ?? 0)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let germanFirst = try detectGermanFirst(in: handle)
        try handle.seek(toOffset: 0)

        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            try Self.execute(database, "DELETE FROM dictionary_entries WHERE source = 'dict.cc'")
            // Building FTS once after the bulk insert is substantially faster than
            // updating its index more than a million times through the trigger.
            try Self.execute(database, "DROP TRIGGER IF EXISTS dictionary_ai; DROP TRIGGER IF EXISTS dictionary_ad; DROP TRIGGER IF EXISTS dictionary_au;")
            let insertStatement = try prepare(dictionaryInsertSQL)
            defer { sqlite3_finalize(insertStatement) }
            var buffer = Data()
            var bytesRead: Int64 = 0
            var imported = 0
            var validLines = 0

            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                buffer.append(chunk)
                bytesRead += Int64(chunk.count)
                while let newline = buffer.firstRange(of: Data([0x0A])) {
                    let lineData = buffer[..<newline.lowerBound]
                    buffer.removeSubrange(...newline.lowerBound)
                    if let line = String(data: lineData, encoding: .utf8), let entry = DictCCParser.parse(line: line, germanFirst: germanFirst) {
                        validLines += 1
                        try insertDictionaryEntry(entry, using: insertStatement)
                        imported += 1
                    }
                }
                if imported % 10_000 < 1_000 {
                    progress(.init(imported: imported, bytesRead: bytesRead, totalBytes: totalBytes))
                }
            }
            if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8), let entry = DictCCParser.parse(line: line, germanFirst: germanFirst) {
                validLines += 1
                try insertDictionaryEntry(entry, using: insertStatement)
                imported += 1
            }
            guard validLines > 0 else { throw LocalStoreError.invalidDictionaryFile }
            try Self.execute(database, "INSERT INTO dictionary_fts(dictionary_fts) VALUES ('rebuild')")
            try Self.createDictionaryTriggers(database)
            try Self.execute(database, "COMMIT")
            try Self.execute(database, "PRAGMA optimize")
            progress(.init(imported: imported, bytesRead: totalBytes, totalBytes: totalBytes))
            return imported
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    @discardableResult
    public func addCard(from entry: DictionaryEntry, listID: Int64 = WordList.defaultID) throws -> PersonalCard {
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            let card: PersonalCard
            if entry.id != 0, let existing = try self.card(forDictionaryEntryID: entry.id) {
                card = existing
            } else {
                let now = Date().timeIntervalSince1970
                let sql = """
                    INSERT INTO personal_cards
                      (dictionary_entry_id, german, english, raw_german, kind, gender, created_at, due_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """
                let statement = try prepare(sql)
                defer { sqlite3_finalize(statement) }
                if entry.id == 0 { sqlite3_bind_null(statement, 1) }
                else { sqlite3_bind_int64(statement, 1, entry.id) }
                bind(entry.german, to: 2, in: statement)
                bind(entry.english, to: 3, in: statement)
                bind(entry.rawGerman, to: 4, in: statement)
                bind(entry.kind.rawValue, to: 5, in: statement)
                bind(entry.gender.rawValue, to: 6, in: statement)
                sqlite3_bind_double(statement, 7, now)
                sqlite3_bind_double(statement, 8, now)
                try stepDone(statement)
                let id = sqlite3_last_insert_rowid(database)
                guard let inserted = try self.card(id: id) else {
                    throw LocalStoreError.sqlite("Could not read the newly created card")
                }
                card = inserted
            }
            try addCard(card.id, toList: listID)
            try Self.execute(database, "COMMIT")
            return card
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    public func cards(search: String = "", listID: Int64 = WordList.defaultID, limit: Int = 500) throws -> [PersonalCard] {
        let hasQuery = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let sql = """
            SELECT \(qualifiedCardColumns) FROM personal_cards AS c
            JOIN card_lists AS cl ON cl.card_id = c.id
            WHERE cl.list_id = ?
            \(hasQuery ? "AND (c.german LIKE ? ESCAPE '\\' OR c.english LIKE ? ESCAPE '\\' OR c.tags LIKE ? ESCAPE '\\')" : "")
            ORDER BY c.is_starred DESC, c.german COLLATE NOCASE
            LIMIT ?
            """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, listID)
        var index: Int32 = 2
        if hasQuery {
            let pattern = "%" + escapedLike(search) + "%"
            for _ in 0..<3 { bind(pattern, to: index, in: statement); index += 1 }
        }
        sqlite3_bind_int(statement, index, Int32(limit))
        return try readCards(statement)
    }

    public func dueCards(listID: Int64 = WordList.defaultID, limit: Int = 100, now: Date = .now) throws -> [PersonalCard] {
        let sql = """
            SELECT \(qualifiedCardColumns) FROM personal_cards AS c
            JOIN card_lists AS cl ON cl.card_id = c.id
            WHERE cl.list_id = ? AND c.is_suspended = 0 AND c.due_at <= ?
            ORDER BY c.due_at, c.repetitions
            LIMIT ?
            """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, listID)
        sqlite3_bind_double(statement, 2, now.timeIntervalSince1970)
        sqlite3_bind_int(statement, 3, Int32(limit))
        return try readCards(statement)
    }

    public func reviewCards(listID: Int64 = WordList.defaultID) throws -> [PersonalCard] {
        let sql = """
            SELECT \(qualifiedCardColumns) FROM personal_cards AS c
            JOIN card_lists AS cl ON cl.card_id = c.id
            WHERE cl.list_id = ? AND c.is_suspended = 0
            ORDER BY c.due_at, c.repetitions
            """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, listID)
        return try readCards(statement)
    }

    public func wordLists() throws -> [WordList] {
        let statement = try prepare("SELECT id, name, created_at FROM word_lists ORDER BY id = ? DESC, name COLLATE NOCASE")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, WordList.defaultID)
        var result: [WordList] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else { throw sqliteError() }
            result.append(.init(
                id: sqlite3_column_int64(statement, 0),
                name: text(statement, 1),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
            ))
        }
    }

    @discardableResult
    public func createWordList(name: String) throws -> WordList {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LocalStoreError.invalidListName }
        let statement = try prepare("INSERT INTO word_lists (name, created_at) VALUES (?, ?)")
        defer { sqlite3_finalize(statement) }
        bind(name, to: 1, in: statement)
        sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            if sqlite3_errcode(database) == SQLITE_CONSTRAINT { throw LocalStoreError.duplicateListName }
            throw sqliteError()
        }
        return .init(id: sqlite3_last_insert_rowid(database), name: name)
    }

    public func renameWordList(id: Int64, name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LocalStoreError.invalidListName }
        let statement = try prepare("UPDATE word_lists SET name = ? WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        bind(name, to: 1, in: statement)
        sqlite3_bind_int64(statement, 2, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            if sqlite3_errcode(database) == SQLITE_CONSTRAINT { throw LocalStoreError.duplicateListName }
            throw sqliteError()
        }
    }

    public func deleteWordList(id: Int64) throws {
        guard id != WordList.defaultID else { throw LocalStoreError.cannotDeleteDefaultList }
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            let statement = try prepare("DELETE FROM word_lists WHERE id = ?")
            sqlite3_bind_int64(statement, 1, id)
            let step = sqlite3_step(statement)
            sqlite3_finalize(statement)
            guard step == SQLITE_DONE else { throw sqliteError() }
            try Self.execute(database, "DELETE FROM personal_cards WHERE NOT EXISTS (SELECT 1 FROM card_lists WHERE card_lists.card_id = personal_cards.id)")
            try Self.execute(database, "COMMIT")
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    public func addCard(_ cardID: Int64, toList listID: Int64) throws {
        let statement = try prepare("INSERT OR IGNORE INTO card_lists (card_id, list_id, added_at) VALUES (?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, cardID)
        sqlite3_bind_int64(statement, 2, listID)
        sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
        try stepDone(statement)
    }

    public func removeCard(_ cardID: Int64, fromList listID: Int64) throws {
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            let statement = try prepare("DELETE FROM card_lists WHERE card_id = ? AND list_id = ?")
            sqlite3_bind_int64(statement, 1, cardID)
            sqlite3_bind_int64(statement, 2, listID)
            let step = sqlite3_step(statement)
            sqlite3_finalize(statement)
            guard step == SQLITE_DONE else { throw sqliteError() }

            let orphan = try prepare("SELECT NOT EXISTS (SELECT 1 FROM card_lists WHERE card_id = ?)")
            sqlite3_bind_int64(orphan, 1, cardID)
            let shouldDelete = try readScalarInt(orphan) != 0
            sqlite3_finalize(orphan)
            if shouldDelete { try deleteCard(id: cardID) }
            try Self.execute(database, "COMMIT")
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    public func review(card: PersonalCard, rating: ReviewRating, now: Date = .now) throws -> PersonalCard {
        let updated = SpacedRepetitionScheduler.reviewed(card, rating: rating, now: now)
        try updateCard(updated)
        let log = try prepare("INSERT INTO review_log (card_id, rating, reviewed_at, interval_days) VALUES (?, ?, ?, ?)")
        defer { sqlite3_finalize(log) }
        sqlite3_bind_int64(log, 1, card.id)
        sqlite3_bind_int(log, 2, Int32(rating.rawValue))
        sqlite3_bind_double(log, 3, now.timeIntervalSince1970)
        sqlite3_bind_double(log, 4, updated.intervalDays)
        try stepDone(log)
        return updated
    }

    public func updateCard(_ card: PersonalCard) throws {
        let sql = """
            UPDATE personal_cards SET
              german = ?, english = ?, raw_german = ?, kind = ?, gender = ?, notes = ?, tags = ?,
              due_at = ?, last_reviewed_at = ?, interval_days = ?, ease_factor = ?, repetitions = ?, lapses = ?,
              is_starred = ?, is_suspended = ?
            WHERE id = ?
            """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(card.german, to: 1, in: statement)
        bind(card.english, to: 2, in: statement)
        bind(card.rawGerman, to: 3, in: statement)
        bind(card.kind.rawValue, to: 4, in: statement)
        bind(card.gender.rawValue, to: 5, in: statement)
        bind(card.notes, to: 6, in: statement)
        bind(card.tags, to: 7, in: statement)
        sqlite3_bind_double(statement, 8, card.dueAt.timeIntervalSince1970)
        if let last = card.lastReviewedAt { sqlite3_bind_double(statement, 9, last.timeIntervalSince1970) }
        else { sqlite3_bind_null(statement, 9) }
        sqlite3_bind_double(statement, 10, card.intervalDays)
        sqlite3_bind_double(statement, 11, card.easeFactor)
        sqlite3_bind_int(statement, 12, Int32(card.repetitions))
        sqlite3_bind_int(statement, 13, Int32(card.lapses))
        sqlite3_bind_int(statement, 14, card.isStarred ? 1 : 0)
        sqlite3_bind_int(statement, 15, card.isSuspended ? 1 : 0)
        sqlite3_bind_int64(statement, 16, card.id)
        try stepDone(statement)
    }

    public func deleteCard(id: Int64) throws {
        let statement = try prepare("DELETE FROM personal_cards WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        try stepDone(statement)
    }

    public func stats(listID: Int64 = WordList.defaultID, now: Date = .now, calendar: Calendar = .current) throws -> StudyStats {
        let totalStatement = try prepare("SELECT COUNT(*) FROM card_lists WHERE list_id = ?")
        defer { sqlite3_finalize(totalStatement) }
        sqlite3_bind_int64(totalStatement, 1, listID)
        let total = try readScalarInt(totalStatement)
        let dueStatement = try prepare("SELECT COUNT(*) FROM personal_cards AS c JOIN card_lists AS cl ON cl.card_id = c.id WHERE cl.list_id = ? AND c.is_suspended = 0 AND c.due_at <= ?")
        defer { sqlite3_finalize(dueStatement) }
        sqlite3_bind_int64(dueStatement, 1, listID)
        sqlite3_bind_double(dueStatement, 2, now.timeIntervalSince1970)
        let due = try readScalarInt(dueStatement)
        let start = calendar.startOfDay(for: now).timeIntervalSince1970
        let reviewsStatement = try prepare("SELECT COUNT(*) FROM review_log AS r JOIN card_lists AS cl ON cl.card_id = r.card_id WHERE cl.list_id = ? AND r.reviewed_at >= ?")
        defer { sqlite3_finalize(reviewsStatement) }
        sqlite3_bind_int64(reviewsStatement, 1, listID)
        sqlite3_bind_double(reviewsStatement, 2, start)
        let reviews = try readScalarInt(reviewsStatement)
        let dayStatement = try prepare("SELECT DISTINCT CAST(r.reviewed_at / 86400 AS INTEGER) FROM review_log AS r JOIN card_lists AS cl ON cl.card_id = r.card_id WHERE cl.list_id = ? ORDER BY 1 DESC")
        defer { sqlite3_finalize(dayStatement) }
        sqlite3_bind_int64(dayStatement, 1, listID)
        var reviewDays = Set<Int>()
        while sqlite3_step(dayStatement) == SQLITE_ROW { reviewDays.insert(Int(sqlite3_column_int64(dayStatement, 0))) }
        var streak = 0
        var day = Int(now.timeIntervalSince1970 / 86_400)
        while reviewDays.contains(day) { streak += 1; day -= 1 }
        return .init(totalCards: total, dueCards: due, reviewsToday: reviews, streakDays: streak)
    }

    private static func configure(_ database: OpaquePointer) throws {
        try execute(database, "PRAGMA journal_mode = WAL")
        try execute(database, "PRAGMA synchronous = NORMAL")
        try execute(database, "PRAGMA foreign_keys = ON")
        try execute(database, "PRAGMA temp_store = MEMORY")
        try execute(database, """
            CREATE TABLE IF NOT EXISTS dictionary_entries (
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
            CREATE INDEX IF NOT EXISTS dictionary_source ON dictionary_entries(source);
            CREATE INDEX IF NOT EXISTS dictionary_word_kind ON dictionary_entries(normalized_german, kind);
            CREATE VIRTUAL TABLE IF NOT EXISTS dictionary_fts USING fts5(
              german, english, content='dictionary_entries', content_rowid='id',
              tokenize='unicode61 remove_diacritics 2'
            );
            CREATE TABLE IF NOT EXISTS personal_cards (
              id INTEGER PRIMARY KEY,
              dictionary_entry_id INTEGER UNIQUE REFERENCES dictionary_entries(id) ON DELETE SET NULL,
              german TEXT NOT NULL,
              english TEXT NOT NULL,
              raw_german TEXT NOT NULL,
              kind TEXT NOT NULL,
              gender TEXT NOT NULL,
              notes TEXT NOT NULL DEFAULT '',
              tags TEXT NOT NULL DEFAULT '',
              created_at REAL NOT NULL,
              due_at REAL NOT NULL,
              last_reviewed_at REAL,
              interval_days REAL NOT NULL DEFAULT 0,
              ease_factor REAL NOT NULL DEFAULT 2.5,
              repetitions INTEGER NOT NULL DEFAULT 0,
              lapses INTEGER NOT NULL DEFAULT 0,
              is_starred INTEGER NOT NULL DEFAULT 0,
              is_suspended INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS cards_due ON personal_cards(is_suspended, due_at);
            CREATE TABLE IF NOT EXISTS word_lists (
              id INTEGER PRIMARY KEY,
              name TEXT NOT NULL COLLATE NOCASE UNIQUE,
              created_at REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS card_lists (
              card_id INTEGER NOT NULL REFERENCES personal_cards(id) ON DELETE CASCADE,
              list_id INTEGER NOT NULL REFERENCES word_lists(id) ON DELETE CASCADE,
              added_at REAL NOT NULL,
              PRIMARY KEY (card_id, list_id)
            );
            CREATE INDEX IF NOT EXISTS card_lists_by_list ON card_lists(list_id, card_id);
            CREATE TABLE IF NOT EXISTS review_log (
              id INTEGER PRIMARY KEY,
              card_id INTEGER NOT NULL REFERENCES personal_cards(id) ON DELETE CASCADE,
              rating INTEGER NOT NULL,
              reviewed_at REAL NOT NULL,
              interval_days REAL NOT NULL
            );
            """)
        let defaultName = "My words".replacingOccurrences(of: "'", with: "''")
        try execute(database, "INSERT OR IGNORE INTO word_lists (id, name, created_at) VALUES (\(WordList.defaultID), '\(defaultName)', strftime('%s', 'now'))")
        try execute(database, "INSERT OR IGNORE INTO card_lists (card_id, list_id, added_at) SELECT id, \(WordList.defaultID), created_at FROM personal_cards WHERE NOT EXISTS (SELECT 1 FROM card_lists)")
        try createDictionaryTriggers(database)
    }

    private func insertDictionaryEntry(_ entry: DictionaryEntry) throws {
        let statement = try prepare(dictionaryInsertSQL)
        defer { sqlite3_finalize(statement) }
        try insertDictionaryEntry(entry, using: statement)
    }

    private func insertDictionaryEntry(_ entry: DictionaryEntry, using statement: OpaquePointer?) throws {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        bind(entry.german.replacingOccurrences(of: "|", with: ""), to: 1, in: statement)
        bind(entry.english, to: 2, in: statement)
        bind(DictCCParser.normalized(entry.german), to: 3, in: statement)
        bind(DictCCParser.normalized(entry.english), to: 4, in: statement)
        bind(entry.rawGerman, to: 5, in: statement)
        bind(entry.rawEnglish, to: 6, in: statement)
        bind(entry.kind.rawValue, to: 7, in: statement)
        bind(entry.gender.rawValue, to: 8, in: statement)
        if let usage = entry.usage { bind(usage, to: 9, in: statement) } else { sqlite3_bind_null(statement, 9) }
        bind(entry.source, to: 10, in: statement)
        try stepDone(statement)
    }

    private var dictionaryInsertSQL: String {
        """
        INSERT OR IGNORE INTO dictionary_entries
          (german, english, normalized_german, normalized_english, raw_german, raw_english, kind, gender, usage, source)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
    }

    private func card(id: Int64) throws -> PersonalCard? {
        let statement = try prepare("SELECT \(cardColumns) FROM personal_cards WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        return try readCards(statement).first
    }

    private func card(forDictionaryEntryID id: Int64) throws -> PersonalCard? {
        let statement = try prepare("SELECT \(cardColumns) FROM personal_cards WHERE dictionary_entry_id = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        return try readCards(statement).first
    }

    private var cardColumns: String {
        "id, dictionary_entry_id, german, english, raw_german, kind, gender, notes, tags, created_at, due_at, last_reviewed_at, interval_days, ease_factor, repetitions, lapses, is_starred, is_suspended"
    }

    private var qualifiedCardColumns: String {
        "c.id, c.dictionary_entry_id, c.german, c.english, c.raw_german, c.kind, c.gender, c.notes, c.tags, c.created_at, c.due_at, c.last_reviewed_at, c.interval_days, c.ease_factor, c.repetitions, c.lapses, c.is_starred, c.is_suspended"
    }

    private func readEntries(_ statement: OpaquePointer?) throws -> [DictionaryEntry] {
        var result: [DictionaryEntry] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else { throw sqliteError() }
            result.append(.init(
                id: sqlite3_column_int64(statement, 0),
                german: text(statement, 1),
                english: text(statement, 2),
                rawGerman: text(statement, 3),
                rawEnglish: text(statement, 4),
                kind: WordKind(rawValue: text(statement, 5)) ?? .other,
                gender: Gender(rawValue: text(statement, 6)) ?? .unknown,
                usage: nullableText(statement, 7),
                source: text(statement, 8)
            ))
        }
    }

    private func dictionaryGroup(representedBy representative: DictionaryEntry) throws -> DictionaryEntry {
        let sql = """
            SELECT id, german, english, raw_german, raw_english,
                   kind, gender, usage, source
            FROM dictionary_entries
            WHERE normalized_german = ? AND kind = ?
            ORDER BY id
            """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(DictCCParser.normalized(representative.german), to: 1, in: statement)
        bind(representative.kind.rawValue, to: 2, in: statement)
        let groupTerm = dictionaryGroupingTerm(representative.german)
        let entries = try readEntries(statement).filter {
            dictionaryGroupingTerm($0.german) == groupTerm
        }
        guard let canonical = entries.first else { return representative }

        var seenMeanings = Set<String>()
        let meanings = entries.compactMap { entry -> DictionaryMeaning? in
            let meaning = DictionaryMeaning(
                english: entry.english,
                rawEnglish: entry.rawEnglish,
                gender: entry.gender,
                usage: entry.usage
            )
            return seenMeanings.insert(meaning.id).inserted ? meaning : nil
        }
        let genders = Set(entries.map(\.gender))
        let usages = Set(entries.map(\.usage))
        let sources = entries.map(\.source).reduce(into: [String]()) { result, source in
            if !result.contains(source) { result.append(source) }
        }

        return DictionaryEntry(
            id: canonical.id,
            german: canonical.german,
            english: canonical.english,
            rawGerman: canonical.rawGerman,
            rawEnglish: canonical.rawEnglish,
            kind: canonical.kind,
            gender: genders.count == 1 ? canonical.gender : .unknown,
            usage: usages.count == 1 ? canonical.usage : nil,
            source: sources.joined(separator: ", "),
            meanings: meanings
        )
    }

    private func readCards(_ statement: OpaquePointer?) throws -> [PersonalCard] {
        var result: [PersonalCard] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else { throw sqliteError() }
            let dictionaryID = sqlite3_column_type(statement, 1) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 1)
            let lastReviewed = sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 11))
            result.append(.init(
                id: sqlite3_column_int64(statement, 0),
                dictionaryEntryID: dictionaryID,
                german: text(statement, 2),
                english: text(statement, 3),
                kind: WordKind(rawValue: text(statement, 5)) ?? .other,
                gender: Gender(rawValue: text(statement, 6)) ?? .unknown,
                rawGerman: text(statement, 4),
                notes: text(statement, 7),
                tags: text(statement, 8),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
                dueAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10)),
                lastReviewedAt: lastReviewed,
                intervalDays: sqlite3_column_double(statement, 12),
                easeFactor: sqlite3_column_double(statement, 13),
                repetitions: Int(sqlite3_column_int(statement, 14)),
                lapses: Int(sqlite3_column_int(statement, 15)),
                isStarred: sqlite3_column_int(statement, 16) != 0,
                isSuspended: sqlite3_column_int(statement, 17) != 0
            ))
        }
    }

    private func scalarInt(_ sql: String) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        return try readScalarInt(statement)
    }

    private func readScalarInt(_ statement: OpaquePointer?) throws -> Int {
        guard sqlite3_step(statement) == SQLITE_ROW else { throw sqliteError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw sqliteError() }
        return statement
    }

    private func bind(_ value: String, to index: Int32, in statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, value, -1, Self.transient)
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw sqliteError() }
    }

    private func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private func nullableText(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return text(statement, column)
    }

    private func escapedLike(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private func detectGermanFirst(in handle: FileHandle) throws -> Bool {
        guard let sample = try handle.read(upToCount: 4_194_304),
              let text = String(data: sample, encoding: .utf8) else { return true }
        var firstColumnTags = 0
        var secondColumnTags = 0
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 2 else { continue }
            firstColumnTags += germanGrammarTagCount(in: columns[0])
            secondColumnTags += germanGrammarTagCount(in: columns[1])
        }
        return firstColumnTags >= secondColumnTags
    }

    private func germanGrammarTagCount(in value: Substring) -> Int {
        let tags = ["{m}", "{f}", "{n}", "{pl}", "{vi}", "{vt}", "{vr}"]
        return tags.reduce(into: 0) { count, tag in
            if value.contains(tag) { count += 1 }
        }
    }

    private func sqliteError() -> LocalStoreError {
        .sqlite(database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error")
    }

    private static func execute(_ database: OpaquePointer?, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(error)
            throw LocalStoreError.sqlite(message)
        }
    }

    private static func createDictionaryTriggers(_ database: OpaquePointer?) throws {
        try execute(database, """
            CREATE TRIGGER IF NOT EXISTS dictionary_ai AFTER INSERT ON dictionary_entries BEGIN
              INSERT INTO dictionary_fts(rowid, german, english) VALUES (new.id, new.normalized_german, new.normalized_english);
            END;
            CREATE TRIGGER IF NOT EXISTS dictionary_ad AFTER DELETE ON dictionary_entries BEGIN
              INSERT INTO dictionary_fts(dictionary_fts, rowid, german, english) VALUES ('delete', old.id, old.normalized_german, old.normalized_english);
            END;
            CREATE TRIGGER IF NOT EXISTS dictionary_au AFTER UPDATE ON dictionary_entries BEGIN
              INSERT INTO dictionary_fts(dictionary_fts, rowid, german, english) VALUES ('delete', old.id, old.normalized_german, old.normalized_english);
              INSERT INTO dictionary_fts(rowid, german, english) VALUES (new.id, new.normalized_german, new.normalized_english);
            END;
            """)
    }
}

private struct DictionaryGroupKey: Hashable {
    let german: String
    let kind: WordKind

    init(_ entry: DictionaryEntry) {
        german = dictionaryGroupingTerm(entry.german)
        kind = entry.kind
    }
}

private func dictionaryGroupingTerm(_ value: String) -> String {
    value
        .precomposedStringWithCanonicalMapping
        .lowercased(with: Locale(identifier: "de_DE"))
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
