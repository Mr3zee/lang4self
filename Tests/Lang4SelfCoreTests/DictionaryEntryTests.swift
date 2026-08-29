import XCTest
@testable import Lang4SelfCore

final class DictionaryEntryTests: XCTestCase {
    func testDistinctExplanationIsShownWhenItAddsInformation() {
        let meaning = DictionaryMeaning(
            english: "bank",
            explanation: "A financial institution that holds and lends money."
        )

        XCTAssertEqual(
            meaning.distinctExplanation,
            "A financial institution that holds and lends money."
        )
    }

    func testDistinctExplanationHidesTranslationDuplicate() {
        let exactDuplicate = DictionaryMeaning(english: "house", explanation: "  HOUSE. ")
        let emptyExplanation = DictionaryMeaning(english: "house", explanation: "   ")

        XCTAssertNil(exactDuplicate.distinctExplanation)
        XCTAssertNil(emptyExplanation.distinctExplanation)
    }

    func testEntryHidesSupplementalExplanationThatDuplicatesTranslation() {
        let entry = DictionaryEntry(
            german: "Haus",
            english: "house",
            explanations: [
                .init(text: "House.", source: "Wiktionary"),
                .init(text: "A building used as a home.", source: "Wiktionary")
            ]
        )

        XCTAssertEqual(entry.distinctExplanations.map(\.text), ["A building used as a home."])
    }
}
