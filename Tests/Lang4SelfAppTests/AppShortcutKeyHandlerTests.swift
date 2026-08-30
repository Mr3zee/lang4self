import AppKit
import XCTest
@testable import Lang4Self

@MainActor
final class AppShortcutKeyHandlerTests: XCTestCase {
    func testCommandCommaOpensSettingsAndConsumesTheEvent() {
        var settingsOpenCount = 0
        let handler = AppShortcutKeyHandler(
            openSettings: { settingsOpenCount += 1 },
            showKeyboardShortcuts: {}
        )
        let event = keyEvent(characters: ",", modifiers: .command)

        XCTAssertNil(handler.handle(event))
        XCTAssertEqual(settingsOpenCount, 1)
    }

    func testModifiedCommaIsNotTreatedAsSettingsShortcut() {
        var settingsOpenCount = 0
        let handler = AppShortcutKeyHandler(
            openSettings: { settingsOpenCount += 1 },
            showKeyboardShortcuts: {}
        )
        let event = keyEvent(characters: ",", modifiers: [.command, .shift])

        XCTAssertIdentical(handler.handle(event), event)
        XCTAssertEqual(settingsOpenCount, 0)
    }

    func testCommandZRunsAppUndoAndConsumesTheEvent() {
        var undoCount = 0
        let handler = AppShortcutKeyHandler(
            openSettings: {},
            showKeyboardShortcuts: {},
            undo: {
                undoCount += 1
                return true
            }
        )
        let event = keyEvent(characters: "z", modifiers: .command)

        XCTAssertNil(handler.handle(event))
        XCTAssertEqual(undoCount, 1)
    }

    func testShiftCommandZRunsAppRedoAndConsumesTheEvent() {
        var redoCount = 0
        let handler = AppShortcutKeyHandler(
            openSettings: {},
            showKeyboardShortcuts: {},
            redo: {
                redoCount += 1
                return true
            }
        )
        let event = keyEvent(characters: "Z", modifiers: [.command, .shift])

        XCTAssertNil(handler.handle(event))
        XCTAssertEqual(redoCount, 1)
    }

    func testTextEditingKeepsTheSystemUndoShortcut() {
        var undoCount = 0
        let handler = AppShortcutKeyHandler(
            openSettings: {},
            showKeyboardShortcuts: {},
            undo: {
                undoCount += 1
                return true
            },
            isEditingText: { true }
        )
        let event = keyEvent(characters: "z", modifiers: .command)

        XCTAssertIdentical(handler.handle(event), event)
        XCTAssertEqual(undoCount, 0)
    }

    private func keyEvent(characters: String, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 43
        )!
    }
}
