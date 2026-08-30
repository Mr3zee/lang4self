import AppKit
import XCTest
@testable import Lang4Self

@MainActor
final class VoiceSearchShortcutControllerTests: XCTestCase {
    func testConsecutiveHoldsConsumeDownRepeatAndUpEvents() {
        let router = TestRouter()
        let speech = TestRecording()
        let controller = VoiceSearchShortcutController(
            router: router,
            speech: speech,
            context: TestContext(),
            holdDelay: 0,
            onForwardedSpaceEvent: {}
        )

        for expectedRerecordCount in 0...1 {
            XCTAssertNil(controller.handle(spaceEvent(type: .keyDown)))
            XCTAssertNil(controller.handle(spaceEvent(type: .keyDown, isRepeat: true)))
            XCTAssertNil(controller.handle(spaceEvent(type: .keyDown, isRepeat: true)))
            XCTAssertNil(controller.handle(spaceEvent(type: .keyUp)))
            XCTAssertEqual(speech.rerecordCount, expectedRerecordCount)
        }

        XCTAssertEqual(speech.startCount, 1)
        XCTAssertEqual(speech.stopCount, 2)
    }

    func testTextSearchReceivesSpaceEventsIncludingRepeats() throws {
        let controller = VoiceSearchShortcutController(
            router: TestRouter(),
            speech: TestRecording(),
            context: TestContext(),
            holdDelay: 0,
            onForwardedSpaceEvent: {}
        )
        controller.dictionaryTextSearchFocusChanged(isFocused: true)

        for event in [
            spaceEvent(type: .keyDown),
            spaceEvent(type: .keyDown, isRepeat: true),
            spaceEvent(type: .keyUp)
        ] {
            XCTAssertIdentical(try XCTUnwrap(controller.handle(event)), event)
        }
    }

    func testCommandBracketsCycleVoiceAlternativesWithoutDependingOnViewFocus() async {
        let speech = TestRecording()
        speech.phase = .guess
        speech.hasMultipleAlternatives = true
        let selections = expectation(description: "Both alternatives selected")
        selections.expectedFulfillmentCount = 2
        speech.didSelectAlternative = { _ in selections.fulfill() }
        let controller = VoiceSearchShortcutController(
            router: TestRouter(),
            speech: speech,
            context: TestContext(),
            holdDelay: 0,
            onForwardedSpaceEvent: {}
        )

        XCTAssertNil(controller.handle(keyEvent(characters: "]", modifiers: .command, keyCode: 30)))
        XCTAssertNil(controller.handle(keyEvent(characters: "", modifiers: .command, keyCode: 33)))
        await fulfillment(of: [selections], timeout: 1)
        XCTAssertEqual(speech.alternativeOffsets, [1, -1])
    }

    func testCommandBracketsAreForwardedWithoutCycleableVoiceResults() throws {
        let speech = TestRecording()
        let controller = VoiceSearchShortcutController(
            router: TestRouter(),
            speech: speech,
            context: TestContext(),
            holdDelay: 0,
            onForwardedSpaceEvent: {}
        )
        let event = keyEvent(characters: "]", modifiers: .command, keyCode: 30)

        XCTAssertIdentical(try XCTUnwrap(controller.handle(event)), event)
        XCTAssertTrue(speech.alternativeOffsets.isEmpty)
    }

    private func spaceEvent(type: NSEvent.EventType, isRepeat: Bool = false) -> NSEvent {
        keyEvent(characters: " ", modifiers: [], keyCode: 49, type: type, isRepeat: isRepeat)
    }

    private func keyEvent(
        characters: String,
        modifiers: NSEvent.ModifierFlags,
        keyCode: UInt16,
        type: NSEvent.EventType = .keyDown,
        isRepeat: Bool = false
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: isRepeat,
            keyCode: keyCode
        )!
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
    var didSelectAlternative: ((Int) -> Void)?

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
        didSelectAlternative?(offset)
    }
}

@MainActor
private final class TestContext: VoiceSearchShortcutContext {
    var hasActiveDialog = false
    var hasEditableTextInputFocus = false
}
