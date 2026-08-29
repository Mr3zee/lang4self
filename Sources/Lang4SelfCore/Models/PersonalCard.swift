import Foundation

public enum ReviewRating: Int, CaseIterable, Codable, Sendable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    public var label: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
}

public struct PersonalCard: Identifiable, Hashable, Codable, Sendable {
    public let id: Int64
    public let dictionaryEntryID: Int64?
    public var german: String
    public var english: String
    public var kind: WordKind
    public var gender: Gender
    public var rawGerman: String
    public var notes: String
    public var tags: String
    public var createdAt: Date
    public var dueAt: Date
    public var lastReviewedAt: Date?
    public var intervalDays: Double
    public var easeFactor: Double
    public var repetitions: Int
    public var lapses: Int
    public var isStarred: Bool
    public var isSuspended: Bool

    public init(
        id: Int64 = 0,
        dictionaryEntryID: Int64? = nil,
        german: String,
        english: String,
        kind: WordKind = .other,
        gender: Gender = .unknown,
        rawGerman: String? = nil,
        notes: String = "",
        tags: String = "",
        createdAt: Date = .now,
        dueAt: Date = .now,
        lastReviewedAt: Date? = nil,
        intervalDays: Double = 0,
        easeFactor: Double = 2.5,
        repetitions: Int = 0,
        lapses: Int = 0,
        isStarred: Bool = false,
        isSuspended: Bool = false
    ) {
        self.id = id
        self.dictionaryEntryID = dictionaryEntryID
        self.german = german
        self.english = english
        self.kind = kind
        self.gender = gender
        self.rawGerman = rawGerman ?? german
        self.notes = notes
        self.tags = tags
        self.createdAt = createdAt
        self.dueAt = dueAt
        self.lastReviewedAt = lastReviewedAt
        self.intervalDays = intervalDays
        self.easeFactor = easeFactor
        self.repetitions = repetitions
        self.lapses = lapses
        self.isStarred = isStarred
        self.isSuspended = isSuspended
    }
}

public struct StudyStats: Hashable, Codable, Sendable {
    public let totalCards: Int
    public let dueCards: Int
    public let reviewsToday: Int
    public let streakDays: Int

    public init(totalCards: Int = 0, dueCards: Int = 0, reviewsToday: Int = 0, streakDays: Int = 0) {
        self.totalCards = totalCards
        self.dueCards = dueCards
        self.reviewsToday = reviewsToday
        self.streakDays = streakDays
    }
}
