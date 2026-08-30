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

    private func spaceEvent(type: NSEvent.EventType, isRepeat: Bool = false) -> NSEvent {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: isRepeat,
            keyCode: 49
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
    private(set) var startCount = 0
    private(set) var rerecordCount = 0
    private(set) var stopCount = 0

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
}

@MainActor
private final class TestContext: VoiceSearchShortcutContext {
    var hasActiveDialog = false
    var hasEditableTextInputFocus = false
}
