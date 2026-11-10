import Foundation

/// Snapshot-based undo stack tailored for canvas documents.
///
/// Documents are small value types (a few hundred KB for very large canvases),
/// so whole-document snapshots are simpler and far less bug-prone than a
/// command/merge system. Snapshots are compressed with a cheap structural
/// comparison guard: identical states are never pushed twice.
public final class UndoStack {
    public struct Entry {
        public let document: CanvasDocument
        public let label: String
        public let timestamp: Date
    }

    public private(set) var undoEntries: [Entry] = []
    public private(set) var redoEntries: [Entry] = []
    public let limit: Int

    /// Used to coalesce rapid edits of the same kind (typing, dragging) into a
    /// single undo step.
    private var lastCoalescingKey: String?
    private var lastPushTime: Date = .distantPast
    private let coalescingWindow: TimeInterval

    public init(limit: Int = 200, coalescingWindow: TimeInterval = 0.6) {
        self.limit = max(1, limit)
        self.coalescingWindow = coalescingWindow
    }

    public var canUndo: Bool { !undoEntries.isEmpty }
    public var canRedo: Bool { !redoEntries.isEmpty }

    public var undoLabel: String? { undoEntries.last?.label }
    public var redoLabel: String? { redoEntries.last?.label }

    public func reset() {
        undoEntries.removeAll()
        redoEntries.removeAll()
        lastCoalescingKey = nil
        lastPushTime = .distantPast
    }

    /// Records the state *before* a change is applied.
    public func record(_ document: CanvasDocument, label: String, coalescingKey: String? = nil) {
        let now = Date()
        if let coalescingKey,
           coalescingKey == lastCoalescingKey,
           now.timeIntervalSince(lastPushTime) < coalescingWindow,
           !undoEntries.isEmpty {
            lastPushTime = now
            return
        }
        push(document, label: label)
        lastCoalescingKey = coalescingKey
        lastPushTime = now
    }

    private func push(_ document: CanvasDocument, label: String) {
        undoEntries.append(Entry(document: document, label: label, timestamp: Date()))
        if undoEntries.count > limit {
            undoEntries.removeFirst(undoEntries.count - limit)
        }
        redoEntries.removeAll()
    }

    /// Returns the document to restore, given the current one (which becomes redoable).
    public func undo(current: CanvasDocument) -> CanvasDocument? {
        guard let entry = undoEntries.popLast() else { return nil }
        redoEntries.append(Entry(document: current, label: entry.label, timestamp: Date()))
        if redoEntries.count > limit { redoEntries.removeFirst(redoEntries.count - limit) }
        lastCoalescingKey = nil
        return entry.document
    }

    public func redo(current: CanvasDocument) -> CanvasDocument? {
        guard let entry = redoEntries.popLast() else { return nil }
        undoEntries.append(Entry(document: current, label: entry.label, timestamp: Date()))
        if undoEntries.count > limit { undoEntries.removeFirst(undoEntries.count - limit) }
        lastCoalescingKey = nil
        return entry.document
    }

    /// Breaks coalescing, e.g. when a drag ends or focus changes.
    public func endCoalescing() {
        lastCoalescingKey = nil
        lastPushTime = .distantPast
    }
}
