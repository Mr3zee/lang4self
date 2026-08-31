import AppKit
import XCTest
@testable import Lang4Self

@MainActor
final class GermanSpeechControllerTests: XCTestCase {
    func testSpeaksOnlyTheNormalizedCurrentTarget() {
        let synthesizer = TestGermanSpeechSynthesizer()
        let controller = GermanSpeechController(synthesizer: synthesizer)

        controller.setTarget("  Donau\u{00AD}dampfschiff  ", in: .dictionary)
        controller.activate(.dictionary)
        controller.speakTarget()

        XCTAssertEqual(synthesizer.spokenTexts, ["Donaudampfschiff"])
        XCTAssertEqual(controller.lastSpokenText, "Donaudampfschiff")
    }

    func testEmptyTargetDoesNotSpeak() {
        let synthesizer = TestGermanSpeechSynthesizer()
        let controller = GermanSpeechController(synthesizer: synthesizer)

        controller.setTarget("   ", in: .review)
        controller.activate(.review)
        controller.speakTarget()

        XCTAssertTrue(synthesizer.spokenTexts.isEmpty)
        XCTAssertNil(controller.target)
    }

    func testOnlyTheActiveScreenProvidesTheShortcutTarget() {
        let synthesizer = TestGermanSpeechSynthesizer()
        let controller = GermanSpeechController(synthesizer: synthesizer)
        controller.setTarget("Haus", in: .dictionary)
        controller.setTarget("Das Kind liest.", in: .sentences)

        controller.activate(.dictionary)
        controller.speakTarget()
        controller.activate(.sentences)
        controller.speakTarget()
        controller.activate(nil)
        controller.speakTarget()

        XCTAssertEqual(synthesizer.spokenTexts, ["Haus", "Das Kind liest."])
        XCTAssertNil(controller.target)
    }
}

final class DoubleShiftKeyDetectorTests: XCTestCase {
    func testTwoCleanShiftTapsWithinIntervalTriggerOnce() {
        var detector = DoubleShiftKeyDetector(maximumInterval: 0.4)

        XCTAssertFalse(detector.handle(shiftEvent(isDown: true, timestamp: 1.0)))
        XCTAssertFalse(detector.handle(shiftEvent(isDown: false, timestamp: 1.1)))
        XCTAssertTrue(detector.handle(shiftEvent(isDown: true, timestamp: 1.3)))
        XCTAssertFalse(detector.handle(shiftEvent(isDown: false, timestamp: 1.4)))
        XCTAssertFalse(detector.handle(shiftEvent(isDown: true, timestamp: 1.5)))
    }

    func testSlowShiftTapsDoNotTrigger() {
        var detector = DoubleShiftKeyDetector(maximumInterval: 0.4)

        _ = detector.handle(shiftEvent(isDown: true, timestamp: 1.0))
        _ = detector.handle(shiftEvent(isDown: false, timestamp: 1.1))

        XCTAssertFalse(detector.handle(shiftEvent(isDown: true, timestamp: 1.6)))
    }

    func testTypingWithShiftDoesNotCountAsATap() {
        var detector = DoubleShiftKeyDetector(maximumInterval: 0.4)

        _ = detector.handle(shiftEvent(isDown: true, timestamp: 1.0))
        _ = detector.handle(keyEvent(timestamp: 1.05))
        _ = detector.handle(shiftEvent(isDown: false, timestamp: 1.1))
        _ = detector.handle(shiftEvent(isDown: true, timestamp: 1.2))

        XCTAssertFalse(detector.handle(shiftEvent(isDown: false, timestamp: 1.3)))
        XCTAssertTrue(detector.handle(shiftEvent(isDown: true, timestamp: 1.5)))
    }

    private func shiftEvent(isDown: Bool, timestamp: TimeInterval) -> NSEvent {
        NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: isDown ? .shift : [],
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 56
        )!
    }

    private func keyEvent(timestamp: TimeInterval) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .shift,
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            characters: "A",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        )!
    }
}

@MainActor
private final class TestGermanSpeechSynthesizer: GermanSpeechSynthesizing {
    private(set) var spokenTexts: [String] = []

    func speak(_ text: String) {
        spokenTexts.append(text)
    }

    func stop() {}
}
