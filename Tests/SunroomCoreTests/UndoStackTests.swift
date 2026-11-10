import XCTest
@testable import SunroomCore

final class UndoStackTests: XCTestCase {

    private func document(named name: String) -> CanvasDocument {
        makeDocument(name: name)
    }

    // MARK: Undo / redo round trip

    func testUndoRestoresRecordedStateAndRedoRestoresCurrent() {
        let stack = UndoStack(limit: 20, coalescingWindow: 60)
        var current = document(named: "One")

        stack.record(current, label: "Rename")
        current = document(named: "Two")

        let undone = try! XCTUnwrap(stack.undo(current: current))
        XCTAssertEqual(undone.name, "One")
        XCTAssertTrue(stack.canRedo)
        XCTAssertFalse(stack.canUndo)

        let redone = try! XCTUnwrap(stack.redo(current: undone))
        XCTAssertEqual(redone.name, "Two")
        XCTAssertTrue(stack.canUndo)
        XCTAssertFalse(stack.canRedo)
    }

    func testUndoAndRedoReturnNilWhenEmpty() {
        let stack = UndoStack()
        XCTAssertNil(stack.undo(current: makeDocument()))
        XCTAssertNil(stack.redo(current: makeDocument()))
        XCTAssertFalse(stack.canUndo)
        XCTAssertFalse(stack.canRedo)
    }

    func testUndoThenRedoPreservesNodeState() {
        let stack = UndoStack()
        let original = makeDocument(nodes: [makeNode(title: "A")])
        var edited = original
        edited.rename(id: edited.nodes[0].id, title: "B")

        stack.record(original, label: "Rename")
        let undone = try! XCTUnwrap(stack.undo(current: edited))
        XCTAssertEqual(undone.nodes[0].title, "A")

        let redone = try! XCTUnwrap(stack.redo(current: undone))
        XCTAssertEqual(redone.nodes[0].title, "B")
    }

    // MARK: Redo invalidation

    func testNewRecordClearsRedo() {
        let stack = UndoStack()
        let one = document(named: "One")
        stack.record(one, label: "First")
        _ = stack.undo(current: document(named: "Two"))
        XCTAssertTrue(stack.canRedo)

        stack.record(document(named: "Three"), label: "New edit")
        XCTAssertFalse(stack.canRedo)
        XCTAssertTrue(stack.canUndo)
    }

    // MARK: Limit

    func testLimitTrimsOldestEntries() {
        let stack = UndoStack(limit: 3)
        var current = document(named: "0")
        for index in 1...5 {
            stack.record(current, label: "Edit \(index)")
            current = document(named: "\(index)")
        }

        // Only the three most recent snapshots survive ("2", "3", "4").
        XCTAssertEqual(stack.undoEntries.count, 3)
        XCTAssertEqual(stack.undoLabel, "Edit 5")

        XCTAssertEqual(stack.undo(current: current)?.name, "4")
        XCTAssertEqual(stack.undo(current: document(named: "4"))?.name, "3")
        XCTAssertEqual(stack.undo(current: document(named: "3"))?.name, "2")
        XCTAssertNil(stack.undo(current: document(named: "2")))
    }

    func testLimitIsAtLeastOne() {
        XCTAssertEqual(UndoStack(limit: 0).limit, 1)
        XCTAssertEqual(UndoStack(limit: -10).limit, 1)
    }

    func testRedoStackAlsoHonorsLimit() {
        let stack = UndoStack(limit: 2)
        for index in 0..<5 {
            stack.record(document(named: "Doc \(index)"), label: "Edit \(index)")
        }

        var current = document(named: "Current")
        while let previous = stack.undo(current: current) {
            current = previous
        }
        XCTAssertEqual(stack.redoEntries.count, 2)
    }

    // MARK: Coalescing

    func testCoalescingCollapsesRapidIdenticalKeys() {
        let stack = UndoStack(limit: 20, coalescingWindow: 60)
        stack.record(document(named: "Zero"), label: "Typing", coalescingKey: "note-1-typing")
        stack.record(document(named: "One"), label: "Typing", coalescingKey: "note-1-typing")
        stack.record(document(named: "Two"), label: "Typing", coalescingKey: "note-1-typing")

        XCTAssertEqual(stack.undoEntries.count, 1)
        XCTAssertEqual(stack.undoEntries[0].document.name, "Zero", "Only the pre-burst document is kept")
    }

