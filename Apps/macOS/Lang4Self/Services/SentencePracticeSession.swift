import Foundation
import Lang4SelfCore

enum SentenceTestMode: String, CaseIterable, Identifiable {
    case fullSentence
    case vocabularyBlanks
    case listening

    static let configurableCases: [SentenceTestMode] = [.fullSentence, .vocabularyBlanks]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullSentence: "Write full sentence"
        case .vocabularyBlanks: "Fill vocabulary blanks"
        case .listening: "Listening"
        }
    }
}

enum SentencePracticeResult: Equatable {
    case correct
    case incorrect(submittedAnswer: String)
}

struct SentencePracticeItem: Identifiable, Hashable {
    let id: UUID
    let draft: SentenceDraft
    let sourceListName: String

    init(
        id: UUID = UUID(),
        draft: SentenceDraft,
        sourceListName: String
    ) {
        self.id = id
        self.draft = draft
        self.sourceListName = sourceListName
    }

    init(savedSentence: SavedSentence) {
        id = UUID()
        draft = SentenceDraft(
            german: savedSentence.german,
            translation: savedSentence.translation,
            tokens: savedSentence.tokens,
            analysis: savedSentence.analysis
        )
        sourceListName = savedSentence.sourceListName
    }

    var targetTokens: [SentenceToken] {
        draft.tokens.filter { $0.cardID != nil }
    }

    func retried() -> SentencePracticeItem {
        SentencePracticeItem(draft: draft, sourceListName: sourceListName)
    }
}

struct SentencePracticeSession {
    private(set) var mode: SentenceTestMode = .vocabularyBlanks
    private(set) var items: [SentencePracticeItem] = []
    private(set) var currentIndex = 0
    private(set) var result: SentencePracticeResult?
    private(set) var requestedGenerationCount = 0
    private(set) var generatedCount = 0
    private(set) var answeredCount = 0
    private(set) var isGenerating = false
    private(set) var isUpdatingRetry = false
    private(set) var sourceList: WordList?

    var currentItem: SentencePracticeItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    var pendingGenerationCount: Int {
        max(0, requestedGenerationCount - generatedCount)
    }

    var isWaitingForInitialGeneration: Bool {
        currentItem == nil && isGenerating && generatedCount == 0
    }

    var isWaitingForGeneration: Bool {
        currentItem == nil && isGenerating && generatedCount > 0
    }

    var isComplete: Bool {
        currentItem == nil && !isGenerating && (!items.isEmpty || requestedGenerationCount > 0)
    }

    var hasStarted: Bool { sourceList != nil }

    var isActive: Bool { hasStarted && !isComplete }

    mutating func start(
        mode: SentenceTestMode,
        requestedCount: Int,
        retries: [SavedSentence],
        sourceList: WordList
    ) {
        self.mode = mode
        items = retries.reversed().map(SentencePracticeItem.init(savedSentence:))
        currentIndex = 0
        result = nil
        requestedGenerationCount = max(1, requestedCount)
        generatedCount = 0
        answeredCount = 0
        isGenerating = true
        isUpdatingRetry = false
        self.sourceList = sourceList
    }

    mutating func appendGenerated(_ drafts: [SentenceDraft]) {
        guard !drafts.isEmpty else { return }
        let sourceName = sourceList?.name ?? "Selected list"
        items.append(contentsOf: drafts.map {
            SentencePracticeItem(draft: $0, sourceListName: sourceName)
        })
        generatedCount += drafts.count
    }

    mutating func finishGeneration() {
        isGenerating = false
        if items.isEmpty {
            abort()
        }
    }

    @discardableResult
    mutating func submit(answer: String) -> SentencePracticeResult? {
        guard result == nil, let item = currentItem else { return nil }
        let evaluation: SentencePracticeResult
        if SentenceAnswerEvaluator.isCorrect(answer, for: item, mode: mode) {
            evaluation = .correct
        } else {
            evaluation = .incorrect(submittedAnswer: answer)
            items.append(item.retried())
        }
        result = evaluation
        answeredCount += 1
        return evaluation
    }

    mutating func setUpdatingRetry(_ isUpdating: Bool) {
        isUpdatingRetry = isUpdating
    }

    mutating func setMode(_ mode: SentenceTestMode) {
        self.mode = mode
    }

    mutating func advance() {
        guard result != nil, !isUpdatingRetry else { return }
        currentIndex += 1
        result = nil
    }

    mutating func abort() {
        self = SentencePracticeSession()
    }
}

enum SentenceAnswerEvaluator {
    static func usesVocabularyBlanks(
        for item: SentencePracticeItem,
        mode: SentenceTestMode
    ) -> Bool {
        mode == .vocabularyBlanks && !item.targetTokens.isEmpty
    }

    static func isCorrect(
        _ answer: String,
        for item: SentencePracticeItem,
        mode: SentenceTestMode
    ) -> Bool {
        let expected: [String]
        if usesVocabularyBlanks(for: item, mode: mode) {
            expected = item.targetTokens.map { SentenceTokenizer.lookupTerm(from: $0.surface) }
        } else {
            expected = item.draft.tokens.map(\.lookupTerm)
        }
        return normalizedWords(in: answer) == expected.map(normalizedWord)
    }

    private static func normalizedWords(in text: String) -> [String] {
        SentenceTokenizer.tokens(in: text).map { normalizedWord($0.lookupTerm) }
    }

    private static func normalizedWord(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SentenceGenerationBatchPlan: Equatable {
    let batches: [Int]

    init(requestedCount: Int, maximumBatchSize: Int = 5) {
        let count = max(1, requestedCount)
        let batchSize = max(1, maximumBatchSize)
        var remaining = count
        var batches: [Int] = []
        while remaining > 0 {
            let next = min(batchSize, remaining)
            batches.append(next)
            remaining -= next
        }
        self.batches = batches
    }
}
