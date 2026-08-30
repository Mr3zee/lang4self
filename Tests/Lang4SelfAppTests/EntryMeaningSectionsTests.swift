import XCTest
import Lang4SelfCore
@testable import Lang4Self

final class EntryMeaningSectionsTests: XCTestCase {
    func testKeepsThreeEnglishMeaningsVisibleAndFoldsTheRestByLanguage() {
        let sections = EntryMeaningSections(meanings: [
            meaning("first"),
            meaning("первый", language: .russian),
            meaning("second"),
            meaning("second Russian", language: .russian),
            meaning("third"),
            meaning("fourth"),
            meaning("fifth")
        ])

        XCTAssertEqual(sections.englishPreview.map(\.translation), ["first", "second", "third"])
        XCTAssertEqual(sections.additionalEnglish.map(\.translation), ["fourth", "fifth"])
        XCTAssertEqual(sections.russian.map(\.translation), ["первый", "second Russian"])
    }

    func testExpandsSemicolonSeparatedTranslationsIntoListItems() {
        let sections = EntryMeaningSections(meanings: [
            meaning("I; me"),
            meaning("я; меня", language: .russian)
        ])

        XCTAssertEqual(sections.englishPreview.map(\.translation), ["I", "me"])
        XCTAssertEqual(sections.russian.map(\.translation), ["я", "меня"])
    }

    func testTranslationSummaryRemovesSemicolonsAndDuplicates() {
        let summary = TranslationPresentation.summary(
            of: [meaning("first; second"), meaning("second")]
        )
        let legacySummary = TranslationPresentation.summary(
            of: [],
            fallback: "first; second; first"
        )

        XCTAssertEqual(summary, "first, second")
        XCTAssertEqual(legacySummary, "first, second")
        XCTAssertFalse(summary.contains(";"))
        XCTAssertFalse(legacySummary.contains(";"))
    }

    func testEntryDetailDoesNotRepeatTheWordAndTranslationsInItsInfoTable() {
        let entry = DictionaryEntry(
            german: "ich",
            english: "I; me",
            kind: .pronoun,
            meanings: [DictionaryMeaning(english: "I; me")]
        )

        let rows = EntryDetailInfoRows.supplemental(from: GermanMorphology.info(for: entry).rows)

        XCTAssertTrue(rows.isEmpty)
    }

    func testEntryDetailKeepsSupplementalGrammarRows() {
        let entry = DictionaryEntry(
            german: "Begriff",
            english: "term",
            kind: .other,
            usage: "technical"
        )

        let rows = EntryDetailInfoRows.supplemental(from: GermanMorphology.info(for: entry).rows)

        XCTAssertEqual(rows.map(\.label), ["Usage"])
    }

    private func meaning(
        _ translation: String,
        language: TranslationLanguage = .english
    ) -> DictionaryMeaning {
        DictionaryMeaning(english: translation, language: language)
    }
}
