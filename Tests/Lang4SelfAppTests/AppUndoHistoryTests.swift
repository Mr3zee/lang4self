import XCTest
@testable import Lang4Self

@MainActor
final class AppUndoHistoryTests: XCTestCase {
    func testUndoAndRedoStoreTheReturnedInverseOperations() async throws {
        let history = AppUndoHistory()
        var value = 1

        func undoOperation() -> AppUndoOperation {
            AppUndoOperation(name: "Add value") {
                value = 0
                return redoOperation()
            }
        }
        func redoOperation() -> AppUndoOperation {
            AppUndoOperation(name: "Add value") {
                value = 1
                return undoOperation()
            }
        }

        history.record(undoOperation())
        XCTAssertEqual(history.undoActionName, "Add value")

        let undoneName = try await history.undo()
        XCTAssertEqual(undoneName, "Add value")
        XCTAssertEqual(value, 0)
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.canRedo)

        let redoneName = try await history.redo()
        XCTAssertEqual(redoneName, "Add value")
        XCTAssertEqual(value, 1)
        XCTAssertTrue(history.canUndo)
        XCTAssertFalse(history.canRedo)
    }

    func testFailedUndoRemainsAvailable() async {
        struct ExpectedError: Error {}
        let history = AppUndoHistory()
        history.record(AppUndoOperation(name: "Delete value") {
            throw ExpectedError()
        })

        do {
            _ = try await history.undo()
            XCTFail("Expected undo to fail")
        } catch is ExpectedError {}
        catch { XCTFail("Unexpected error: \(error)") }

        XCTAssertTrue(history.canUndo)
        XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.undoActionName, "Delete value")
    }
}
