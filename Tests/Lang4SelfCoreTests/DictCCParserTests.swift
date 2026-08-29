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
}
