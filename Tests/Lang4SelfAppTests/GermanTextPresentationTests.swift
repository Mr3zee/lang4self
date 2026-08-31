import XCTest
@testable import Lang4Self

final class GermanTextPresentationTests: XCTestCase {
    func testLongGermanCompoundGetsDiscretionaryGrammaticalBreaks() {
        let source = "Donaudampfschifffahrtsgesellschaftskapitän"

        let rendered = GermanTextPresentation.hyphenated(source)

        XCTAssertEqual(
            rendered.replacingOccurrences(of: GermanTextPresentation.softHyphen, with: ""),
            source
        )
        var sourceOffset = 0
        var breakOffsets: [Int] = []
        for character in rendered {
            if String(character) == GermanTextPresentation.softHyphen {
                breakOffsets.append(sourceOffset)
            } else {
                sourceOffset += String(character).utf16.count
            }
        }
        for expectedOffset in [5, 10, 16, 22, 28, 35] {
            XCTAssertTrue(breakOffsets.contains(expectedOffset), "Missing German break at \(expectedOffset)")
        }
    }

    func testHyphenationCoversEveryLongWordInAPhraseAndIsIdempotent() {
        let source = "Donaudampfschifffahrt trifft Kraftfahrzeughaftpflichtversicherung"

        let rendered = GermanTextPresentation.hyphenated(source)

        XCTAssertGreaterThan(
            rendered.filter { String($0) == GermanTextPresentation.softHyphen }.count,
            2
        )
        XCTAssertEqual(GermanTextPresentation.hyphenated(rendered), rendered)
    }
}
