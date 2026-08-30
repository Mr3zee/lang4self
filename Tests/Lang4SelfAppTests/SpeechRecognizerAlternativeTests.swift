import XCTest
@testable import Lang4Self

@MainActor
final class SpeechRecognizerAlternativeTests: XCTestCase {
    func testVoiceAlternativesExposeConfidenceAndWrapInBothDirections() {
        let recognizer = SpeechRecognizer(
            isUITesting: true,
            simulatesUndeterminedPermissions: false
        )

        recognizer.start()

        XCTAssertEqual(recognizer.alternatives.count, 3)
        XCTAssertEqual(recognizer.transcription, "Der Hund")
        XCTAssertEqual(recognizer.alternativePosition, "1 of 3")
        XCTAssertEqual(recognizer.confidence, 0.96, accuracy: 0.001)

        recognizer.selectAlternative(by: -1)
        XCTAssertEqual(recognizer.transcription, "Ein Hund")
        XCTAssertEqual(recognizer.alternativePosition, "3 of 3")

        recognizer.selectAlternative(by: 1)
        XCTAssertEqual(recognizer.transcription, "Der Hund")
        XCTAssertEqual(recognizer.alternativePosition, "1 of 3")
    }
}
