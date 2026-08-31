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

public struct ExplanationImportProgress: Sendable, Equatable {
    public let imported: Int
    public let total: Int

    public init(imported: Int, total: Int) {
        self.imported = imported
        self.total = total
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(imported) / Double(total))
    }
}

public enum LocalStoreError: LocalizedError {
    case open(String)
    case sqlite(String)
    case invalidDictionaryFile
    case invalidListName
    case duplicateListName
    case cannotDeleteDefaultList
    case invalidExplanationDatabase
    case unsupportedSchema(found: Int, latest: Int)

    public var errorDescription: String? {
        switch self {
        case .open(let message): "Could not open the local database: \(message)"
        case .sqlite(let message): "Local database error: \(message)"
        case .invalidDictionaryFile: "This does not look like a tab-delimited dict.cc translation file."
        case .invalidListName: "List names cannot be empty."
        case .duplicateListName: "A list with that name already exists."
        case .cannotDeleteDefaultList: "The My words list cannot be deleted."
        case .invalidExplanationDatabase: "This is not a supported Lector German dictionary database."
        case .unsupportedSchema(let found, let latest):
            "This database uses schema version \(found), but this app supports up to version \(latest)."
        }
    }
}

public actor LocalStore {
    static let latestSchemaVersion = LocalStoreSchema.latestSchemaVersion

    private var database: OpaquePointer?
    private var dictionaryClassifications: [String: DictionaryClassification] = [:]
    public nonisolated let databaseURL: URL
    private let now: @Sendable () -> Date
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(
        url: URL? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) throws {
        self.now = now
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
            try LocalStoreSchema.configure(pointer)
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
        try scalarInt("SELECT COUNT(*) FROM dictionary_entries WHERE source = 'dict.cc' AND translation_language = 'en'") > 100_000
    }

    public func installedTranslationLanguages() throws -> Set<TranslationLanguage> {
        let statement = try prepare("SELECT DISTINCT translation_language FROM dictionary_entries WHERE source = 'dict.cc'")
        defer { sqlite3_finalize(statement) }
        var result = Set<TranslationLanguage>()
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else { throw sqliteError() }
            if let language = TranslationLanguage(rawValue: text(statement, 0)) {
                result.insert(language)
            }
        }
    }

    public func explanationCount() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM dictionary_explanations")
    }

    public func seedStarterDictionaryIfNeeded() throws {
        guard try dictionaryCount() == 0 else { return }
        let starter = [
            "Haus {n}\thouse", "Frau {f}\twoman", "Mann {m}\tman", "Kind {n}\tchild",
            "Hund {m}\tdog", "Hunde {pl}\tdogs",
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
        var lookupTerms = GermanMorphology.lookupTerms(for: query)
        guard !lookupTerms.isEmpty, limit > 0 else { return [] }
        let inflectionLinks = try dictionaryInflectionSearchLinks(for: query)
        for link in inflectionLinks where !lookupTerms.contains(link.searchTerm) {
            lookupTerms.append(link.searchTerm)
        }
        var hitsByGroup: [DictionaryGroupKey: DictionarySearchHit] = [:]
        var ordinal = 0
        for (termIndex, term) in lookupTerms.prefix(16).enumerated() {
            for storedEntry in try dictionaryMatches(for: term, limit: limit) {
                let entry = try resolvedDictionaryEntry(storedEntry)
                guard shouldInclude(
                    entry,
                    storedKind: dictionaryEvidenceKind(for: storedEntry),
                    literalTerm: lookupTerms[0],
                    inflectionLinks: inflectionLinks
                ) else { continue }
                let key = DictionaryGroupKey(entry)
                let classification = try dictionaryClassification(for: entry.german)
                let hit = DictionarySearchHit(
                    entry: entry,
                    preference: searchPreference(
                        for: entry,
                        storedKind: dictionaryEvidenceKind(for: storedEntry),
                        hasDirectKindEvidence: classification.hasDirectKindEvidence,
                        literalTerm: lookupTerms[0],
                        lookupTerms: lookupTerms,
                        inflectionLinks: inflectionLinks
                    ),
                    groupSize: classification.groupSize(for: entry),
                    termIndex: termIndex,
                    ordinal: ordinal
                )
                ordinal += 1
                if let existing = hitsByGroup[key], existing.sortsBefore(hit) { continue }
                hitsByGroup[key] = hit
            }
        }

        var seenGroups = Set<DictionaryGroupKey>()
        var groups: [DictionaryEntry] = []
        for hit in hitsByGroup.values.sorted(by: { $0.sortsBefore($1) }) {
            for group in try dictionaryGroups(representedBy: hit.entry) {
                guard seenGroups.insert(DictionaryGroupKey(group)).inserted else { continue }
                groups.append(group)
                if groups.count == limit { return groups }
            }
        }
        return groups
    }

    public func dictionaryEntry(id: DictionaryEntry.ID) throws -> DictionaryEntry? {
        let statement = try prepare("""
            SELECT id, german, english, raw_german, raw_english,
                   kind, gender, usage, source, translation_language,
                   explanation, grammar, subject
            FROM dictionary_entries
            WHERE id = ?
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        guard let representative = try readEntries(statement).first else { return nil }
        let groups = try dictionaryGroups(representedBy: representative)
        return groups.first(where: { $0.id == id }) ?? groups.first
    }

    private func dictionaryInflectionSearchLinks(
        for query: String
    ) throws -> [DictionaryInflectionSearchLink] {
        let queryForm = dictionaryGroupingTerm(
            DictCCParser.cleanedTerm(query).replacingOccurrences(of: "|", with: "")
        )
        guard !queryForm.isEmpty else { return [] }
        var forms = [queryForm]
        let words = queryForm.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.count == 2, words[0] == "am" {
            forms.append(words[1])
        }

        let statement = try prepare("""
            SELECT DISTINCT lemma_key, kind, tags
            FROM dictionary_inflections
            WHERE form = ? AND tags != 'auxiliary'
            ORDER BY lemma_key, kind, tags
            """)
        defer { sqlite3_finalize(statement) }
        var result: [DictionaryInflectionSearchLink] = []
        for form in forms {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bind(form, to: 1, in: statement)
            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW else { throw sqliteError() }
                let kind = WordKind(rawValue: text(statement, 1)) ?? .other
                let lemmaKey = text(statement, 0)
                let link = DictionaryInflectionSearchLink(
                    lemmaKey: lemmaKey,
                    searchTerm: DictCCParser.normalized(lemmaKey),
                    kind: kind,
                    tags: lectorTags(text(statement, 2))
                )
                if !link.searchTerm.isEmpty, !result.contains(link) {
                    result.append(link)
                }
            }
        }
        return result
    }

    private func dictionaryMatches(for normalized: String, limit: Int) throws -> [DictionaryEntry] {
        let tokens = normalized
            .split(whereSeparator: { $0.isWhitespace })
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }
            .joined(separator: " ")
        let sql = """
            SELECT d.id, d.german, d.english, d.raw_german, d.raw_english,
                   d.kind, d.gender, d.usage, d.source, d.translation_language,
                   d.explanation, d.grammar, d.subject
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
        return try readEntries(statement)
    }

    private func searchPreference(
        for entry: DictionaryEntry,
        storedKind: WordKind,
        hasDirectKindEvidence: Bool,
        literalTerm: String,
        lookupTerms: [String],
        inflectionLinks: [DictionaryInflectionSearchLink]
    ) -> Int {
        let german = DictCCParser.normalized(entry.german)
        let groupingTerm = dictionaryGroupingTerm(entry.german)
        if german == literalTerm,
           entry.gender != .plural,
           !inflectionLinks.contains(where: \.isDegree),
           storedKind != .other || hasDirectKindEvidence {
            return -2
        }
        if inflectionLinks.contains(where: {
            $0.lemmaKey == groupingTerm && $0.kind == entry.kind
        }) {
            return -1
        }
        guard let exactIndex = lookupTerms.firstIndex(of: german) else { return 10 }
        let isSingularNoun = entry.kind == .noun
            && entry.gender != .plural
            && entry.gender != .unknown
        if exactIndex > 0, entry.kind == .verb { return 0 }
        if exactIndex > 0, isSingularNoun { return 1 }
        if german == literalTerm, entry.gender != .plural {
            return entry.kind == .other ? 2 : 0
        }
        if entry.kind == .verb || isSingularNoun { return 2 }
        if german == literalTerm { return 3 }
        return 4
    }

    private func shouldInclude(
        _ entry: DictionaryEntry,
        storedKind: WordKind,
        literalTerm: String,
        inflectionLinks: [DictionaryInflectionSearchLink]
    ) -> Bool {
        let groupingTerm = dictionaryGroupingTerm(entry.german)
        let literalGroupingTerm = dictionaryGroupingTerm(literalTerm)
        if storedKind == .other,
           groupingTerm == literalGroupingTerm,
           inflectionLinks.contains(where: {
               $0.lemmaKey != literalGroupingTerm && $0.kind == entry.kind
           }) {
            return false
        }
        return true
    }

    private func resolvedDictionaryEntry(_ entry: DictionaryEntry) throws -> DictionaryEntry {
        let classification = try dictionaryClassification(for: entry.german)
        let evidenceKind = dictionaryEvidenceKind(for: entry)
        let resolvedKind: WordKind
        if evidenceKind == .other, let preferredKind = classification.preferredKind {
            if preferredKind == .noun, classification.nounGender == nil {
                resolvedKind = .other
            } else {
                resolvedKind = preferredKind
            }
        } else if evidenceKind == .adverb, classification.preferredKind == .adjective {
            // German adjective forms are also used adverbially without changing
            // spelling. They are one study lexeme, not duplicate cards.
            resolvedKind = .adjective
        } else {
            resolvedKind = evidenceKind
        }
        let resolvedGender = resolvedKind == .noun && entry.gender == .unknown
            ? classification.nounGender ?? .unknown
            : entry.gender
        guard resolvedKind != entry.kind || resolvedGender != entry.gender else { return entry }
        return entry.reclassified(kind: resolvedKind, gender: resolvedGender)
    }

    private func dictionaryClassification(for german: String) throws -> DictionaryClassification {
        let groupingTerm = dictionaryGroupingTerm(german)
        if let cached = dictionaryClassifications[groupingTerm] { return cached }

        let spellings = dictionaryGroupingSpellings(for: groupingTerm)
        let placeholders = Array(repeating: "?", count: spellings.count).joined(separator: ", ")
        let entryStatement = try prepare("""
            SELECT german, kind, gender, raw_german, raw_english, grammar, translation_language
            FROM dictionary_entries
            WHERE normalized_german IN (\(placeholders))
            """)
        defer { sqlite3_finalize(entryStatement) }
        for (offset, spelling) in spellings.enumerated() {
            bind(DictCCParser.normalized(spelling), to: Int32(offset + 1), in: entryStatement)
        }
        var directKindCounts: [WordKind: Int] = [:]
        var nounGenderCounts: [Gender: Int] = [:]
        while true {
            let step = sqlite3_step(entryStatement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw sqliteError() }
            guard dictionaryGroupingTerm(text(entryStatement, 0)) == groupingTerm,
                  let storedKind = WordKind(rawValue: text(entryStatement, 1)) else { continue }
            let kind = dictionaryEvidenceKind(
                storedKind: storedKind,
                rawGerman: text(entryStatement, 3),
                rawEnglish: text(entryStatement, 4),
                grammar: nullableText(entryStatement, 5),
                language: TranslationLanguage(rawValue: text(entryStatement, 6)) ?? .english
            )
            guard kind != .other, kind != .phrase else { continue }
            directKindCounts[kind, default: 0] += 1
            if kind == .noun,
               let gender = Gender(rawValue: text(entryStatement, 2)),
               gender != .unknown, gender != .plural {
                nounGenderCounts[gender, default: 0] += 1
            }
        }

        let lectorStatement = try prepare("""
            SELECT kind, COUNT(*)
            FROM dictionary_explanations
            WHERE german_key = ? AND kind != 'other'
            GROUP BY kind
            """)
        defer { sqlite3_finalize(lectorStatement) }
        bind(groupingTerm, to: 1, in: lectorStatement)
        var lectorKindCounts: [WordKind: Int] = [:]
        while true {
            let step = sqlite3_step(lectorStatement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw sqliteError() }
            guard let kind = WordKind(rawValue: text(lectorStatement, 0)), kind != .phrase else { continue }
            lectorKindCounts[kind] = Int(sqlite3_column_int64(lectorStatement, 1))
        }

        let classification = DictionaryClassification(
            directKindCounts: directKindCounts,
            lectorKindCounts: lectorKindCounts,
            nounGenderCounts: nounGenderCounts
        )
        if dictionaryClassifications.count >= 20_000 {
            dictionaryClassifications.removeAll(keepingCapacity: true)
        }
        dictionaryClassifications[groupingTerm] = classification
        return classification
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
        let format = try detectDictionaryFormat(in: handle)
        try handle.seek(toOffset: 0)

        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            let deleteStatement = try prepare("DELETE FROM dictionary_entries WHERE source = 'dict.cc' AND translation_language = ?")
            bind(format.language.rawValue, to: 1, in: deleteStatement)
            let deleteStep = sqlite3_step(deleteStatement)
            sqlite3_finalize(deleteStatement)
            guard deleteStep == SQLITE_DONE else { throw sqliteError() }
            // Building FTS once after the bulk insert is substantially faster than
            // updating its index more than a million times through the trigger.
            try Self.execute(database, "DROP TRIGGER IF EXISTS dictionary_ai; DROP TRIGGER IF EXISTS dictionary_ad; DROP TRIGGER IF EXISTS dictionary_au;")
            let insertStatement = try prepare(dictionaryImportSQL)
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
                    if let line = String(data: lineData, encoding: .utf8),
                       let entry = DictCCParser.parse(
                           line: line,
                           germanFirst: format.germanFirst,
                           translationLanguage: format.language
                       ) {
                        validLines += 1
                        try insertDictionaryEntry(entry, using: insertStatement)
                        imported += 1
                    }
                }
                if imported % 10_000 < 1_000 {
                    progress(.init(imported: imported, bytesRead: bytesRead, totalBytes: totalBytes))
                }
            }
            if !buffer.isEmpty,
               let line = String(data: buffer, encoding: .utf8),
               let entry = DictCCParser.parse(
                   line: line,
                   germanFirst: format.germanFirst,
                   translationLanguage: format.language
               ) {
                validLines += 1
                try insertDictionaryEntry(entry, using: insertStatement)
                imported += 1
            }
            guard validLines > 0 else { throw LocalStoreError.invalidDictionaryFile }
            try LocalStoreSchema.rebuildDictionarySearchIndex(database)
            try LocalStoreSchema.createDictionaryTriggers(database)
            try Self.execute(database, "COMMIT")
            dictionaryClassifications.removeAll(keepingCapacity: true)
            try Self.execute(database, "PRAGMA optimize")
            progress(.init(imported: imported, bytesRead: totalBytes, totalBytes: totalBytes))
            return imported
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    @discardableResult
    public func importExplanations(
        from url: URL,
        progress: @escaping @Sendable (ExplanationImportProgress) -> Void = { _ in }
    ) throws -> Int {
        var sourceDatabase: OpaquePointer?
        let separator = url.absoluteString.contains("?") ? "&" : "?"
        let sourceURI = url.absoluteString + separator + "immutable=1"
        let openResult = sqlite3_open_v2(
            sourceURI,
            &sourceDatabase,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let sourceDatabase else {
            sqlite3_close(sourceDatabase)
            throw LocalStoreError.invalidExplanationDatabase
        }
        defer { sqlite3_close(sourceDatabase) }

        var countStatement: OpaquePointer?
        guard sqlite3_prepare_v2(sourceDatabase, "SELECT COUNT(*) FROM senses", -1, &countStatement, nil) == SQLITE_OK else {
            throw LocalStoreError.invalidExplanationDatabase
        }
        defer { sqlite3_finalize(countStatement) }
        guard sqlite3_step(countStatement) == SQLITE_ROW else {
            throw LocalStoreError.invalidExplanationDatabase
        }
        let total = Int(sqlite3_column_int64(countStatement, 0))

        let sourceSQL = """
            SELECT s.word, s.pos, s.gloss, s.sort_order
            FROM senses AS s
            JOIN entries AS e ON e.word = s.word
            ORDER BY s.word, s.sort_order, s.id
            """
        var sourceStatement: OpaquePointer?
        guard sqlite3_prepare_v2(sourceDatabase, sourceSQL, -1, &sourceStatement, nil) == SQLITE_OK else {
            throw LocalStoreError.invalidExplanationDatabase
        }
        defer { sqlite3_finalize(sourceStatement) }

        var sourceInflectionStatement: OpaquePointer?
        if try Self.sourceTableExists("inflections", in: sourceDatabase) {
            let inflectionSQL = """
                SELECT i.inflected_form, i.lemma, i.type, coalesce(k.parts_of_speech, '')
                FROM inflections AS i
                LEFT JOIN (
                  SELECT word, group_concat(DISTINCT lower(pos)) AS parts_of_speech
                  FROM senses
                  WHERE pos IS NOT NULL AND trim(pos) != ''
                  GROUP BY word
                ) AS k ON k.word = i.lemma
                WHERE i.type IS NOT NULL AND trim(i.type) != ''
                  AND instr(',' || i.type || ',', ',inflection-template,') = 0
                  AND instr(',' || i.type || ',', ',table-tags,') = 0
                ORDER BY i.lemma, i.type, i.inflected_form
                """
            guard sqlite3_prepare_v2(
                sourceDatabase,
                inflectionSQL,
                -1,
                &sourceInflectionStatement,
                nil
            ) == SQLITE_OK else {
                throw LocalStoreError.invalidExplanationDatabase
            }
        }
        defer { sqlite3_finalize(sourceInflectionStatement) }

        var sourceReferenceStatement: OpaquePointer?
        if try Self.sourceTableExists("entries", in: sourceDatabase) {
            let hasIPA = try Self.sourceTable("entries", hasColumn: "ipa", in: sourceDatabase)
            let hasEtymology = try Self.sourceTable("entries", hasColumn: "etymology", in: sourceDatabase)
            let referenceSQL = """
                SELECT word, \(hasIPA ? "ipa" : "NULL"), \(hasEtymology ? "etymology" : "NULL")
                FROM entries
                ORDER BY word
                """
            guard sqlite3_prepare_v2(
                sourceDatabase,
                referenceSQL,
                -1,
                &sourceReferenceStatement,
                nil
            ) == SQLITE_OK else {
                throw LocalStoreError.invalidExplanationDatabase
            }
        }
        defer { sqlite3_finalize(sourceReferenceStatement) }

        var sourceRelatedStatement: OpaquePointer?
        if try Self.sourceTableExists("related_forms", in: sourceDatabase) {
            let relatedSQL = """
                SELECT word, related_word, relation
                FROM related_forms
                ORDER BY word, relation, related_word
                """
            guard sqlite3_prepare_v2(
                sourceDatabase,
                relatedSQL,
                -1,
                &sourceRelatedStatement,
                nil
            ) == SQLITE_OK else {
                throw LocalStoreError.invalidExplanationDatabase
            }
        }
        defer { sqlite3_finalize(sourceRelatedStatement) }

        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            let sourceName = "Wiktionary via Lector"
            let deleteStatement = try prepare("DELETE FROM dictionary_explanations WHERE source = ?")
            bind(sourceName, to: 1, in: deleteStatement)
            defer { sqlite3_finalize(deleteStatement) }
            try stepDone(deleteStatement)

            let deleteInflections = try prepare("DELETE FROM dictionary_inflections WHERE source = ?")
            bind(sourceName, to: 1, in: deleteInflections)
            defer { sqlite3_finalize(deleteInflections) }
            try stepDone(deleteInflections)

            for table in ["dictionary_reference_entries", "dictionary_related_forms"] {
                let deleteReference = try prepare("DELETE FROM \(table) WHERE source = ?")
                bind(sourceName, to: 1, in: deleteReference)
                let step = sqlite3_step(deleteReference)
                sqlite3_finalize(deleteReference)
                guard step == SQLITE_DONE else { throw sqliteError() }
            }

            let insertStatement = try prepare("""
                INSERT OR IGNORE INTO dictionary_explanations
                  (german_key, kind, explanation, source, sort_order)
                VALUES (?, ?, ?, ?, ?)
                """)
            defer { sqlite3_finalize(insertStatement) }

            let insertInflection = try prepare("""
                INSERT OR IGNORE INTO dictionary_inflections
                  (lemma_key, form, tags, source, kind)
                VALUES (?, ?, ?, ?, ?)
                """)
            defer { sqlite3_finalize(insertInflection) }

            func storeInflection(
                lemma: String,
                form: String,
                tags: Set<String>,
                kind: WordKind
            ) throws {
                let lemmaKey = dictionaryGroupingTerm(lemma)
                let cleanForm = form.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !lemmaKey.isEmpty, !cleanForm.isEmpty, !tags.isEmpty else { return }
                sqlite3_reset(insertInflection)
                sqlite3_clear_bindings(insertInflection)
                bind(lemmaKey, to: 1, in: insertInflection)
                bind(cleanForm, to: 2, in: insertInflection)
                bind(tags.sorted().joined(separator: ","), to: 3, in: insertInflection)
                bind(sourceName, to: 4, in: insertInflection)
                bind(kind.rawValue, to: 5, in: insertInflection)
                try stepDone(insertInflection)
            }

            var imported = 0
            while true {
                let step = sqlite3_step(sourceStatement)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW,
                      let wordValue = sqlite3_column_text(sourceStatement, 0),
                      let glossValue = sqlite3_column_text(sourceStatement, 2) else {
                    throw LocalStoreError.invalidExplanationDatabase
                }
                let sourceWord = String(cString: wordValue).trimmingCharacters(in: .whitespacesAndNewlines)
                let word = dictionaryGroupingTerm(sourceWord)
                let gloss = String(cString: glossValue).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !word.isEmpty, !gloss.isEmpty else { continue }
                let position = sqlite3_column_int(sourceStatement, 3)
                let partOfSpeech = sqlite3_column_text(sourceStatement, 1).map { String(cString: $0) } ?? ""

                sqlite3_reset(insertStatement)
                sqlite3_clear_bindings(insertStatement)
                bind(word, to: 1, in: insertStatement)
                bind(wordKind(forLectorPartOfSpeech: partOfSpeech).rawValue, to: 2, in: insertStatement)
                bind(gloss, to: 3, in: insertStatement)
                bind(sourceName, to: 4, in: insertStatement)
                sqlite3_bind_int(insertStatement, 5, position)
                try stepDone(insertStatement)
                if let degree = lectorDegreeInflection(word: sourceWord, gloss: gloss) {
                    try storeInflection(
                        lemma: degree.lemma,
                        form: sourceWord,
                        tags: [degree.tag],
                        kind: .adjective
                    )
                }
                imported += 1
                if imported % 5_000 == 0 {
                    progress(.init(imported: imported, total: total))
                }
            }
            if let sourceInflectionStatement {
                while true {
                    let step = sqlite3_step(sourceInflectionStatement)
                    if step == SQLITE_DONE { break }
                    guard step == SQLITE_ROW,
                          let formValue = sqlite3_column_text(sourceInflectionStatement, 0),
                          let lemmaValue = sqlite3_column_text(sourceInflectionStatement, 1),
                          let typeValue = sqlite3_column_text(sourceInflectionStatement, 2) else {
                        throw LocalStoreError.invalidExplanationDatabase
                    }
                    let tags = lectorTags(String(cString: typeValue))
                    let partsOfSpeech = sqlite3_column_text(sourceInflectionStatement, 3)
                        .map { String(cString: $0) } ?? ""
                    let kind = lectorInflectionKind(tags: tags, partsOfSpeech: partsOfSpeech)
                    try storeInflection(
                        lemma: String(cString: lemmaValue),
                        form: String(cString: formValue),
                        tags: tags,
                        kind: kind
                    )
                }
            }
            let insertReference = try prepare("""
                INSERT OR IGNORE INTO dictionary_reference_entries
                  (german_key, word, ipa, etymology, source)
                VALUES (?, ?, ?, ?, ?)
                """)
            defer { sqlite3_finalize(insertReference) }
            if let sourceReferenceStatement {
                while true {
                    let step = sqlite3_step(sourceReferenceStatement)
                    if step == SQLITE_DONE { break }
                    guard step == SQLITE_ROW,
                          let wordValue = sqlite3_column_text(sourceReferenceStatement, 0) else {
                        throw LocalStoreError.invalidExplanationDatabase
                    }
                    let word = String(cString: wordValue).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !word.isEmpty else { continue }
                    sqlite3_reset(insertReference)
                    sqlite3_clear_bindings(insertReference)
                    bind(dictionaryGroupingTerm(word), to: 1, in: insertReference)
                    bind(word, to: 2, in: insertReference)
                    bindNullableSourceText(sourceReferenceStatement, column: 1, to: 3, in: insertReference)
                    bindNullableSourceText(sourceReferenceStatement, column: 2, to: 4, in: insertReference)
                    bind(sourceName, to: 5, in: insertReference)
                    try stepDone(insertReference)
                }
            }

            let insertRelated = try prepare("""
                INSERT OR IGNORE INTO dictionary_related_forms
                  (german_key, related_word, relation, source)
                VALUES (?, ?, ?, ?)
                """)
            defer { sqlite3_finalize(insertRelated) }
            if let sourceRelatedStatement {
                while true {
                    let step = sqlite3_step(sourceRelatedStatement)
                    if step == SQLITE_DONE { break }
                    guard step == SQLITE_ROW,
                          let wordValue = sqlite3_column_text(sourceRelatedStatement, 0),
                          let relatedValue = sqlite3_column_text(sourceRelatedStatement, 1),
                          let relationValue = sqlite3_column_text(sourceRelatedStatement, 2) else {
                        throw LocalStoreError.invalidExplanationDatabase
                    }
                    let word = String(cString: wordValue).trimmingCharacters(in: .whitespacesAndNewlines)
                    let related = String(cString: relatedValue).trimmingCharacters(in: .whitespacesAndNewlines)
                    let relation = String(cString: relationValue).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !word.isEmpty, !related.isEmpty, !relation.isEmpty else { continue }
                    sqlite3_reset(insertRelated)
                    sqlite3_clear_bindings(insertRelated)
                    bind(dictionaryGroupingTerm(word), to: 1, in: insertRelated)
                    bind(related, to: 2, in: insertRelated)
                    bind(relation, to: 3, in: insertRelated)
                    bind(sourceName, to: 4, in: insertRelated)
                    try stepDone(insertRelated)
                }
            }
            let stored: Int
            do {
                let storedStatement = try prepare("SELECT COUNT(*) FROM dictionary_explanations WHERE source = ?")
                defer { sqlite3_finalize(storedStatement) }
                bind(sourceName, to: 1, in: storedStatement)
                stored = try readScalarInt(storedStatement)
            }
            try Self.execute(database, "COMMIT")
            dictionaryClassifications.removeAll(keepingCapacity: true)
            try Self.execute(database, "PRAGMA optimize")
            progress(.init(imported: imported, total: total))
            return stored
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    @discardableResult
    public func addCard(from entry: DictionaryEntry, listID: Int64 = WordList.defaultID) throws -> PersonalCard {
        try addCardRecordingChange(from: entry, listID: listID).card
    }

    public func addCardRecordingChange(
        from entry: DictionaryEntry,
        listID: WordList.ID
    ) throws -> AddedCardMutation {
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            let addition = try addCardRecordingChangeInsideTransaction(from: entry, listID: listID)
            try Self.execute(database, "COMMIT")
            return addition
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    public func cacheTranslationAndAddCardRecordingChange(
        from entry: DictionaryEntry,
        listID: WordList.ID
    ) throws -> AddedCardMutation {
        guard entry.isAppleTranslation else {
            throw LocalStoreError.sqlite("Only Apple Translation results can be cached as translations")
        }
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            try insertDictionaryEntry(entry)
            let statement = try prepare("""
                SELECT id, german, english, raw_german, raw_english,
                       kind, gender, usage, source, translation_language,
                       explanation, grammar, subject
                FROM dictionary_entries
                WHERE raw_german = ? AND raw_english = ? AND translation_language = ?
                LIMIT 1
                """)
            defer { sqlite3_finalize(statement) }
            bind(entry.rawGerman, to: 1, in: statement)
            bind(entry.rawEnglish, to: 2, in: statement)
            bind(TranslationLanguage.english.rawValue, to: 3, in: statement)
            guard let cachedEntry = try readEntries(statement).first else {
                throw LocalStoreError.sqlite("Could not read the cached translation")
            }
            dictionaryClassifications.removeValue(forKey: dictionaryGroupingTerm(entry.german))
            let addition = try addCardRecordingChangeInsideTransaction(
                from: cachedEntry,
                listID: listID
            )
            try Self.execute(database, "COMMIT")
            return addition
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    private func addCardRecordingChangeInsideTransaction(
        from entry: DictionaryEntry,
        listID: WordList.ID
    ) throws -> AddedCardMutation {
        let card: PersonalCard
        if entry.id != 0, var existing = try self.card(forDictionaryEntryID: entry.id) {
            if existing.meanings == nil {
                existing.english = entry.english
                existing.meanings = entry.meanings
                try updateCard(existing)
            }
            card = existing
        } else {
            let timestamp = now().timeIntervalSince1970
            let sql = """
                INSERT INTO personal_cards
                  (dictionary_entry_id, german, english, raw_german, kind, gender, created_at, due_at, meanings_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            sqlite3_bind_double(statement, 7, timestamp)
            sqlite3_bind_double(statement, 8, timestamp)
            bind(try meaningsJSON(entry.meanings), to: 9, in: statement)
            try stepDone(statement)
            let id = sqlite3_last_insert_rowid(database)
            guard let inserted = try self.card(id: id) else {
                throw LocalStoreError.sqlite("Could not read the newly created card")
            }
            card = inserted
        }
        let didAddToList = try insertCard(card.id, toList: listID, addedAt: now())
        return AddedCardMutation(card: card, didAddToList: didAddToList)
    }

    public func cards(search: String = "", listID: Int64 = WordList.defaultID, limit: Int = 500) throws -> [PersonalCard] {
        guard limit > 0 else { return [] }
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
        sqlite3_bind_int(statement, index, Int32(clamping: limit))
        return try readCards(statement)
    }

    public func dueCards(listID: Int64 = WordList.defaultID, limit: Int = 100, now: Date = .now) throws -> [PersonalCard] {
        guard limit > 0 else { return [] }
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
        sqlite3_bind_int(statement, 3, Int32(clamping: limit))
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
        let createdAt = now()
        bind(name, to: 1, in: statement)
        sqlite3_bind_double(statement, 2, createdAt.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            if sqlite3_errcode(database) == SQLITE_CONSTRAINT { throw LocalStoreError.duplicateListName }
            throw sqliteError()
        }
        return .init(id: sqlite3_last_insert_rowid(database), name: name, createdAt: createdAt)
    }

    public func createWordList(
        name: String,
        movingCard cardID: PersonalCard.ID,
        fromList sourceListID: WordList.ID
    ) throws -> WordList {
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            let list = try createWordList(name: name)
            _ = try insertCard(cardID, toList: list.id, addedAt: now())

            let statement = try prepare("DELETE FROM card_lists WHERE card_id = ? AND list_id = ?")
            sqlite3_bind_int64(statement, 1, cardID)
            sqlite3_bind_int64(statement, 2, sourceListID)
            let step = sqlite3_step(statement)
            sqlite3_finalize(statement)
            guard step == SQLITE_DONE else { throw sqliteError() }

            try Self.execute(database, "COMMIT")
            return list
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
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
        _ = try deleteWordListRecordingChange(id: id)
    }

    public func deleteWordListRecordingChange(id: WordList.ID) throws -> DeletedWordListMutation {
        guard id != WordList.defaultID else { throw LocalStoreError.cannotDeleteDefaultList }
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            guard let list = try wordList(id: id) else {
                throw LocalStoreError.sqlite("Could not find the list to delete")
            }
            let cardIDs = try cardIDs(inList: id)
            let cardMutations = try cardIDs.compactMap {
                try removedCardMutation(cardID: $0, listID: id)
            }
            let linkedSentenceIDs = try sentenceIDs(sourceListID: id)
            let statement = try prepare("DELETE FROM word_lists WHERE id = ?")
            sqlite3_bind_int64(statement, 1, id)
            let step = sqlite3_step(statement)
            sqlite3_finalize(statement)
            guard step == SQLITE_DONE else { throw sqliteError() }
            try Self.execute(database, "DELETE FROM personal_cards WHERE NOT EXISTS (SELECT 1 FROM card_lists WHERE card_lists.card_id = personal_cards.id)")
            try Self.execute(database, "COMMIT")
            return DeletedWordListMutation(
                list: list,
                cards: cardMutations,
                linkedSentenceIDs: linkedSentenceIDs
            )
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    public func addCard(_ cardID: Int64, toList listID: Int64) throws {
        _ = try insertCard(cardID, toList: listID, addedAt: now())
    }

    public func addCardRecordingChange(
        _ cardID: PersonalCard.ID,
        toList listID: WordList.ID
    ) throws -> Bool {
        try insertCard(cardID, toList: listID, addedAt: now())
    }

    public func removeCard(_ cardID: Int64, fromList listID: Int64) throws {
        _ = try removeCardRecordingChange(cardID, fromList: listID)
    }

    public func removeCardRecordingChange(
        _ cardID: PersonalCard.ID,
        fromList listID: WordList.ID
    ) throws -> RemovedCardMutation? {
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            guard let mutation = try removedCardMutation(cardID: cardID, listID: listID) else {
                try Self.execute(database, "COMMIT")
                return nil
            }
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
            return mutation
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    public func restoreRemovedCard(_ mutation: RemovedCardMutation) throws {
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            try restoreCard(mutation.card)
            try restoreReviews(mutation.reviews, cardID: mutation.card.id)
            _ = try insertCard(
                mutation.card.id,
                toList: mutation.listID,
                addedAt: mutation.addedAt
            )
            try Self.execute(database, "COMMIT")
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    public func restoreDeletedWordList(_ mutation: DeletedWordListMutation) throws {
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            let listStatement = try prepare(
                "INSERT INTO word_lists (id, name, created_at) VALUES (?, ?, ?)"
            )
            sqlite3_bind_int64(listStatement, 1, mutation.list.id)
            bind(mutation.list.name, to: 2, in: listStatement)
            sqlite3_bind_double(listStatement, 3, mutation.list.createdAt.timeIntervalSince1970)
            let listStep = sqlite3_step(listStatement)
            sqlite3_finalize(listStatement)
            guard listStep == SQLITE_DONE else { throw sqliteError() }

            for cardMutation in mutation.cards {
                try restoreCard(cardMutation.card)
                try restoreReviews(cardMutation.reviews, cardID: cardMutation.card.id)
                _ = try insertCard(
                    cardMutation.card.id,
                    toList: mutation.list.id,
                    addedAt: cardMutation.addedAt
                )
            }

            let sentenceStatement = try prepare(
                "UPDATE saved_sentences SET source_list_id = ? WHERE id = ?"
            )
            defer { sqlite3_finalize(sentenceStatement) }
            for sentenceID in mutation.linkedSentenceIDs {
                sqlite3_reset(sentenceStatement)
                sqlite3_clear_bindings(sentenceStatement)
                sqlite3_bind_int64(sentenceStatement, 1, mutation.list.id)
                sqlite3_bind_int64(sentenceStatement, 2, sentenceID)
                try stepDone(sentenceStatement)
            }
            try Self.execute(database, "COMMIT")
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    public func moveCard(
        _ cardID: Int64,
        fromList sourceListID: Int64,
        toList destinationListID: Int64
    ) throws {
        guard sourceListID != destinationListID else { return }
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            try addCard(cardID, toList: destinationListID)

            let statement = try prepare("DELETE FROM card_lists WHERE card_id = ? AND list_id = ?")
            sqlite3_bind_int64(statement, 1, cardID)
            sqlite3_bind_int64(statement, 2, sourceListID)
            let step = sqlite3_step(statement)
            sqlite3_finalize(statement)
            guard step == SQLITE_DONE else { throw sqliteError() }

            try Self.execute(database, "COMMIT")
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    public func review(
        card: PersonalCard,
        rating: ReviewRating,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> PersonalCard {
        let updated = SpacedRepetitionScheduler.reviewed(card, rating: rating, now: now, calendar: calendar)
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            try updateCard(updated)
            let log = try prepare("INSERT INTO review_log (card_id, rating, reviewed_at, interval_days) VALUES (?, ?, ?, ?)")
            defer { sqlite3_finalize(log) }
            sqlite3_bind_int64(log, 1, card.id)
            sqlite3_bind_int(log, 2, Int32(rating.rawValue))
            sqlite3_bind_double(log, 3, now.timeIntervalSince1970)
            sqlite3_bind_double(log, 4, updated.intervalDays)
            try stepDone(log)
            try Self.execute(database, "COMMIT")
            return updated
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    public func updateCard(_ card: PersonalCard) throws {
        let sql = """
            UPDATE personal_cards SET
              german = ?, english = ?, raw_german = ?, kind = ?, gender = ?, notes = ?, tags = ?,
              due_at = ?, last_reviewed_at = ?, interval_days = ?, ease_factor = ?, repetitions = ?, lapses = ?,
              is_starred = ?, is_suspended = ?, meanings_json = ?
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
        if let meanings = card.meanings {
            bind(try meaningsJSON(meanings), to: 16, in: statement)
        } else {
            sqlite3_bind_null(statement, 16)
        }
        sqlite3_bind_int64(statement, 17, card.id)
        try stepDone(statement)
    }

    public func deleteCard(id: Int64) throws {
        let statement = try prepare("DELETE FROM personal_cards WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        try stepDone(statement)
    }

    public func personalCard(id: PersonalCard.ID) throws -> PersonalCard? {
        try card(id: id)
    }

    public func savedSentences(limit: Int = 500) throws -> [SavedSentence] {
        guard limit > 0 else { return [] }
        let statement = try prepare("""
            SELECT id, german, translation, source_list_id, source_list_name,
                   tokens_json, analysis_json, created_at
            FROM saved_sentences
            ORDER BY created_at DESC, id DESC
            LIMIT ?
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(clamping: limit))
        return try readSentences(statement)
    }

    @discardableResult
    public func saveSentences(_ drafts: [SentenceDraft], sourceList: WordList) throws -> [SavedSentence] {
        let validDrafts = drafts.prefix(10).filter {
            !$0.german.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.tokens.isEmpty
        }
        guard !validDrafts.isEmpty else { return [] }

        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            let sql = """
                INSERT OR IGNORE INTO saved_sentences
                  (german, translation, source_list_id, source_list_name, tokens_json, analysis_json, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            let encoder = JSONEncoder()
            var result: [SavedSentence] = []

            for draft in validDrafts {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bind(draft.german.trimmingCharacters(in: .whitespacesAndNewlines), to: 1, in: statement)
                bind(draft.translation.trimmingCharacters(in: .whitespacesAndNewlines), to: 2, in: statement)
                sqlite3_bind_int64(statement, 3, sourceList.id)
                bind(sourceList.name, to: 4, in: statement)
                let tokenData = try encoder.encode(draft.tokens)
                guard let tokenJSON = String(data: tokenData, encoding: .utf8) else {
                    throw LocalStoreError.sqlite("Could not encode sentence words")
                }
                bind(tokenJSON, to: 5, in: statement)
                if let analysis = draft.analysis {
                    let analysisData = try encoder.encode(analysis)
                    guard let analysisJSON = String(data: analysisData, encoding: .utf8) else {
                        throw LocalStoreError.sqlite("Could not encode sentence analysis")
                    }
                    bind(analysisJSON, to: 6, in: statement)
                } else {
                    sqlite3_bind_null(statement, 6)
                }
                let createdAt = now()
                sqlite3_bind_double(statement, 7, createdAt.timeIntervalSince1970)
                try stepDone(statement)

                if sqlite3_changes(database) > 0 {
                    result.append(.init(
                        id: sqlite3_last_insert_rowid(database),
                        german: draft.german,
                        translation: draft.translation,
                        sourceListID: sourceList.id,
                        sourceListName: sourceList.name,
                        tokens: draft.tokens,
                        analysis: draft.analysis,
                        createdAt: createdAt
                    ))
                }
            }
            try Self.execute(database, "COMMIT")
            return result
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    public func deleteSentence(id: SavedSentence.ID) throws {
        let statement = try prepare("DELETE FROM saved_sentences WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        try stepDone(statement)
    }

    public func deleteSentences(ids: [SavedSentence.ID]) throws {
        guard !ids.isEmpty else { return }
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            let statement = try prepare("DELETE FROM saved_sentences WHERE id = ?")
            defer { sqlite3_finalize(statement) }
            for id in ids {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                sqlite3_bind_int64(statement, 1, id)
                try stepDone(statement)
            }
            try Self.execute(database, "COMMIT")
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    public func restoreSentences(_ sentences: [SavedSentence]) throws {
        guard !sentences.isEmpty else { return }
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            let statement = try prepare("""
                INSERT INTO saved_sentences
                  (id, german, translation, source_list_id, source_list_name, tokens_json, analysis_json, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """)
            defer { sqlite3_finalize(statement) }
            let encoder = JSONEncoder()
            for sentence in sentences {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                sqlite3_bind_int64(statement, 1, sentence.id)
                bind(sentence.german, to: 2, in: statement)
                bind(sentence.translation, to: 3, in: statement)
                if let sourceListID = sentence.sourceListID {
                    sqlite3_bind_int64(statement, 4, sourceListID)
                } else {
                    sqlite3_bind_null(statement, 4)
                }
                bind(sentence.sourceListName, to: 5, in: statement)
                let tokenData = try encoder.encode(sentence.tokens)
                guard let tokenJSON = String(data: tokenData, encoding: .utf8) else {
                    throw LocalStoreError.sqlite("Could not encode sentence words")
                }
                bind(tokenJSON, to: 6, in: statement)
                if let analysis = sentence.analysis {
                    let analysisData = try encoder.encode(analysis)
                    guard let analysisJSON = String(data: analysisData, encoding: .utf8) else {
                        throw LocalStoreError.sqlite("Could not encode sentence analysis")
                    }
                    bind(analysisJSON, to: 7, in: statement)
                } else {
                    sqlite3_bind_null(statement, 7)
                }
                sqlite3_bind_double(statement, 8, sentence.createdAt.timeIntervalSince1970)
                try stepDone(statement)
            }
            try Self.execute(database, "COMMIT")
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
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
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            throw LocalStoreError.sqlite("Could not calculate the study-day boundary")
        }
        let reviewsStatement = try prepare("SELECT COUNT(*) FROM review_log AS r JOIN card_lists AS cl ON cl.card_id = r.card_id WHERE cl.list_id = ? AND r.reviewed_at >= ? AND r.reviewed_at < ?")
        defer { sqlite3_finalize(reviewsStatement) }
        sqlite3_bind_int64(reviewsStatement, 1, listID)
        sqlite3_bind_double(reviewsStatement, 2, start)
        sqlite3_bind_double(reviewsStatement, 3, nextDay.timeIntervalSince1970)
        let reviews = try readScalarInt(reviewsStatement)
        let dayStatement = try prepare("SELECT r.reviewed_at FROM review_log AS r JOIN card_lists AS cl ON cl.card_id = r.card_id WHERE cl.list_id = ?")
        defer { sqlite3_finalize(dayStatement) }
        sqlite3_bind_int64(dayStatement, 1, listID)
        var reviewDays = Set<Date>()
        while true {
            let step = sqlite3_step(dayStatement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw sqliteError() }
            let reviewedAt = Date(timeIntervalSince1970: sqlite3_column_double(dayStatement, 0))
            reviewDays.insert(calendar.startOfDay(for: reviewedAt))
        }
        var streak = 0
        var day = calendar.startOfDay(for: now)
        while reviewDays.contains(day) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previousDay
        }
        return .init(totalCards: total, dueCards: due, reviewsToday: reviews, streakDays: streak)
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
        bind(entry.meanings.first?.language.rawValue ?? TranslationLanguage.english.rawValue, to: 11, in: statement)
        if let explanation = entry.meanings.first?.explanation {
            bind(explanation, to: 12, in: statement)
        } else {
            sqlite3_bind_null(statement, 12)
        }
        if let grammar = entry.meanings.first?.grammar {
            bind(grammar, to: 13, in: statement)
        } else {
            sqlite3_bind_null(statement, 13)
        }
        if let subject = entry.meanings.first?.subject {
            bind(subject, to: 14, in: statement)
        } else {
            sqlite3_bind_null(statement, 14)
        }
        try stepDone(statement)
    }

    private var dictionaryInsertSQL: String {
        """
        INSERT OR IGNORE INTO dictionary_entries
          (german, english, normalized_german, normalized_english, raw_german, raw_english, kind, gender, usage, source, translation_language, explanation, grammar, subject)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
    }

    private var dictionaryImportSQL: String {
        """
        INSERT INTO dictionary_entries
          (german, english, normalized_german, normalized_english, raw_german, raw_english, kind, gender, usage, source, translation_language, explanation, grammar, subject)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(raw_german, raw_english, translation_language) DO UPDATE SET
          german = excluded.german,
          english = excluded.english,
          normalized_german = excluded.normalized_german,
          normalized_english = excluded.normalized_english,
          kind = excluded.kind,
          gender = excluded.gender,
          usage = excluded.usage,
          source = excluded.source,
          explanation = coalesce(excluded.explanation, dictionary_entries.explanation),
          grammar = CASE
            WHEN excluded.grammar IS NULL OR excluded.grammar = '' THEN dictionary_entries.grammar
            WHEN dictionary_entries.grammar IS NULL OR dictionary_entries.grammar = '' THEN excluded.grammar
            WHEN dictionary_entries.grammar = excluded.grammar THEN dictionary_entries.grammar
            ELSE dictionary_entries.grammar || ' · ' || excluded.grammar
          END,
          subject = CASE
            WHEN excluded.subject IS NULL OR excluded.subject = '' THEN dictionary_entries.subject
            WHEN dictionary_entries.subject IS NULL OR dictionary_entries.subject = '' THEN excluded.subject
            WHEN dictionary_entries.subject = excluded.subject THEN dictionary_entries.subject
            ELSE dictionary_entries.subject || ' · ' || excluded.subject
          END
        """
    }

    private func card(id: Int64) throws -> PersonalCard? {
        let statement = try prepare("SELECT \(cardColumns) FROM personal_cards WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        return try readCards(statement).first
    }

    private func wordList(id: WordList.ID) throws -> WordList? {
        let statement = try prepare("SELECT id, name, created_at FROM word_lists WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return nil }
        guard step == SQLITE_ROW else { throw sqliteError() }
        return WordList(
            id: sqlite3_column_int64(statement, 0),
            name: text(statement, 1),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
        )
    }

    private func cardIDs(inList listID: WordList.ID) throws -> [PersonalCard.ID] {
        let statement = try prepare(
            "SELECT card_id FROM card_lists WHERE list_id = ? ORDER BY card_id"
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, listID)
        var result: [PersonalCard.ID] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else { throw sqliteError() }
            result.append(sqlite3_column_int64(statement, 0))
        }
    }

    private func sentenceIDs(sourceListID: WordList.ID) throws -> [SavedSentence.ID] {
        let statement = try prepare(
            "SELECT id FROM saved_sentences WHERE source_list_id = ? ORDER BY id"
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sourceListID)
        var result: [SavedSentence.ID] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else { throw sqliteError() }
            result.append(sqlite3_column_int64(statement, 0))
        }
    }

    private func removedCardMutation(
        cardID: PersonalCard.ID,
        listID: WordList.ID
    ) throws -> RemovedCardMutation? {
        guard let card = try card(id: cardID) else { return nil }
        let membership = try prepare(
            "SELECT added_at FROM card_lists WHERE card_id = ? AND list_id = ?"
        )
        defer { sqlite3_finalize(membership) }
        sqlite3_bind_int64(membership, 1, cardID)
        sqlite3_bind_int64(membership, 2, listID)
        let membershipStep = sqlite3_step(membership)
        if membershipStep == SQLITE_DONE { return nil }
        guard membershipStep == SQLITE_ROW else { throw sqliteError() }
        return RemovedCardMutation(
            card: card,
            listID: listID,
            addedAt: Date(timeIntervalSince1970: sqlite3_column_double(membership, 0)),
            reviews: try reviews(cardID: cardID)
        )
    }

    private func reviews(cardID: PersonalCard.ID) throws -> [CardReviewSnapshot] {
        let statement = try prepare("""
            SELECT id, rating, reviewed_at, interval_days
            FROM review_log
            WHERE card_id = ?
            ORDER BY id
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, cardID)
        var result: [CardReviewSnapshot] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else { throw sqliteError() }
            result.append(.init(
                id: sqlite3_column_int64(statement, 0),
                rating: Int(sqlite3_column_int(statement, 1)),
                reviewedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                intervalDays: sqlite3_column_double(statement, 3)
            ))
        }
    }

    @discardableResult
    private func insertCard(
        _ cardID: PersonalCard.ID,
        toList listID: WordList.ID,
        addedAt: Date
    ) throws -> Bool {
        let statement = try prepare(
            "INSERT OR IGNORE INTO card_lists (card_id, list_id, added_at) VALUES (?, ?, ?)"
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, cardID)
        sqlite3_bind_int64(statement, 2, listID)
        sqlite3_bind_double(statement, 3, addedAt.timeIntervalSince1970)
        try stepDone(statement)
        return sqlite3_changes(database) > 0
    }

    private func restoreCard(_ card: PersonalCard) throws {
        guard try self.card(id: card.id) == nil else { return }
        let statement = try prepare("""
            INSERT INTO personal_cards
              (id, dictionary_entry_id, german, english, raw_german, kind, gender, notes, tags,
               created_at, due_at, last_reviewed_at, interval_days, ease_factor, repetitions,
               lapses, is_starred, is_suspended, meanings_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, card.id)
        if let dictionaryEntryID = card.dictionaryEntryID {
            sqlite3_bind_int64(statement, 2, dictionaryEntryID)
        } else {
            sqlite3_bind_null(statement, 2)
        }
        bind(card.german, to: 3, in: statement)
        bind(card.english, to: 4, in: statement)
        bind(card.rawGerman, to: 5, in: statement)
        bind(card.kind.rawValue, to: 6, in: statement)
        bind(card.gender.rawValue, to: 7, in: statement)
        bind(card.notes, to: 8, in: statement)
        bind(card.tags, to: 9, in: statement)
        sqlite3_bind_double(statement, 10, card.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 11, card.dueAt.timeIntervalSince1970)
        if let lastReviewedAt = card.lastReviewedAt {
            sqlite3_bind_double(statement, 12, lastReviewedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 12)
        }
        sqlite3_bind_double(statement, 13, card.intervalDays)
        sqlite3_bind_double(statement, 14, card.easeFactor)
        sqlite3_bind_int(statement, 15, Int32(clamping: card.repetitions))
        sqlite3_bind_int(statement, 16, Int32(clamping: card.lapses))
        sqlite3_bind_int(statement, 17, card.isStarred ? 1 : 0)
        sqlite3_bind_int(statement, 18, card.isSuspended ? 1 : 0)
        if let meanings = card.meanings {
            bind(try meaningsJSON(meanings), to: 19, in: statement)
        } else {
            sqlite3_bind_null(statement, 19)
        }
        try stepDone(statement)
    }

    private func restoreReviews(
        _ reviews: [CardReviewSnapshot],
        cardID: PersonalCard.ID
    ) throws {
        let statement = try prepare("""
            INSERT OR IGNORE INTO review_log
              (id, card_id, rating, reviewed_at, interval_days)
            VALUES (?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }
        for review in reviews {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_int64(statement, 1, review.id)
            sqlite3_bind_int64(statement, 2, cardID)
            sqlite3_bind_int(statement, 3, Int32(clamping: review.rating))
            sqlite3_bind_double(statement, 4, review.reviewedAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 5, review.intervalDays)
            try stepDone(statement)
        }
    }

    private func card(forDictionaryEntryID id: Int64) throws -> PersonalCard? {
        let statement = try prepare("SELECT \(cardColumns) FROM personal_cards WHERE dictionary_entry_id = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        return try readCards(statement).first
    }

    private var cardColumns: String {
        "id, dictionary_entry_id, german, english, raw_german, kind, gender, notes, tags, created_at, due_at, last_reviewed_at, interval_days, ease_factor, repetitions, lapses, is_starred, is_suspended, meanings_json"
    }

    private var qualifiedCardColumns: String {
        "c.id, c.dictionary_entry_id, c.german, c.english, c.raw_german, c.kind, c.gender, c.notes, c.tags, c.created_at, c.due_at, c.last_reviewed_at, c.interval_days, c.ease_factor, c.repetitions, c.lapses, c.is_starred, c.is_suspended, c.meanings_json"
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
                source: text(statement, 8),
                explanation: nullableText(statement, 10),
                translationLanguage: TranslationLanguage(rawValue: text(statement, 9)) ?? .english,
                meanings: [DictionaryMeaning(
                    english: text(statement, 2),
                    rawEnglish: text(statement, 4),
                    rawGerman: text(statement, 3),
                    language: TranslationLanguage(rawValue: text(statement, 9)) ?? .english,
                    gender: Gender(rawValue: text(statement, 6)) ?? .unknown,
                    usage: nullableText(statement, 7),
                    explanation: nullableText(statement, 10),
                    grammar: nullableText(statement, 11),
                    subject: nullableText(statement, 12)
                )]
            ))
        }
    }

    private func dictionaryGroups(representedBy representative: DictionaryEntry) throws -> [DictionaryEntry] {
        let representative = try resolvedDictionaryEntry(representative)
        let singularEntries = try dictionarySingularEntries(for: representative)
        let representatives = singularEntries.isEmpty ? [representative] : singularEntries
        return try representatives.map(dictionaryGroup)
    }

    private func dictionaryGroup(representedBy representative: DictionaryEntry) throws -> DictionaryEntry {
        let groupTerm = dictionaryGroupingTerm(representative.german)
        let spellings = dictionaryGroupingSpellings(for: groupTerm)
        let placeholders = Array(repeating: "?", count: spellings.count).joined(separator: ", ")
        let sql = """
            SELECT id, german, english, raw_german, raw_english,
                   kind, gender, usage, source, translation_language,
                   explanation, grammar, subject
            FROM dictionary_entries
            WHERE normalized_german IN (\(placeholders))
            ORDER BY CASE translation_language WHEN 'en' THEN 0 WHEN 'ru' THEN 1 ELSE 2 END, id
            """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        for (offset, spelling) in spellings.enumerated() {
            bind(DictCCParser.normalized(spelling), to: Int32(offset + 1), in: statement)
        }
        let groupEntries = try readEntries(statement)
            .filter { dictionaryGroupingTerm($0.german) == groupTerm }
            .map(resolvedDictionaryEntry)
        let singularGenders = Set(groupEntries.compactMap { entry -> Gender? in
            guard entry.kind == .noun,
                  entry.gender != .unknown, entry.gender != .plural else { return nil }
            return entry.gender
        })
        let entries = groupEntries.filter { entry in
            guard entry.kind == representative.kind else { return false }
            guard entry.kind == .noun else { return true }
            if entry.gender == .plural { return true }
            if representative.gender == .plural {
                return singularGenders.count == 1
            }
            return entry.gender == representative.gender
        }
        guard let canonical = entries.sorted(by: dictionaryCanonicalEntrySortsBefore).first else {
            return representative
        }
        let singularEntries = entries.filter { $0.gender != .plural }
        let sameSpellingPluralEntries = entries.filter { $0.gender == .plural }
        let linkedPluralEntries = try dictionaryPluralEntries(for: canonical)
        var seenEntryIDs = Set<Int64>()
        let pluralEntries = (sameSpellingPluralEntries + linkedPluralEntries).filter {
            seenEntryIDs.insert($0.id).inserted
        }
        let baseEntries = singularEntries.isEmpty ? entries : singularEntries
        let meaningEntries = baseEntries + pluralEntries

        var seenMeanings = Set<String>()
        let meanings = meaningEntries.compactMap { entry -> DictionaryMeaning? in
            let meaning = DictionaryMeaning(
                english: entry.english,
                rawEnglish: entry.rawEnglish,
                rawGerman: entry.rawGerman,
                language: entry.meanings.first?.language ?? .english,
                gender: entry.gender,
                usage: entry.usage,
                explanation: entry.meanings.first?.explanation,
                grammar: entry.meanings.first?.grammar,
                subject: entry.meanings.first?.subject
            )
            return seenMeanings.insert(meaning.id).inserted ? meaning : nil
        }
        let genders = Set(baseEntries.map(\.gender))
        let usages = Set(baseEntries.map(\.usage))
        let sources = meaningEntries.map(\.source).reduce(into: [String]()) { result, source in
            if !result.contains(source) { result.append(source) }
        }
        let explanations = try dictionaryExplanations(for: canonical)
        let forms = try dictionaryForms(for: canonical.german, kind: canonical.kind)
        let reference = try dictionaryReference(for: canonical.german)
        let pluralForms = (baseEntries.flatMap(GermanMorphology.pluralForms) + pluralEntries.map(\.german))
            .reduce(into: [String]()) { forms, form in
                if !forms.contains(form) { forms.append(form) }
        }
        let allSources = explanations.reduce(into: sources) { result, explanation in
            if !result.contains(explanation.source) { result.append(explanation.source) }
        }
        let sourcesWithForms = forms.reduce(into: allSources) { result, form in
            if !result.contains(form.source) { result.append(form.source) }
        }
        let completeSources = reference.sources.reduce(into: sourcesWithForms) { result, source in
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
            source: completeSources.joined(separator: ", "),
            pluralForms: pluralForms,
            meanings: meanings,
            explanations: explanations,
            forms: forms,
            ipa: reference.ipa,
            etymology: reference.etymology,
            relatedForms: reference.relatedForms
        )
    }

    private func dictionarySingularEntries(for entry: DictionaryEntry) throws -> [DictionaryEntry] {
        guard entry.kind == .noun, entry.gender == .plural else { return [] }
        let relationStatement = try prepare("""
            SELECT DISTINCT lemma_key
            FROM dictionary_inflections
            WHERE form = ?
              AND kind = 'noun'
              AND instr(',' || tags || ',', ',plural,') > 0
            ORDER BY lemma_key
            """)
        defer { sqlite3_finalize(relationStatement) }
        bind(dictionaryGroupingTerm(entry.german), to: 1, in: relationStatement)
        var singularKeys: [String] = []
        while true {
            let step = sqlite3_step(relationStatement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw sqliteError() }
            singularKeys.append(text(relationStatement, 0))
        }
        let candidates = try singularKeys.compactMap { key -> (String, [DictionaryEntry])? in
            let entries = try dictionaryNounSingularEntries(for: key)
            return entries.isEmpty ? nil : (key, entries)
        }
        guard candidates.count == 1, let candidate = candidates.first else { return [] }
        let classification = try dictionaryClassification(for: candidate.0)
        return candidate.1.filter { classification.canOwnLinkedPlurals(gender: $0.gender) }
    }

    private func dictionaryPluralEntries(for entry: DictionaryEntry) throws -> [DictionaryEntry] {
        guard entry.kind == .noun, entry.gender != .plural else { return [] }
        let classification = try dictionaryClassification(for: entry.german)
        guard classification.canOwnLinkedPlurals(gender: entry.gender) else { return [] }
        let lemmaKey = dictionaryGroupingTerm(entry.german)
        let relationStatement = try prepare("""
            SELECT DISTINCT candidate.form
            FROM dictionary_inflections AS candidate
            WHERE candidate.lemma_key = ?
              AND candidate.kind = 'noun'
              AND instr(',' || candidate.tags || ',', ',plural,') > 0
            ORDER BY candidate.form
            """)
        defer { sqlite3_finalize(relationStatement) }
        bind(lemmaKey, to: 1, in: relationStatement)
        var pluralKeys: [String] = []
        while true {
            let step = sqlite3_step(relationStatement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw sqliteError() }
            let pluralKey = text(relationStatement, 0)
            let activeLemmas = try dictionaryNounLemmaKeys(forPluralForm: pluralKey)
            if activeLemmas == [lemmaKey] { pluralKeys.append(pluralKey) }
        }

        let entrySQL = """
            SELECT id, german, english, raw_german, raw_english,
                   kind, gender, usage, source, translation_language,
                   explanation, grammar, subject
            FROM dictionary_entries
            WHERE kind = 'noun' AND gender = 'plural' AND normalized_german = ?
            ORDER BY id
            """
        var result: [DictionaryEntry] = []
        var seenIDs = Set<Int64>()
        for pluralKey in pluralKeys {
            let statement = try prepare(entrySQL)
            defer { sqlite3_finalize(statement) }
            bind(DictCCParser.normalized(pluralKey), to: 1, in: statement)
            for plural in try readEntries(statement)
            where dictionaryGroupingTerm(plural.german) == pluralKey {
                if seenIDs.insert(plural.id).inserted { result.append(plural) }
            }
        }
        return result
    }

    private func dictionaryNounLemmaKeys(forPluralForm form: String) throws -> [String] {
        let statement = try prepare("""
            SELECT DISTINCT lemma_key
            FROM dictionary_inflections
            WHERE form = ?
              AND kind = 'noun'
              AND instr(',' || tags || ',', ',plural,') > 0
            ORDER BY lemma_key
            """)
        defer { sqlite3_finalize(statement) }
        bind(form, to: 1, in: statement)
        var result: [String] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else { throw sqliteError() }
            let lemmaKey = text(statement, 0)
            if try !dictionaryNounSingularEntries(for: lemmaKey).isEmpty {
                result.append(lemmaKey)
            }
        }
    }

    private func dictionaryNounSingularEntries(for lemmaKey: String) throws -> [DictionaryEntry] {
        let statement = try prepare("""
            SELECT id, german, english, raw_german, raw_english,
                   kind, gender, usage, source, translation_language,
                   explanation, grammar, subject
            FROM dictionary_entries
            WHERE kind = 'noun' AND gender != 'plural' AND normalized_german = ?
            ORDER BY CASE translation_language WHEN 'en' THEN 0 WHEN 'ru' THEN 1 ELSE 2 END, id
            """)
        defer { sqlite3_finalize(statement) }
        bind(DictCCParser.normalized(lemmaKey), to: 1, in: statement)
        var seenGroups = Set<DictionaryGroupKey>()
        return try readEntries(statement).filter {
            dictionaryGroupingTerm($0.german) == lemmaKey
        }.filter {
            seenGroups.insert(DictionaryGroupKey($0)).inserted
        }
    }

    private func dictionaryExplanations(for entry: DictionaryEntry) throws -> [DictionaryExplanation] {
        let statement = try prepare("""
            SELECT explanation, source
            FROM dictionary_explanations
            WHERE german_key = ? AND kind = ?
            ORDER BY sort_order, id
            """)
        defer { sqlite3_finalize(statement) }
        bind(dictionaryGroupingTerm(entry.german), to: 1, in: statement)
        bind(entry.kind.rawValue, to: 2, in: statement)
        var result: [DictionaryExplanation] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else { throw sqliteError() }
            result.append(.init(text: text(statement, 0), source: text(statement, 1)))
        }
    }

    private func dictionaryReference(for german: String) throws -> DictionaryReference {
        let key = dictionaryGroupingTerm(german)
        let entryStatement = try prepare("""
            SELECT ipa, etymology, source
            FROM dictionary_reference_entries
            WHERE german_key = ?
            ORDER BY word = ? COLLATE NOCASE DESC, id
            """)
        defer { sqlite3_finalize(entryStatement) }
        bind(key, to: 1, in: entryStatement)
        bind(german, to: 2, in: entryStatement)
        var ipa: String?
        var etymology: String?
        var sources: [String] = []
        while true {
            let step = sqlite3_step(entryStatement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw sqliteError() }
            if ipa == nil { ipa = nullableText(entryStatement, 0) }
            if etymology == nil { etymology = nullableText(entryStatement, 1) }
            let source = text(entryStatement, 2)
            if !sources.contains(source) { sources.append(source) }
        }

        let relatedStatement = try prepare("""
            SELECT related_word, relation, source
            FROM dictionary_related_forms
            WHERE german_key = ?
            ORDER BY relation, related_word COLLATE NOCASE
            """)
        defer { sqlite3_finalize(relatedStatement) }
        bind(key, to: 1, in: relatedStatement)
        var relatedForms: [DictionaryRelatedForm] = []
        while true {
            let step = sqlite3_step(relatedStatement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw sqliteError() }
            let source = text(relatedStatement, 2)
            relatedForms.append(.init(
                word: text(relatedStatement, 0),
                relation: text(relatedStatement, 1),
                source: source
            ))
            if !sources.contains(source) { sources.append(source) }
        }
        return .init(ipa: ipa, etymology: etymology, relatedForms: relatedForms, sources: sources)
    }

    private func dictionaryForms(for german: String, kind: WordKind) throws -> [DictionaryForm] {
        let lemmaKey = dictionaryGroupingTerm(GermanMorphology.inflectionLemma(for: german))
        guard !lemmaKey.isEmpty else { return [] }
        let statement = try prepare("""
            SELECT form, tags, source
            FROM dictionary_inflections
            WHERE lemma_key = ? AND kind = ?
            ORDER BY tags, form, source
            """)
        defer { sqlite3_finalize(statement) }
        bind(lemmaKey, to: 1, in: statement)
        bind(kind.rawValue, to: 2, in: statement)
        var result: [DictionaryForm] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else { throw sqliteError() }
            result.append(.init(
                form: text(statement, 0),
                tags: lectorTags(text(statement, 1)),
                source: text(statement, 2)
            ))
        }
    }

    private func readCards(_ statement: OpaquePointer?) throws -> [PersonalCard] {
        var result: [PersonalCard] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else { throw sqliteError() }
            let dictionaryID = sqlite3_column_type(statement, 1) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 1)
            let lastReviewed = sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 11))
            let indexedEntry = try dictionaryID.flatMap { try dictionaryEntry(id: $0) }
            let storedGerman = text(statement, 2)
            let storedKind = WordKind(rawValue: text(statement, 5)) ?? .other
            let storedMeanings = nullableText(statement, 18).flatMap {
                try? JSONDecoder().decode([DictionaryMeaning].self, from: Data($0.utf8))
            }
            result.append(.init(
                id: sqlite3_column_int64(statement, 0),
                dictionaryEntryID: dictionaryID,
                german: indexedEntry?.german ?? storedGerman,
                english: indexedEntry?.english ?? text(statement, 3),
                kind: indexedEntry?.kind ?? storedKind,
                gender: indexedEntry?.gender ?? Gender(rawValue: text(statement, 6)) ?? .unknown,
                rawGerman: indexedEntry?.rawGerman ?? text(statement, 4),
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
                isSuspended: sqlite3_column_int(statement, 17) != 0,
                pluralForms: indexedEntry?.pluralForms ?? [],
                forms: try indexedEntry?.forms ?? dictionaryForms(for: storedGerman, kind: storedKind),
                meanings: indexedEntry?.meanings ?? storedMeanings
            ))
        }
    }

    private func meaningsJSON(_ meanings: [DictionaryMeaning]) throws -> String {
        let data = try JSONEncoder().encode(meanings)
        guard let result = String(data: data, encoding: .utf8) else {
            throw LocalStoreError.sqlite("Could not encode saved translations")
        }
        return result
    }

    private func readSentences(_ statement: OpaquePointer?) throws -> [SavedSentence] {
        let decoder = JSONDecoder()
        var result: [SavedSentence] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else { throw sqliteError() }
            let sourceListID = sqlite3_column_type(statement, 3) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(statement, 3)
            let tokenData = Data(text(statement, 5).utf8)
            let tokens = (try? decoder.decode([SentenceToken].self, from: tokenData))
                ?? SentenceTokenizer.tokens(in: text(statement, 1))
            let analysis = nullableText(statement, 6).flatMap {
                try? decoder.decode(SentenceAnalysis.self, from: Data($0.utf8))
            }
            result.append(.init(
                id: sqlite3_column_int64(statement, 0),
                german: text(statement, 1),
                translation: text(statement, 2),
                sourceListID: sourceListID,
                sourceListName: text(statement, 4),
                tokens: tokens,
                analysis: analysis,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7))
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

    private func bindNullableSourceText(
        _ sourceStatement: OpaquePointer?,
        column: Int32,
        to index: Int32,
        in destinationStatement: OpaquePointer?
    ) {
        guard let value = sqlite3_column_text(sourceStatement, column) else {
            sqlite3_bind_null(destinationStatement, index)
            return
        }
        let string = String(cString: value).trimmingCharacters(in: .whitespacesAndNewlines)
        if string.isEmpty {
            sqlite3_bind_null(destinationStatement, index)
        } else {
            bind(string, to: index, in: destinationStatement)
        }
    }

    private func escapedLike(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private func detectDictionaryFormat(in handle: FileHandle) throws -> DictionaryFormat {
        guard let sample = try handle.read(upToCount: 4_194_304),
              let text = String(data: sample, encoding: .utf8) else {
            return .init(germanFirst: true, language: .english)
        }
        let header = text.prefix(2_000).uppercased()
        if header.contains("DE-RU VOCABULARY DATABASE") {
            return .init(germanFirst: true, language: .russian)
        }
        if header.contains("RU-DE VOCABULARY DATABASE") {
            return .init(germanFirst: false, language: .russian)
        }
        if header.contains("DE-EN VOCABULARY DATABASE") {
            return .init(germanFirst: true, language: .english)
        }
        if header.contains("EN-DE VOCABULARY DATABASE") {
            return .init(germanFirst: false, language: .english)
        }
        var firstColumnTags = 0
        var secondColumnTags = 0
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 2 else { continue }
            firstColumnTags += germanGrammarTagCount(in: columns[0])
            secondColumnTags += germanGrammarTagCount(in: columns[1])
        }
        return .init(germanFirst: firstColumnTags >= secondColumnTags, language: .english)
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

    private static func sourceTableExists(_ table: String, in database: OpaquePointer?) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw LocalStoreError.invalidExplanationDatabase
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, table, -1, transient)
        let step = sqlite3_step(statement)
        guard step == SQLITE_ROW || step == SQLITE_DONE else {
            throw LocalStoreError.invalidExplanationDatabase
        }
        return step == SQLITE_ROW
    }

    private static func sourceTable(
        _ table: String,
        hasColumn column: String,
        in database: OpaquePointer?
    ) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else {
            throw LocalStoreError.invalidExplanationDatabase
        }
        defer { sqlite3_finalize(statement) }
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return false }
            guard step == SQLITE_ROW else { throw LocalStoreError.invalidExplanationDatabase }
            guard let value = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: value) == column { return true }
        }
    }

}

