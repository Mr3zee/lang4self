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
    public let analysis: SentenceAnalysis?

    public init(
        id: UUID = UUID(),
        german: String,
        translation: String,
        tokens: [SentenceToken],
        analysis: SentenceAnalysis? = nil
    ) {
        self.id = id
        self.german = german
        self.translation = translation
        self.tokens = tokens
        self.analysis = analysis
    }

    public func withAnalysis(_ analysis: SentenceAnalysis) -> SentenceDraft {
        SentenceDraft(
            id: id,
            german: german,
            translation: translation,
            tokens: tokens,
            analysis: analysis
        )
    }
}

public struct SavedSentence: Hashable, Identifiable, Sendable {
    public let id: Int64
    public let german: String
    public let translation: String
    public let sourceListID: WordList.ID?
    public let sourceListName: String
    public let tokens: [SentenceToken]
    public let analysis: SentenceAnalysis?
    public let createdAt: Date

    public init(
        id: Int64,
        german: String,
        translation: String,
        sourceListID: WordList.ID?,
        sourceListName: String,
        tokens: [SentenceToken],
        analysis: SentenceAnalysis? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.german = german
        self.translation = translation
        self.sourceListID = sourceListID
        self.sourceListName = sourceListName
        self.tokens = tokens
        self.analysis = analysis
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

    /// Reuses the lexical token linked to a detached prefix or determiner, so
    /// every part of the selection opens the same dictionary entry.
    public static func contextualLookupToken(
        for token: SentenceToken,
        in tokens: [SentenceToken],
        nounTokenIndices: Set<Int> = []
    ) -> SentenceToken {
        if let anchor = separableVerbAnchor(for: token, in: tokens), anchor.index != token.index {
            return SentenceToken(
                index: token.index,
                surface: token.surface,
                lookupTerm: anchor.lookupTerm,
                cardID: anchor.cardID
            )
        }

        if GermanMorphology.isDeterminer(token.lookupTerm),
           let noun = followingNoun(
               after: token,
               in: tokens,
               nounTokenIndices: nounTokenIndices
           ) {
            return SentenceToken(
                index: token.index,
                surface: token.surface,
                lookupTerm: noun.lookupTerm,
                cardID: noun.cardID
            )
        }
        return token
    }

    public static func relatedTokenIndices(
        for token: SentenceToken,
        in tokens: [SentenceToken],
        nounTokenIndices: Set<Int> = []
    ) -> Set<Int> {
        if let anchor = separableVerbAnchor(for: token, in: tokens),
           let prefix = GermanMorphology.separablePrefix(in: anchor.lookupTerm),
           let detachedPrefix = followingToken(
               after: anchor,
               in: tokens,
               matching: { normalized($0.surface) == normalized(prefix) }
           ) {
            return [anchor.index, detachedPrefix.index]
        }

        if GermanMorphology.isDeterminer(token.lookupTerm),
           let noun = followingNoun(
               after: token,
               in: tokens,
               nounTokenIndices: nounTokenIndices
           ) {
            return [token.index, noun.index]
        }
        if nounTokenIndices.contains(token.index),
           let determiner = precedingDeterminer(
               before: token,
               in: tokens,
               nounTokenIndices: nounTokenIndices
           ) {
            return [determiner.index, token.index]
        }
        return [token.index]
    }

    public static func normalized(_ value: String) -> String {
        lookupTerm(from: value)
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }

    private static func separableVerbAnchor(
        for token: SentenceToken,
        in tokens: [SentenceToken]
    ) -> SentenceToken? {
        let selectedSurface = normalized(token.surface)
        guard !selectedSurface.isEmpty else { return nil }

        if let prefix = GermanMorphology.separablePrefix(in: token.lookupTerm),
           normalized(prefix) != selectedSurface {
            return token
        }

        guard let selectedOffset = tokens.firstIndex(where: { $0.index == token.index }),
              selectedOffset > tokens.startIndex else { return nil }
        for candidate in tokens[..<selectedOffset].reversed() {
            if endsClause(candidate.surface) { break }
            guard let prefix = GermanMorphology.separablePrefix(in: candidate.lookupTerm),
                  normalized(prefix) == selectedSurface else { continue }
            return candidate
        }
        return nil
    }

    private static func followingNoun(
        after token: SentenceToken,
        in tokens: [SentenceToken],
        nounTokenIndices: Set<Int>
    ) -> SentenceToken? {
        guard let offset = tokens.firstIndex(where: { $0.index == token.index }),
              offset < tokens.index(before: tokens.endIndex) else { return nil }
        for candidate in tokens[tokens.index(after: offset)...] {
            if GermanMorphology.isDeterminer(candidate.lookupTerm) { break }
            if nounTokenIndices.contains(candidate.index) { return candidate }
            if endsClause(candidate.surface) { break }
        }
        return nil
    }

    private static func precedingDeterminer(
        before token: SentenceToken,
        in tokens: [SentenceToken],
        nounTokenIndices: Set<Int>
    ) -> SentenceToken? {
        guard let offset = tokens.firstIndex(where: { $0.index == token.index }),
              offset > tokens.startIndex else { return nil }
        for candidate in tokens[..<offset].reversed() {
            if endsClause(candidate.surface) || nounTokenIndices.contains(candidate.index) { break }
            if GermanMorphology.isDeterminer(candidate.lookupTerm) { return candidate }
        }
        return nil
    }

    private static func followingToken(
        after token: SentenceToken,
        in tokens: [SentenceToken],
        matching predicate: (SentenceToken) -> Bool
    ) -> SentenceToken? {
        guard let offset = tokens.firstIndex(where: { $0.index == token.index }),
              offset < tokens.index(before: tokens.endIndex) else { return nil }
        for candidate in tokens[tokens.index(after: offset)...] {
            if predicate(candidate) { return candidate }
            if endsClause(candidate.surface) { break }
        }
        return nil
    }

    private static func endsClause(_ surface: String) -> Bool {
        guard let last = surface.last else { return false }
        return ".!?;:".contains(last)
    }
}
