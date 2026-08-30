import Foundation

public enum WordKind: String, Codable, CaseIterable, Sendable {
    case noun
    case verb
    case adjective
    case adverb
    case pronoun
    case determiner
    case preposition
    case conjunction
    case presentParticiple = "present_participle"
    case pastParticiple = "past_participle"
    case prefix
    case suffix
    case phrase
    case other

    public var label: String {
        switch self {
        case .noun: "Noun"
        case .verb: "Verb"
        case .adjective: "Adjective"
        case .adverb: "Adverb"
        case .pronoun: "Pronoun"
        case .determiner: "Determiner"
        case .preposition: "Preposition"
        case .conjunction: "Conjunction"
        case .presentParticiple: "Present participle"
        case .pastParticiple: "Past participle"
        case .prefix: "Prefix"
        case .suffix: "Suffix"
        case .phrase: "Phrase"
        case .other: "Word"
        }
    }
}

public enum Gender: String, Codable, CaseIterable, Sendable {
    case masculine
    case feminine
    case neuter
    case plural
    case unknown

    public var article: String {
        switch self {
        case .masculine: "der"
        case .feminine: "die"
        case .neuter: "das"
        case .plural: "die (plural)"
        case .unknown: ""
        }
    }
}

public enum TranslationLanguage: String, Codable, CaseIterable, Sendable {
    case english = "en"
    case russian = "ru"

    public var label: String {
        switch self {
        case .english: "English"
        case .russian: "Russian"
        }
    }

    public var shortLabel: String { rawValue.uppercased() }
}

public struct DictionaryMeaning: Identifiable, Hashable, Codable, Sendable {
    public var id: String {
        "\(language.rawValue):\(gender.rawValue):\(english.lowercased()):\(usage ?? ""):\(explanation ?? ""):\(grammar ?? ""):\(subject ?? ""):\(rawGerman ?? "")"
    }

    public let english: String
    public let rawEnglish: String
    public let rawGerman: String?
    public let language: TranslationLanguage
    public let gender: Gender
    public let usage: String?
    public let explanation: String?
    public let grammar: String?
    public let subject: String?

    public var translation: String { english }
    public var rawTranslation: String { rawEnglish }
    public var germanMetadata: [String] { Self.annotations(in: rawGerman ?? "") }
    public var translationMetadata: [String] { Self.annotations(in: rawEnglish) }
    public var distinctExplanation: String? {
        guard let explanation else { return nil }
        let trimmed = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              Self.comparableText(trimmed) != Self.comparableText(translation) else { return nil }
        return trimmed
    }

    public init(
        english: String,
        rawEnglish: String? = nil,
        rawGerman: String? = nil,
        language: TranslationLanguage = .english,
        gender: Gender = .unknown,
        usage: String? = nil,
        explanation: String? = nil,
        grammar: String? = nil,
        subject: String? = nil
    ) {
        self.english = english
        self.rawEnglish = rawEnglish ?? english
        self.rawGerman = rawGerman
        self.language = language
        self.gender = gender
        self.usage = usage
        self.explanation = explanation
        self.grammar = grammar
        self.subject = subject
    }

    private static func comparableText(_ value: String) -> String {
        comparableDictionaryText(value)
    }

    private static func annotations(in value: String) -> [String] {
        let pairs: [(Character, Character)] = [("[", "]"), ("{", "}"), ("<", ">")]
        var result: [String] = []
        for (opening, closing) in pairs {
            var remainder = value[...]
            while let start = remainder.firstIndex(of: opening),
                  let end = remainder[remainder.index(after: start)...].firstIndex(of: closing) {
                let content = remainder[remainder.index(after: start)..<end]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty, !result.contains(content) { result.append(content) }
                remainder = remainder[remainder.index(after: end)...]
            }
        }
        return result
    }
}

public struct DictionaryExplanation: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(source):\(text)" }
    public let text: String
    public let source: String

    public init(text: String, source: String) {
        self.text = text
        self.source = source
    }
}

