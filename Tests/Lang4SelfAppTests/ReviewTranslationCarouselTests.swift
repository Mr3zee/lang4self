import XCTest
import Lang4SelfCore
@testable import Lang4Self

final class ReviewTranslationCarouselTests: XCTestCase {
    func testSentencePracticeIsPartOfReviewModeCycling() {
        XCTAssertEqual(ReviewMode.card(.plural).advanced(by: 1), .sentences)
        XCTAssertEqual(ReviewMode.sentences.advanced(by: 1), .card(.listeningWords))
        XCTAssertEqual(ReviewMode.card(.listeningWords).advanced(by: 1), .listeningSentences)
        XCTAssertEqual(ReviewMode.listeningSentences.advanced(by: 1), .card(.flashcard))
        XCTAssertEqual(ReviewMode.card(.flashcard).advanced(by: -1), .listeningSentences)
    }

    func testCyclesTranslationsAndLanguagesWhileKeepingEachLanguageSelection() {
        var carousel = ReviewTranslationCarousel(
            cardEnglish: "first; second; third; первый; второй",
            dictionaryMeanings: [
                DictionaryMeaning(english: "dictionary English", language: .english),
                DictionaryMeaning(english: "первый", language: .russian),
                DictionaryMeaning(english: "второй", language: .russian)
            ]
        )

        XCTAssertEqual(carousel.current, item(.english, "first"))
        XCTAssertEqual(carousel.previousTranslation, item(.english, "third"))
        XCTAssertEqual(carousel.nextTranslation, item(.english, "second"))
        XCTAssertEqual(carousel.previousLanguage, item(.russian, "первый"))
        XCTAssertEqual(carousel.nextLanguage, item(.russian, "первый"))

        carousel.moveTranslation(by: 1)
        carousel.moveLanguage(by: 1)
        XCTAssertEqual(carousel.current, item(.russian, "первый"))
        XCTAssertEqual(carousel.previousLanguage, item(.english, "second"))

        carousel.moveTranslation(by: 1)
        carousel.moveLanguage(by: -1)
        XCTAssertEqual(carousel.current, item(.english, "second"))

        carousel.moveLanguage(by: 1)
        XCTAssertEqual(carousel.current, item(.russian, "второй"))
    }

    func testSingleTranslationHasNoDimmedNeighbors() {
        let carousel = ReviewTranslationCarousel(cardEnglish: "only")

        XCTAssertEqual(carousel.current, item(.english, "only"))
        XCTAssertNil(carousel.previousTranslation)
        XCTAssertNil(carousel.nextTranslation)
        XCTAssertNil(carousel.previousLanguage)
        XCTAssertNil(carousel.nextLanguage)
        XCTAssertFalse(carousel.hasMultipleTranslations)
        XCTAssertFalse(carousel.hasMultipleLanguages)
    }

    func testDictionaryRefreshPreservesTheSelectedEnglishTranslation() {
        var carousel = ReviewTranslationCarousel(cardEnglish: "first; second")
        carousel.moveTranslation(by: 1)

        carousel.replace(
            cardEnglish: "first; second",
            dictionaryMeanings: [DictionaryMeaning(english: "первый", language: .russian)]
        )

        XCTAssertEqual(carousel.current, item(.english, "second"))
        XCTAssertTrue(carousel.hasMultipleLanguages)
    }

    func testSplitsSemicolonSeparatedDictionaryMeanings() {
        var carousel = ReviewTranslationCarousel(
            dictionaryMeanings: [
                DictionaryMeaning(english: "first; second", language: .english),
                DictionaryMeaning(english: "первый; второй", language: .russian)
            ]
        )

        XCTAssertEqual(carousel.current, item(.english, "first"))
        carousel.moveTranslation(by: 1)
        XCTAssertEqual(carousel.current, item(.english, "second"))
        carousel.moveLanguage(by: 1)
        XCTAssertEqual(carousel.current, item(.russian, "первый"))
        carousel.moveTranslation(by: 1)
        XCTAssertEqual(carousel.current, item(.russian, "второй"))
    }

    private func item(
        _ language: TranslationLanguage,
        _ translation: String
    ) -> ReviewTranslationCarousel.Item {
        .init(language: language, translation: translation)
    }
}