private struct DictionaryGroupKey: Hashable {
    let german: String
    let kind: WordKind
    let gender: Gender?

    init(_ entry: DictionaryEntry) {
        german = dictionaryGroupingTerm(entry.german)
        kind = entry.kind
        gender = entry.kind == .noun ? entry.gender : nil
    }
}

private struct DictionarySearchHit {
    let entry: DictionaryEntry
    let preference: Int
    let groupSize: Int
    let termIndex: Int
    let ordinal: Int

    func sortsBefore(_ other: DictionarySearchHit) -> Bool {
        if preference != other.preference { return preference < other.preference }
        if termIndex != other.termIndex { return termIndex < other.termIndex }
        if entry.kind == .noun,
           other.entry.kind == .noun,
           dictionaryGroupingTerm(entry.german) == dictionaryGroupingTerm(other.entry.german),
           groupSize != other.groupSize {
            return groupSize > other.groupSize
        }
        return ordinal < other.ordinal
    }
}

private struct DictionaryClassification {
    let preferredKind: WordKind?
    let nounGender: Gender?
    let hasDirectKindEvidence: Bool
    private let directKindCounts: [WordKind: Int]
    private let nounGenderCounts: [Gender: Int]
    private let linkedPluralGender: Gender?

    init(
        directKindCounts: [WordKind: Int],
        lectorKindCounts: [WordKind: Int],
        nounGenderCounts: [Gender: Int]
    ) {
        self.directKindCounts = directKindCounts
        self.nounGenderCounts = nounGenderCounts
        hasDirectKindEvidence = !directKindCounts.isEmpty
        preferredKind = Self.preferredKind(
            direct: directKindCounts,
            lector: lectorKindCounts
        )
        nounGender = nounGenderCounts.count == 1 ? nounGenderCounts.keys.first : nil
        linkedPluralGender = Self.uniqueWinner(in: nounGenderCounts)
    }

