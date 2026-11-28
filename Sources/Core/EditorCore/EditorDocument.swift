/// The editor's state with snapshot undo (§6.2, U1–U6). Pure and not `@MainActor`; one per editor.
public final class EditorDocument {
    public static let undoLimit = 200

    public private(set) var state: EditorState
    private var undoStack: [EditorState] = []
    private var redoStack: [EditorState] = []
    /// The state when the open change began, nil while none is open.
    private var changeStart: EditorState?
    private var savedState: EditorState

    public init(state: EditorState = EditorState()) {
        self.state = state
        savedState = state
    }

    public var isChangeOpen: Bool { changeStart != nil }

    /// U4: also true while an open change differs from its start.
    public var canUndo: Bool { !undoStack.isEmpty || (changeStart.map { $0 != state } ?? false) }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var isDirty: Bool { state != savedState }

    /// U1: remembers the state only if no change is open.
    public func beginChange() {
        if changeStart == nil { changeStart = state }
    }

    public func update(_ body: (inout EditorState) -> Void) {
        body(&state)
    }

    /// U1: pushes the remembered state only if the state differs, and then clears redo.
    public func endChange() {
        guard let start = changeStart else { return }
        changeStart = nil
        guard start != state else { return }
        undoStack.append(start)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst(undoStack.count - Self.undoLimit) }
        redoStack.removeAll()
    }

    /// Restores the open change's start without a step (Esc during a drag, E15).
    public func cancelChange() {
        guard let start = changeStart else { return }
        state = start
        changeStart = nil
    }

    public func apply(_ body: (inout EditorState) -> Void) {
        beginChange()
        update(body)
        endChange()
    }

    /// Closes an open change first (U4).
    public func undo() {
        endChange()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(state)
        state = previous
    }

    public func redo() {
        endChange()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(state)
        state = next
    }

    /// U6: the state that was written, not necessarily the current one (E13).
    public func markSaved(_ written: EditorState) {
        savedState = written
    }
}