public struct DictionaryForm: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(source):\(form):\(tags.sorted().joined(separator: ","))" }
    public let form: String
    public let tags: Set<String>
    public let source: String

    public init(form: String, tags: Set<String>, source: String = "Wiktionary via Lector") {
        self.form = form
        self.tags = tags
        self.source = source
    }
}

public struct DictionaryRelatedForm: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(source):\(relation):\(word)" }
    public let word: String
    public let relation: String
    public let source: String

    public init(word: String, relation: String, source: String = "Wiktionary via Lector") {
        self.word = word
        self.relation = relation
        self.source = source
    }
}

public struct DictionaryEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: Int64
    public let german: String
    public let english: String
    public let rawGerman: String
    public let rawEnglish: String
    public let kind: WordKind
    public let gender: Gender
    public let usage: String?
    public let source: String
    public let pluralForms: [String]
    public let meanings: [DictionaryMeaning]
    public let explanations: [DictionaryExplanation]
    public let forms: [DictionaryForm]
    public let ipa: String?
    public let etymology: String?
    public let relatedForms: [DictionaryRelatedForm]

    public var translations: String { english }
    public var distinctExplanations: [DictionaryExplanation] {
        let meaningText = Set(meanings.flatMap { meaning in
            [meaning.translation, meaning.distinctExplanation].compactMap { $0 }.map(comparableDictionaryText)
        })
        var seen = Set<String>()
        return explanations.filter { explanation in
            let comparable = comparableDictionaryText(explanation.text)
            return !comparable.isEmpty
                && !meaningText.contains(comparable)
                && seen.insert(comparable).inserted
        }
    }

    public init(
        id: Int64 = 0,
        german: String,
        english: String,
        rawGerman: String? = nil,
        rawEnglish: String? = nil,
        kind: WordKind = .other,
        gender: Gender = .unknown,
        usage: String? = nil,
        source: String = "dict.cc",
        pluralForms: [String] = [],
        explanation: String? = nil,
        translationLanguage: TranslationLanguage = .english,
        meanings: [DictionaryMeaning]? = nil,
        explanations: [DictionaryExplanation] = [],
        forms: [DictionaryForm] = [],
        ipa: String? = nil,
        etymology: String? = nil,
        relatedForms: [DictionaryRelatedForm] = []
    ) {
        let resolvedMeanings = meanings ?? [DictionaryMeaning(
            english: english,
            rawEnglish: rawEnglish,
            rawGerman: rawGerman,
            language: translationLanguage,
            gender: gender,
            usage: usage,
            explanation: explanation
        )]
        self.id = id
        self.german = german
        self.english = resolvedMeanings.map(\.english).joined(separator: "; ")
        self.rawGerman = rawGerman ?? german
        self.rawEnglish = resolvedMeanings.map(\.rawEnglish).joined(separator: "; ")
        self.kind = kind
        self.gender = gender
        self.usage = usage
        self.source = source
        self.pluralForms = pluralForms
        self.meanings = resolvedMeanings
        self.explanations = explanations
        self.forms = forms
        self.ipa = ipa
        self.etymology = etymology
        self.relatedForms = relatedForms
    }
}

private func comparableDictionaryText(_ value: String) -> String {
    let ignoredEdges = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    return value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .trimmingCharacters(in: ignoredEdges)
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
        .lowercased()
}

public struct WordInfo: Hashable, Codable, Sendable {
    public struct Row: Identifiable, Hashable, Codable, Sendable {
        public var id: String { "\(label):\(value)" }
        public let label: String
        public let value: String

        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    public let headline: String
    public let kind: WordKind
    public let gender: Gender
    public let separablePrefix: String?
    public let stem: String
    public let rows: [Row]
    public let isEstimated: Bool

    public init(
        headline: String,
        kind: WordKind,
        gender: Gender,
        separablePrefix: String?,
        stem: String,
        rows: [Row],
        isEstimated: Bool
    ) {
        self.headline = headline
        self.kind = kind
        self.gender = gender
        self.separablePrefix = separablePrefix
        self.stem = stem
        self.rows = rows
        self.isEstimated = isEstimated
    }
}
