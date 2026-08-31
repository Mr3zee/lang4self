import XCTest
@testable import Lang4Self

@MainActor
final class SpeechRecognizerAlternativeTests: XCTestCase {
    func testEmptyRecordingReturnsToIdle() {
        let recognizer = SpeechRecognizer(
            isUITesting: true,
            simulatesUndeterminedPermissions: false,
            uiTestingAlternativeCount: 0
        )

        recognizer.start()
        XCTAssertEqual(recognizer.phase, .listening)

        recognizer.stop()
        XCTAssertEqual(recognizer.phase, .idle)
    }

    func testVoiceAlternativesExposeConfidenceAndWrapInBothDirections() {
        let recognizer = SpeechRecognizer(
            isUITesting: true,
            simulatesUndeterminedPermissions: false,
            uiTestingAlternativeCount: 3
        )

        recognizer.start()

        XCTAssertEqual(recognizer.alternatives.count, 3)
        XCTAssertEqual(recognizer.alternatives.map(\.transcription), ["Der Hund", "Die Hunde", "Ein Hund"])
        XCTAssertEqual(recognizer.alternatives.map(\.confidence), [0.96, 0.78, 0.61])
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