    func groupSize(for entry: DictionaryEntry) -> Int {
        if entry.kind == .noun {
            return max(nounGenderCounts[entry.gender, default: 0], 1)
        }
        if entry.kind == .adjective {
            return max(
                directKindCounts[.adjective, default: 0] + directKindCounts[.adverb, default: 0],
                1
            )
        }
        return max(directKindCounts[entry.kind, default: 0], 1)
    }

    func canOwnLinkedPlurals(gender: Gender) -> Bool {
        nounGenderCounts.isEmpty || linkedPluralGender == gender
    }

    private static func preferredKind(
        direct: [WordKind: Int],
        lector: [WordKind: Int]
    ) -> WordKind? {
        let direct = collapsingAdjectiveAndAdverb(direct)
        let lector = collapsingAdjectiveAndAdverb(lector)
        if let winner = uniqueWinner(in: direct) { return winner }
        if !direct.isEmpty {
            let maximum = direct.values.max()!
            let tied = Set(direct.filter { $0.value == maximum }.map(\.key))
            let overlap = tied.intersection(lector.keys)
            if overlap.count == 1 { return overlap.first }
            let lectorAmongTied = lector.filter { tied.contains($0.key) }
            return uniqueWinner(in: lectorAmongTied)
        }
        return uniqueWinner(in: lector)
    }

