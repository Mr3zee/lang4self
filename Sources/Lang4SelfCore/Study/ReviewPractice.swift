import Foundation

public enum ReviewTestMode: String, CaseIterable, Identifiable, Sendable {
    case flashcard
    case writing
    case speaking
    case gender
    case germanToEnglish
    case germanToEnglishWriting
    case conjugation
    case plural
    case listeningWords

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .flashcard: "English → German"
        case .writing: "Writing"
        case .speaking: "Speaking"
        case .gender: "Gender"
        case .germanToEnglish: "German → English"
        case .germanToEnglishWriting: "German → English · Writing"
        case .conjugation: "Conjugation"
        case .plural: "Plural"
        case .listeningWords: "Listening words"
        }
    }

    public var requiresWrittenAnswer: Bool {
        switch self {
        case .writing, .germanToEnglishWriting, .conjugation, .plural, .listeningWords: true
        case .flashcard, .speaking, .gender, .germanToEnglish: false
        }
    }

    public var usesSpeech: Bool { self == .speaking }
    public var usesGenderChoices: Bool { self == .gender }
    public var usesTranslationCarousel: Bool {
        self == .flashcard || self == .writing || self == .speaking
    }

    public func advanced(by offset: Int) -> ReviewTestMode {
        guard let index = Self.allCases.firstIndex(of: self) else { return self }
        let count = Self.allCases.count
        return Self.allCases[(index + offset % count + count) % count]
    }
}

public struct ReviewChallenge: Equatable, Sendable {
    public let mode: ReviewTestMode
    public let prompt: String
    public let acceptedAnswers: [String]
    public let conjugationPronoun: String?

    public init?(
        card: PersonalCard,
        mode: ReviewTestMode,
        conjugationIndex: Int? = nil
    ) {
        self.mode = mode
        switch mode {
        case .flashcard, .writing, .speaking:
            guard !card.german.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !card.english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            prompt = card.english
            acceptedAnswers = mode == .speaking
                ? Self.spokenGermanAnswers(for: card)
                : [card.german]
            conjugationPronoun = nil

        case .listeningWords:
            guard !card.german.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            prompt = card.german
            acceptedAnswers = [card.german]
            conjugationPronoun = nil

        case .germanToEnglish, .germanToEnglishWriting:
            let answers = Self.englishAnswers(for: card)
            guard !answers.isEmpty else { return nil }
            prompt = card.german
            acceptedAnswers = answers
            conjugationPronoun = nil

        case .gender:
            guard card.kind == .noun,
                  [.masculine, .feminine, .neuter].contains(card.gender)
            else { return nil }
            prompt = card.german
            acceptedAnswers = [card.gender.article]
            conjugationPronoun = nil

        case .conjugation:
            guard card.kind == .verb else { return nil }
            let conjugations = Self.presentTenseConjugations(for: card)
            guard !conjugations.isEmpty else { return nil }
            let rawIndex = conjugationIndex ?? Int(card.id.magnitude % UInt64(conjugations.count))
            let index = (rawIndex % conjugations.count + conjugations.count) % conjugations.count
            let conjugation = conjugations[index]
            prompt = card.german
            let subjectPronouns = conjugation.pronoun
                .split(separator: "/")
                .map(String.init)
            acceptedAnswers = (
                conjugation.forms
                    + subjectPronouns.flatMap { pronoun in
                        conjugation.forms.map { "\(pronoun) \($0)" }
                    }
            ).uniquedReviewAnswers()
            conjugationPronoun = conjugation.pronoun

        case .plural:
            guard card.kind == .noun else { return nil }
            let grammaticalCases: Set<String> = ["accusative", "dative", "genitive", "nominative"]
            let importedAnswers = card.forms.compactMap { form -> String? in
                guard form.tags.contains("plural"),
                      form.tags.contains("nominative") || form.tags.isDisjoint(with: grammaticalCases)
                else { return nil }
                return form.form
            }
            let answers = (
                card.pluralForms
                    + importedAnswers
                    + GermanMorphology.pluralForms(for: Self.entry(for: card))
            ).uniquedReviewAnswers()
            guard !answers.isEmpty else { return nil }
            prompt = card.german
            acceptedAnswers = answers
            conjugationPronoun = nil
        }
    }

    public func accepts(_ answer: String) -> Bool {
        let candidate = Self.comparable(answer)
        guard !candidate.isEmpty else { return false }
        return acceptedAnswers.contains { Self.comparable($0) == candidate }
    }

    private static func englishAnswers(for card: PersonalCard) -> [String] {
        let meaningAnswers = card.resolvedMeanings
            .filter { $0.language == .english }
            .map(\.translation)
        if card.meanings != nil { return meaningAnswers.uniquedReviewAnswers() }
        let fallbackAnswers = card.english
            .split(separator: ";", omittingEmptySubsequences: true)
            .map(String.init)
        return (meaningAnswers + fallbackAnswers).uniquedReviewAnswers()
    }

    private static func spokenGermanAnswers(for card: PersonalCard) -> [String] {
        var answers = [card.german]
        if card.kind == .noun,
           [.masculine, .feminine, .neuter].contains(card.gender) {
            answers.append("\(card.gender.article) \(card.german)")
        }
        return answers
    }

    private static func presentTenseConjugations(
        for card: PersonalCard
    ) -> [(pronoun: String, forms: [String])] {
        let present = GermanMorphology.info(for: entry(for: card)).rows
            .first { $0.label == "Present" }?.value ?? ""
        return present.split(separator: "·").compactMap { item in
            let components = item
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
                .map(String.init)
            guard components.count == 2 else { return nil }
            return (components[0], slashAlternatives(in: components[1]))
        }
    }

    private static func slashAlternatives(in value: String) -> [String] {
        let words = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let index = words.firstIndex(where: { $0.contains("/") }) else { return [value] }
        return words[index].split(separator: "/").map { alternative in
            var result = words
            result[index] = String(alternative)
            return result.joined(separator: " ")
        }
    }

    private static func entry(for card: PersonalCard) -> DictionaryEntry {
        DictionaryEntry(
            id: card.dictionaryEntryID ?? 0,
            german: card.german,
            english: card.english,
            rawGerman: card.rawGerman,
            kind: card.kind,
            gender: card.gender,
            source: "My words",
            pluralForms: card.pluralForms,
            meanings: card.resolvedMeanings,
            forms: card.forms
        )
    }

    private static func comparable(_ value: String) -> String {
        let ignoredEdges = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return value
            .precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "de_DE"))
            .trimmingCharacters(in: ignoredEdges)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

private extension Array where Element == String {
    func uniquedReviewAnswers() -> [String] {
        var seen = Set<String>()
        return compactMap { answer in
            let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed
                .precomposedStringWithCanonicalMapping
                .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard !trimmed.isEmpty, seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }
}
