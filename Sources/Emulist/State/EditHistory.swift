/// Linear undo/redo of whole-value snapshots. Grade settings are small value types, so snapshots are
/// simpler and safer than inverse operations.
struct EditHistory<Value: Equatable> {
    private(set) var undoStack: [Value] = []
    private(set) var redoStack: [Value] = []
    private let limit: Int

    init(limit: Int = 200) {
        self.limit = limit
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Records `value` as the state to return to on undo.
    mutating func record(_ value: Value) {
        guard undoStack.last != value else { return }
        undoStack.append(value)
        if undoStack.count > limit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    mutating func undo(from current: Value) -> Value? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    mutating func redo(from current: Value) -> Value? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    mutating func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