    func testDifferentCoalescingKeysCreateSeparateEntries() {
        let stack = UndoStack(limit: 20, coalescingWindow: 60)
        stack.record(document(named: "Zero"), label: "Typing", coalescingKey: "note-1")
        stack.record(document(named: "One"), label: "Typing", coalescingKey: "note-2")
        XCTAssertEqual(stack.undoEntries.count, 2)
    }

    func testCoalescingDoesNotApplyWithoutAKey() {
        let stack = UndoStack(limit: 20, coalescingWindow: 60)
        stack.record(document(named: "Zero"), label: "Move")
        stack.record(document(named: "One"), label: "Move")
        XCTAssertEqual(stack.undoEntries.count, 2)
    }

    func testCoalescingDoesNotApplyToFirstEntry() {
        let stack = UndoStack(limit: 20, coalescingWindow: 60)
        stack.record(document(named: "Zero"), label: "Typing", coalescingKey: "same")
        XCTAssertEqual(stack.undoEntries.count, 1)
    }

    func testEndCoalescingStartsANewStep() {
        let stack = UndoStack(limit: 20, coalescingWindow: 60)
        stack.record(document(named: "Zero"), label: "Drag", coalescingKey: "drag")
        stack.record(document(named: "One"), label: "Drag", coalescingKey: "drag")
        XCTAssertEqual(stack.undoEntries.count, 1)

        stack.endCoalescing()
        stack.record(document(named: "Two"), label: "Drag", coalescingKey: "drag")
        XCTAssertEqual(stack.undoEntries.count, 2)
    }

    func testCoalescingWindowExpires() {
        // A zero-length window means the time-since-last-push condition can
        // never be satisfied, deterministically exercising the expiry branch.
        let stack = UndoStack(limit: 20, coalescingWindow: 0)
        stack.record(document(named: "Zero"), label: "Typing", coalescingKey: "same")
        stack.record(document(named: "One"), label: "Typing", coalescingKey: "same")
        XCTAssertEqual(stack.undoEntries.count, 2)
    }

    func testUndoBreaksCoalescing() {
        let stack = UndoStack(limit: 20, coalescingWindow: 60)
        stack.record(document(named: "Zero"), label: "Typing", coalescingKey: "same")
        _ = stack.undo(current: document(named: "One"))

        stack.record(document(named: "Two"), label: "Typing", coalescingKey: "same")
        XCTAssertEqual(stack.undoEntries.count, 1)
        XCTAssertFalse(stack.canRedo)
    }

    // MARK: Labels & reset

    func testLabelsFollowTheStacks() {
        let stack = UndoStack()
        stack.record(document(named: "Zero"), label: "Add Note")

        XCTAssertEqual(stack.undoLabel, "Add Note")
        XCTAssertNil(stack.redoLabel)

        _ = stack.undo(current: document(named: "One"))
        XCTAssertNil(stack.undoLabel)
        XCTAssertEqual(stack.redoLabel, "Add Note")

        _ = stack.redo(current: document(named: "Zero"))
        XCTAssertEqual(stack.undoLabel, "Add Note")
        XCTAssertNil(stack.redoLabel)
    }

    func testEntriesCaptureTimestampAndDocument() {
        let stack = UndoStack()
        let doc = document(named: "Captured")
        let before = Date()
        stack.record(doc, label: "Capture")
        let after = Date()

        let entry = try! XCTUnwrap(stack.undoEntries.last)
        XCTAssertEqual(entry.document.name, "Captured")
        XCTAssertEqual(entry.label, "Capture")
        XCTAssertGreaterThanOrEqual(entry.timestamp, before)
        XCTAssertLessThanOrEqual(entry.timestamp, after)
    }

    func testResetClearsEverything() {
        let stack = UndoStack(limit: 20, coalescingWindow: 60)
        stack.record(document(named: "Zero"), label: "One")
        _ = stack.undo(current: document(named: "One"))
        XCTAssertTrue(stack.canRedo)

        stack.reset()

        XCTAssertFalse(stack.canUndo)
        XCTAssertFalse(stack.canRedo)
        XCTAssertNil(stack.undoLabel)
        XCTAssertNil(stack.redoLabel)

        // Reset also clears the coalescing key, so the same key starts fresh.
        stack.record(document(named: "Two"), label: "Typing", coalescingKey: "same")
        stack.record(document(named: "Three"), label: "Typing", coalescingKey: "same")
        XCTAssertEqual(stack.undoEntries.count, 1)
    }
}
