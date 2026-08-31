import XCTest
@testable import Lang4Self

@MainActor
final class VoiceSearchShortcutControllerTests: XCTestCase {
    func testConsecutiveDictionarySpaceHoldsStartAndStopRecording() {
        let router = TestRouter()
        let speech = TestRecording()
        let controller = VoiceSearchShortcutController(
            router: router,
            speech: speech,
            context: TestContext()
        )

        for expectedRerecordCount in 0...1 {
            controller.beginDictionarySpaceHold()
            controller.beginDictionarySpaceHold()
            controller.releaseSpaceHold()
            XCTAssertEqual(speech.rerecordCount, expectedRerecordCount)
        }

        XCTAssertEqual(speech.startCount, 1)
        XCTAssertEqual(speech.stopCount, 2)
    }

    func testTextSearchPreventsDictionarySpaceHold() {
        let controller = VoiceSearchShortcutController(
            router: TestRouter(),
            speech: TestRecording(),
            context: TestContext()
        )
        controller.dictionaryTextSearchFocusChanged(isFocused: true)

        controller.beginDictionarySpaceHold()

        XCTAssertFalse(controller.isSpaceHeld)
    }

    func testCyclesVoiceAlternativesOnDictionaryPage() {
        let speech = TestRecording()
        speech.phase = .guess
        speech.hasMultipleAlternatives = true
        let controller = VoiceSearchShortcutController(
            router: TestRouter(),
            speech: speech,
            context: TestContext()
        )

        XCTAssertTrue(controller.cycleVoiceAlternative(by: 1))
        XCTAssertTrue(controller.cycleVoiceAlternative(by: -1))
        XCTAssertEqual(speech.alternativeOffsets, [1, -1])
    }

    func testDoesNotCycleWithoutVoiceResults() {
        let speech = TestRecording()
        let controller = VoiceSearchShortcutController(
            router: TestRouter(),
            speech: speech,
            context: TestContext()
        )

        XCTAssertFalse(controller.cycleVoiceAlternative(by: 1))
        XCTAssertTrue(speech.alternativeOffsets.isEmpty)
    }
}

@MainActor
private final class TestRouter: VoiceSearchShortcutRouting {
    var route: AppRoute = .dictionary
}

@MainActor
private final class TestRecording: VoiceSearchShortcutRecording {
    var phase: SpeechRecognizer.Phase = .idle
    var hasRecordingPermission = true
    var hasMultipleAlternatives = false
    private(set) var startCount = 0
    private(set) var rerecordCount = 0
    private(set) var stopCount = 0
    private(set) var alternativeOffsets: [Int] = []

    func start() {
        startCount += 1
        phase = .listening
    }

    func rerecord() {
        rerecordCount += 1
        phase = .listening
    }

    func stop() {
        stopCount += 1
        phase = .guess
    }

    func selectAlternative(by offset: Int) {
        alternativeOffsets.append(offset)
    }
}

@MainActor
private final class TestContext: VoiceSearchShortcutContext {
    var hasActiveDialog = false
}
