import SQLite3

enum LocalStoreSchema {
    static let latestSchemaVersion = 1

    static func configure(_ database: OpaquePointer) throws {
        let installedVersion = try schemaVersion(in: database)
        guard installedVersion <= latestSchemaVersion else {
            throw LocalStoreError.unsupportedSchema(found: installedVersion, latest: latestSchemaVersion)
        }
        try execute(database, "PRAGMA journal_mode = WAL")
        try execute(database, "PRAGMA synchronous = NORMAL")
        try execute(database, "PRAGMA foreign_keys = ON")
        try execute(database, "PRAGMA temp_store = MEMORY")
        guard installedVersion < latestSchemaVersion else { return }

        try execute(database, "BEGIN IMMEDIATE")
        do {
            var migratedVersion = installedVersion
            // Released migration bodies are immutable. Add each future migration in
            // a new ordered `if migratedVersion < N` block and test data preservation.
            if migratedVersion < 1 {
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
                      translation_language TEXT NOT NULL DEFAULT 'en',
                      explanation TEXT,
                      UNIQUE(raw_german, raw_english, translation_language)
                    );
                    CREATE INDEX IF NOT EXISTS dictionary_source ON dictionary_entries(source);
                    CREATE INDEX IF NOT EXISTS dictionary_word_kind ON dictionary_entries(normalized_german, kind);
                    CREATE TABLE IF NOT EXISTS dictionary_explanations (
                      id INTEGER PRIMARY KEY,
                      german_key TEXT NOT NULL,
                      kind TEXT NOT NULL,
                      explanation TEXT NOT NULL,
                      source TEXT NOT NULL,
                      sort_order INTEGER NOT NULL DEFAULT 0,
                      UNIQUE(german_key, kind, explanation, source)
                    );
                    CREATE INDEX IF NOT EXISTS dictionary_explanations_word_kind
                      ON dictionary_explanations(german_key, kind, sort_order);
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
                    CREATE TABLE IF NOT EXISTS saved_sentences (
                      id INTEGER PRIMARY KEY,
                      german TEXT NOT NULL,
                      translation TEXT NOT NULL,
                      source_list_id INTEGER REFERENCES word_lists(id) ON DELETE SET NULL,
                      source_list_name TEXT NOT NULL,
                      tokens_json TEXT NOT NULL,
                      created_at REAL NOT NULL,
                      UNIQUE(german, translation)
                    );
                    CREATE INDEX IF NOT EXISTS saved_sentences_created ON saved_sentences(created_at DESC);
                    """)
                if try !table("dictionary_entries", hasColumn: "translation_language", in: database) {
                    try execute(database, "ALTER TABLE dictionary_entries ADD COLUMN translation_language TEXT NOT NULL DEFAULT 'en'")
                }
                if try !table("dictionary_entries", hasColumn: "explanation", in: database) {
                    try execute(database, "ALTER TABLE dictionary_entries ADD COLUMN explanation TEXT")
                }
                try execute(database, "CREATE INDEX IF NOT EXISTS dictionary_source_language ON dictionary_entries(source, translation_language)")
                try execute(database, "INSERT OR IGNORE INTO word_lists (id, name, created_at) VALUES (\(WordList.defaultID), 'My words', strftime('%s', 'now'))")
                try execute(database, "INSERT OR IGNORE INTO card_lists (card_id, list_id, added_at) SELECT id, \(WordList.defaultID), created_at FROM personal_cards WHERE NOT EXISTS (SELECT 1 FROM card_lists)")
                try createDictionaryTriggers(database)
                migratedVersion = 1
            }
            guard migratedVersion == latestSchemaVersion else {
                throw LocalStoreError.sqlite("Missing migration to schema version \(latestSchemaVersion)")
            }
            try execute(database, "PRAGMA user_version = \(migratedVersion)")
            try execute(database, "COMMIT")
        } catch {
            try? execute(database, "ROLLBACK")
            throw error
        }
    }

    static func createDictionaryTriggers(_ database: OpaquePointer?) throws {
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

    private static func table(_ table: String, hasColumn column: String, in database: OpaquePointer?) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError(database)
        }
        defer { sqlite3_finalize(statement) }
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return false }
            guard step == SQLITE_ROW else { throw sqliteError(database) }
            guard let value = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: value) == column { return true }
        }
    }

    private static func schemaVersion(in database: OpaquePointer?) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError(database)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw LocalStoreError.sqlite("Could not read the database schema version")
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private static func execute(_ database: OpaquePointer?, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(error)
            throw LocalStoreError.sqlite(message)
        }
    }

    private static func sqliteError(_ database: OpaquePointer?) -> LocalStoreError {
        .sqlite(database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error")
    }
}
