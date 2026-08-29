import Foundation

public enum WordKind: String, Codable, CaseIterable, Sendable {
    case noun
    case verb
    case adjective
    case adverb
    case phrase
    case other

    public var label: String {
        switch self {
        case .noun: "Noun"
        case .verb: "Verb"
        case .adjective: "Adjective"
        case .adverb: "Adverb"
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

    public init(
        id: Int64 = 0,
        german: String,
        english: String,
        rawGerman: String? = nil,
        rawEnglish: String? = nil,
        kind: WordKind = .other,
        gender: Gender = .unknown,
        usage: String? = nil,
        source: String = "dict.cc"
    ) {
        self.id = id
        self.german = german
        self.english = english
        self.rawGerman = rawGerman ?? german
        self.rawEnglish = rawEnglish ?? english
        self.kind = kind
        self.gender = gender
        self.usage = usage
        self.source = source
    }
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
