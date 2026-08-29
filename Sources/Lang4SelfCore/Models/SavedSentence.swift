import Foundation

public struct SentenceToken: Codable, Hashable, Identifiable, Sendable {
    public let index: Int
    public let surface: String
    public let lookupTerm: String
    public let cardID: PersonalCard.ID?

    public var id: Int { index }

    public init(index: Int, surface: String, lookupTerm: String, cardID: PersonalCard.ID? = nil) {
        self.index = index
        self.surface = surface
        self.lookupTerm = lookupTerm
        self.cardID = cardID
    }
}

public struct SentenceDraft: Hashable, Identifiable, Sendable {
    public let id: UUID
    public let german: String
    public let translation: String
    public let tokens: [SentenceToken]

    public init(
        id: UUID = UUID(),
        german: String,
        translation: String,
        tokens: [SentenceToken]
    ) {
        self.id = id
        self.german = german
        self.translation = translation
        self.tokens = tokens
    }
}

public struct SavedSentence: Hashable, Identifiable, Sendable {
    public let id: Int64
    public let german: String
    public let translation: String
    public let sourceListID: WordList.ID?
    public let sourceListName: String
    public let tokens: [SentenceToken]
    public let createdAt: Date

    public init(
        id: Int64,
        german: String,
        translation: String,
        sourceListID: WordList.ID?,
        sourceListName: String,
        tokens: [SentenceToken],
        createdAt: Date
    ) {
        self.id = id
        self.german = german
        self.translation = translation
        self.sourceListID = sourceListID
        self.sourceListName = sourceListName
        self.tokens = tokens
        self.createdAt = createdAt
    }
}

public enum SentenceTokenizer {
    public static func tokens(in sentence: String) -> [SentenceToken] {
        sentence
            .split(whereSeparator: { $0.isWhitespace })
            .enumerated()
            .compactMap { index, part in
                let surface = String(part)
                let lookup = lookupTerm(from: surface)
                guard !lookup.isEmpty else { return nil }
                return SentenceToken(index: index, surface: surface, lookupTerm: lookup)
            }
    }

    public static func lookupTerm(from surface: String) -> String {
        surface.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
    }

    public static func normalized(_ value: String) -> String {
        lookupTerm(from: value)
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }
}
