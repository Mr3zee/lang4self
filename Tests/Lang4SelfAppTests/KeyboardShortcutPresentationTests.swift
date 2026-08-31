import XCTest
@testable import Lang4Self

final class KeyboardShortcutPresentationTests: XCTestCase {
    func testLettersAndDigitsUsePlainCharacters() {
        XCTAssertEqual(
            ShortcutKey.letter("f"),
            .character("F", accessibilityName: "F")
        )
        XCTAssertEqual(
            ShortcutKey.digit(3),
            .character("3", accessibilityName: "3")
        )
    }

    func testSpaceActionLabelUsesConsistentInstruction() {
        XCTAssertEqual(
            KeyboardShortcutLabel.pressSpace(to: "show answer"),
            "Press Space to show answer"
        )
    }
}