    private static func collapsingAdjectiveAndAdverb(
        _ counts: [WordKind: Int]
    ) -> [WordKind: Int] {
        guard counts[.adjective] != nil else { return counts }
        var result = counts
        result[.adjective, default: 0] += result.removeValue(forKey: .adverb) ?? 0
        return result
    }

    private static func uniqueWinner<Key: Hashable>(in counts: [Key: Int]) -> Key? {
        guard let maximum = counts.values.max() else { return nil }
        let winners = counts.filter { $0.value == maximum }.map(\.key)
        return winners.count == 1 ? winners[0] : nil
    }
}

private struct DictionaryInflectionSearchLink: Equatable {
    let lemmaKey: String
    let searchTerm: String
    let kind: WordKind
    let tags: Set<String>

    var isDegree: Bool {
        tags.contains("comparative") || tags.contains("superlative")
    }
}

private struct DictionaryFormat {
    let germanFirst: Bool
    let language: TranslationLanguage
}

private struct DictionaryReference {
    let ipa: String?
    let etymology: String?
    let relatedForms: [DictionaryRelatedForm]
    let sources: [String]
}

private func wordKind(forLectorPartOfSpeech value: String) -> WordKind {
    switch value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
    case "noun": .noun
    case "verb": .verb
    case "adj": .adjective
    case "adv": .adverb
    case "pron", "pronoun": .pronoun
    case "det", "determiner": .determiner
    case "prep", "preposition": .preposition
    case "conj", "conjunction": .conjunction
    case "pres-p", "present_participle": .presentParticiple
    case "past-p", "past_participle": .pastParticiple
    case "prefix": .prefix
    case "suffix": .suffix
    case "phrase", "prep_phrase", "proverb": .phrase
    default: .other
    }
}

