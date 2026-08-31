import XCTest
import Lang4SelfCore
@testable import Lang4Self

final class SentencePracticeSessionTests: XCTestCase {
    func testGenerationRequestsAreSplitIntoOrderedBatchesOfFive() {
        XCTAssertEqual(
            SentenceGenerationBatchPlan(requestedCount: 12).batches,
            [5, 5, 2]
        )
        XCTAssertEqual(
            SentenceGenerationBatchPlan(requestedCount: 5).batches,
            [5]
        )
    }

    func testVocabularyBlankChecksInflectedSurfaceInsteadOfLemma() {
        let item = practiceItem(
            german: "Das ist eine einfache Frage.",
            targetSurfaces: ["einfache"],
            lookupTerm: "einfach"
        )

        XCTAssertTrue(SentenceAnswerEvaluator.isCorrect(
            "einfache",
            for: item,
            mode: .vocabularyBlanks
        ))
        XCTAssertFalse(SentenceAnswerEvaluator.isCorrect(
            "einfach",
            for: item,
            mode: .vocabularyBlanks
        ))
    }

    func testFullSentenceAcceptsOmittedPunctuationButPreservesGermanSpellingAndCase() {
        let item = practiceItem(
            german: "Das Haus ist schön.",
            targetSurfaces: ["Haus"],
            lookupTerm: "Haus"
        )

        XCTAssertTrue(SentenceAnswerEvaluator.isCorrect(
            "Das Haus ist schön",
            for: item,
            mode: .fullSentence
        ))
        XCTAssertFalse(SentenceAnswerEvaluator.isCorrect(
            "Das haus ist schon.",
            for: item,
            mode: .fullSentence
        ))
    }

    func testListeningSentenceChecksTheFullSentenceWithoutVocabularyBlanks() {
        let item = practiceItem(
            german: "Das Haus ist schön.",
            targetSurfaces: ["Haus"],
            lookupTerm: "Haus"
        )

        XCTAssertFalse(SentenceAnswerEvaluator.usesVocabularyBlanks(for: item, mode: .listening))
        XCTAssertTrue(SentenceAnswerEvaluator.isCorrect(
            "Das Haus ist schön",
            for: item,
            mode: .listening
        ))
        XCTAssertFalse(SentenceAnswerEvaluator.isCorrect(
            "Haus",
            for: item,
            mode: .listening
        ))
    }

    func testFailedAnswerIsRequeuedAndSessionWaitsForNextBatch() {
        let source = WordList(id: WordList.defaultID, name: "My words")
        let item = practiceItem(
            german: "Das Haus ist groß.",
            targetSurfaces: ["Haus"],
            lookupTerm: "Haus"
        )
        var session = SentencePracticeSession()
        session.start(
            mode: .vocabularyBlanks,
            requestedCount: 7,
            retries: [],
            sourceList: source
        )
        session.appendGenerated(Array(repeating: item.draft, count: 5))

        XCTAssertEqual(session.submit(answer: "Baum"), .incorrect(submittedAnswer: "Baum"))
        XCTAssertEqual(session.items.count, 6)
        session.advance()

        for _ in 0..<4 {
            XCTAssertEqual(session.submit(answer: "Haus"), .correct)
            session.advance()
        }
        XCTAssertNotNil(session.currentItem, "The failed prompt should remain queued")
        XCTAssertEqual(session.submit(answer: "Haus"), .correct)
        session.advance()

        XCTAssertTrue(session.isWaitingForGeneration)
        session.appendGenerated(Array(repeating: item.draft, count: 2))
        XCTAssertNotNil(session.currentItem)
        XCTAssertFalse(session.isWaitingForGeneration)
    }

    func testInitialGenerationIsNotReportedAsWaitingForNextBatch() {
        let source = WordList(id: WordList.defaultID, name: "My words")
        var session = SentencePracticeSession()

        session.start(
            mode: .vocabularyBlanks,
            requestedCount: 5,
            retries: [],
            sourceList: source
        )

        XCTAssertTrue(session.isWaitingForInitialGeneration)
        XCTAssertFalse(session.isWaitingForGeneration)
    }

    func testGenerationFailureWithoutSentencesReturnsToSetup() {
        let source = WordList(id: WordList.defaultID, name: "My words")
        var session = SentencePracticeSession()
        session.start(
            mode: .vocabularyBlanks,
            requestedCount: 5,
            retries: [],
            sourceList: source
        )

        session.finishGeneration()

        XCTAssertFalse(session.hasStarted)
        XCTAssertFalse(session.isComplete)
        XCTAssertNil(session.currentItem)
    }

    func testAbortClearsAnActiveRunAndReturnsToSetupState() {
        let source = WordList(id: WordList.defaultID, name: "My words")
        var session = SentencePracticeSession()
        session.start(
            mode: .fullSentence,
            requestedCount: 5,
            retries: [],
            sourceList: source
        )
        session.appendGenerated([
            practiceItem(
                german: "Das Haus ist groß.",
                targetSurfaces: ["Haus"],
                lookupTerm: "Haus"
            ).draft
        ])

        XCTAssertTrue(session.hasStarted)
        XCTAssertTrue(session.isActive)

        session.abort()

        XCTAssertFalse(session.hasStarted)
        XCTAssertFalse(session.isActive)
        XCTAssertNil(session.currentItem)
        XCTAssertEqual(session.requestedGenerationCount, 0)
    }

    func testActiveRunCanSwitchToListeningWithoutDiscardingGeneratedItems() {
        let source = WordList(id: WordList.defaultID, name: "My words")
        let item = practiceItem(
            german: "Das Haus ist groß.",
            targetSurfaces: ["Haus"],
            lookupTerm: "Haus"
        )
        var session = SentencePracticeSession()
        session.start(
            mode: .vocabularyBlanks,
            requestedCount: 1,
            retries: [],
            sourceList: source
        )
        session.appendGenerated([item.draft])

        session.setMode(.listening)

        XCTAssertEqual(session.mode, .listening)
        XCTAssertEqual(session.currentItem?.draft, item.draft)
    }

    private func practiceItem(
        german: String,
        targetSurfaces: Set<String>,
        lookupTerm: String
    ) -> SentencePracticeItem {
        let tokens = SentenceTokenizer.tokens(in: german).map { token in
            guard targetSurfaces.contains(SentenceTokenizer.lookupTerm(from: token.surface)) else {
                return token
            }
            return SentenceToken(
                index: token.index,
                surface: token.surface,
                lookupTerm: lookupTerm,
                cardID: 1
            )
        }
        return SentencePracticeItem(
            draft: SentenceDraft(
                german: german,
                translation: "Translation.",
                tokens: tokens
            ),
            sourceListName: "My words"
        )
    }
}
