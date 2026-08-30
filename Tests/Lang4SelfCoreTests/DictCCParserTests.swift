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

    func testTranslationSummaryUsesMiddleDots() {
        let entry = DictionaryEntry(
            german: "recht",
            english: "all right",
            kind: .adverb,
            meanings: [
                DictionaryMeaning(english: "all right"),
                DictionaryMeaning(english: "okay"),
                DictionaryMeaning(english: "well")
            ]
        )

        let translationRow = GermanMorphology.info(for: entry).rows.first { $0.label == "Translations" }

        XCTAssertEqual(translationRow?.value, "all right · okay · well")
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

    func testParsesEveryDictCCClassification() throws {
        let classifications: [(String, WordKind)] = [
            ("noun", .noun),
            ("verb", .verb),
            ("adj", .adjective),
            ("adv", .adverb),
            ("pron", .pronoun),
            ("prep", .preposition),
            ("conj", .conjunction),
            ("pres-p", .presentParticiple),
            ("past-p", .pastParticiple),
            ("prefix", .prefix),
            ("suffix", .suffix)
        ]

        for (classification, expectedKind) in classifications {
            let entry = try XCTUnwrap(DictCCParser.parse(line: "Wort\tword\t\(classification)\t"))
            XCTAssertEqual(entry.kind, expectedKind, classification)
        }
    }

    func testUsesFirstKindForMixedDatasetClassifications() throws {
        let adjective = try XCTUnwrap(DictCCParser.parse(line: "echt\treal\tadj adv\t"))
        let participle = try XCTUnwrap(DictCCParser.parse(line: "gemacht\tmade\tpast-p adj\t"))

        XCTAssertEqual(adjective.kind, .adjective)
        XCTAssertEqual(participle.kind, .pastParticiple)
    }

    func testDetectsInlineDeterminerClassification() throws {
        let entry = try XCTUnwrap(DictCCParser.parse(line: "sein\this [determiner]\t"))

        XCTAssertEqual(entry.kind, .determiner)
        XCTAssertEqual(entry.english, "his")
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