private func dictionaryGroupingTerm(_ value: String) -> String {
    let term = value
        .precomposedStringWithCanonicalMapping
        .lowercased(with: Locale(identifier: "de_DE"))
        .trimmingCharacters(in: .whitespacesAndNewlines)
    for prefix in dictionaryValencyPrefixes where term.hasPrefix(prefix) {
        let remainder = String(term.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainder.isEmpty, !remainder.contains(where: { $0.isWhitespace }) {
            return remainder
        }
    }
    return term
}

private let dictionaryValencyPrefixes = [
    "jdn./etw. ", "jdm./etw. ", "(jdn./etw.) ",
    "jdn. ", "jdm. ", "etw. ", "(jdn.) ", "(jdm.) ", "(etw.) "
]

private func dictionaryGroupingSpellings(for groupingTerm: String) -> [String] {
    [groupingTerm] + dictionaryValencyPrefixes.map { $0 + groupingTerm }
}

private func dictionaryCanonicalEntrySortsBefore(
    _ lhs: DictionaryEntry,
    _ rhs: DictionaryEntry
) -> Bool {
    let lhsPlural = lhs.gender == .plural
    let rhsPlural = rhs.gender == .plural
    if lhsPlural != rhsPlural { return !lhsPlural }
    let groupTerm = dictionaryGroupingTerm(lhs.german)
    let lhsBare = lhs.german.precomposedStringWithCanonicalMapping
        .lowercased(with: Locale(identifier: "de_DE")) == groupTerm
    let rhsBare = rhs.german.precomposedStringWithCanonicalMapping
        .lowercased(with: Locale(identifier: "de_DE")) == groupTerm
    if lhsBare != rhsBare { return lhsBare }
    let lhsLanguage = lhs.meanings.first?.language ?? .english
    let rhsLanguage = rhs.meanings.first?.language ?? .english
    if lhsLanguage != rhsLanguage { return lhsLanguage == .english }
    return lhs.id < rhs.id
}

private func dictionaryEvidenceKind(for entry: DictionaryEntry) -> WordKind {
    dictionaryEvidenceKind(
        storedKind: entry.kind,
        rawGerman: entry.rawGerman,
        rawEnglish: entry.rawEnglish,
        grammar: entry.meanings.first?.grammar,
        language: entry.meanings.first?.language ?? .english
    )
}

private func dictionaryEvidenceKind(
    storedKind: WordKind,
    rawGerman: String,
    rawEnglish: String,
    grammar: String?,
    language: TranslationLanguage
) -> WordKind {
    guard storedKind == .verb,
          language == .english,
          (grammar ?? "").isEmpty,
          !DictCCParser.hasGermanVerbMarker(rawGerman),
          !DictCCParser.looksLikeEnglishInfinitive(rawEnglish) else {
        return storedKind
    }
    return DictCCParser.cleanedTerm(rawGerman).contains(where: { $0.isWhitespace })
        ? .phrase
        : .other
}

private extension DictionaryEntry {
    func reclassified(kind: WordKind, gender: Gender) -> DictionaryEntry {
        DictionaryEntry(
            id: id,
            german: german,
            english: english,
            rawGerman: rawGerman,
            rawEnglish: rawEnglish,
            kind: kind,
            gender: gender,
            usage: usage,
            source: source,
            pluralForms: pluralForms,
            meanings: meanings,
            explanations: explanations,
            forms: forms,
            ipa: ipa,
            etymology: etymology,
            relatedForms: relatedForms
        )
    }
}

private func lectorTags(_ value: String) -> Set<String> {
    Set(value.split(separator: ",").map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty })
}

