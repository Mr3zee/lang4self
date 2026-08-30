import XCTest
@testable import Lang4SelfCore

final class DictCCParserTests: XCTestCase {
    func testParsesGenderAndUsage() throws {
        let entry = try XCTUnwrap(DictCCParser.parse(line: "Apfel {m} [Obst]\tapple"))
        XCTAssertEqual(entry.german, "Apfel")
        XCTAssertEqual(entry.english, "apple")
        XCTAssertEqual(entry.kind, .noun)
        XCTAssertEqual(entry.gender, .masculine)
        XCTAssertEqual(entry.usage, "Obst")
    }

    func testDetectsSeparableVerb() throws {
        let entry = try XCTUnwrap(DictCCParser.parse(line: "auf|stehen\tto get up"))
        XCTAssertEqual(entry.kind, .verb)
        let parts = try XCTUnwrap(GermanMorphology.separableParts(for: entry))
        XCTAssertEqual(parts.prefix, "auf")
        XCTAssertEqual(parts.stem, "stehen")
        XCTAssertTrue(GermanMorphology.info(for: entry).rows.contains { $0.value == "sein aufgestanden" || $0.value == "haben aufgestanden" })
    }

    func testIrregularAdjectiveDegrees() throws {
        let entry = try XCTUnwrap(DictCCParser.parse(line: "gut {adj}\tgood"))
        let values = GermanMorphology.info(for: entry).rows.map(\.value)
        XCTAssertEqual(values, ["gut", "besser", "am besten"])
    }

    func testParsesEnglishFirstFile() throws {
        let entry = try XCTUnwrap(DictCCParser.parse(line: "cat\tKatze {f}", germanFirst: false))
        XCTAssertEqual(entry.german, "Katze")
        XCTAssertEqual(entry.english, "cat")
        XCTAssertEqual(entry.gender, .feminine)
    }

    func testParsesRussianTranslationAndDeclaredKind() throws {
        let entry = try XCTUnwrap(DictCCParser.parse(
            line: "lernen\tучиться [несов.]\tverb\t",
            translationLanguage: .russian
        ))
        XCTAssertEqual(entry.german, "lernen")
        XCTAssertEqual(entry.english, "учиться")
        XCTAssertEqual(entry.kind, .verb)
        XCTAssertEqual(entry.meanings.first?.language, .russian)
    }

    func testNounInfoSeparatesPluralFormsFromUsageNotes() throws {
        let dog = try XCTUnwrap(DictCCParser.parse(line: "Hund {m} [Hunde]\tdog"))
        let mother = try XCTUnwrap(DictCCParser.parse(line: "Mutter {f} [Mütter]\tmother"))
        let technicalTerm = try XCTUnwrap(DictCCParser.parse(
            line: "Hundedermatologie {f} [auch: Hunde-Dermatologie]\tcanine dermatology"
        ))

        XCTAssertEqual(GermanMorphology.pluralForms(for: dog), ["Hunde"])
        XCTAssertEqual(GermanMorphology.pluralForms(for: mother), ["Mütter"])
        let dogRows = GermanMorphology.info(for: dog).rows
        XCTAssertEqual(dogRows.map(\.label), ["Article / gender", "Singular", "Plural"])
        XCTAssertEqual(dogRows.map(\.value), ["der", "Hund", "Hunde"])
        XCTAssertTrue(GermanMorphology.pluralForms(for: technicalTerm).isEmpty)
        XCTAssertEqual(GermanMorphology.info(for: technicalTerm).rows.last?.label, "Usage")
    }

    func testLookupTermsIncludeArticlesInflectionsAndSeparatedPrefixes() {
        XCTAssertTrue(GermanMorphology.lookupTerms(for: "Der Hund").contains("hund"))
        XCTAssertTrue(GermanMorphology.lookupTerms(for: "Hunde").contains("hund"))
        XCTAssertTrue(GermanMorphology.lookupTerms(for: "lernt").contains("lernen"))
        XCTAssertTrue(GermanMorphology.lookupTerms(for: "fällt").contains("fallen"))
        XCTAssertTrue(GermanMorphology.lookupTerms(for: "fällt ab").contains("abfallen"))
        XCTAssertTrue(GermanMorphology.lookupTerms(for: "abgefallen").contains("abfallen"))
    }
}