private func lectorInflectionKind(tags: Set<String>, partsOfSpeech: String) -> WordKind {
    if !tags.isDisjoint(with: ["inflection-template", "table-tags"]) { return .other }
    if !tags.isDisjoint(with: ["comparative", "superlative"]) { return .adjective }
    let declaredKinds = partsOfSpeech.split(separator: ",").map {
        wordKind(forLectorPartOfSpeech: String($0))
    }.filter { $0 != .other }
    if declaredKinds.count == 1 { return declaredKinds[0] }

    let verbTags: Set<String> = [
        "auxiliary", "first-person", "second-person", "third-person", "present",
        "preterite", "future", "past", "indicative", "subjunctive", "imperative",
        "participle", "infinitive"
    ]
    if !tags.isDisjoint(with: verbTags) { return .verb }
    if tags.contains("noun") || declaredKinds.contains(.noun) { return .noun }
    if declaredKinds.contains(.adjective) { return .adjective }
    return declaredKinds.first ?? .other
}

private func lectorDegreeInflection(word: String, gloss: String) -> (lemma: String, tag: String)? {
    let prefixes = [
        ("comparative degree of ", "comparative"),
        ("superlative degree of ", "superlative")
    ]
    guard let (prefix, tag) = prefixes.first(where: { gloss.hasPrefix($0.0) }) else { return nil }
    let remainder = gloss.dropFirst(prefix.count)
    let terminators = CharacterSet(charactersIn: ";:()\"“”")
    let lemma = remainder.prefix { character in
        character.unicodeScalars.allSatisfy { !terminators.contains($0) }
    }.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !lemma.isEmpty else { return nil }
    return (lemma, tag)
}
