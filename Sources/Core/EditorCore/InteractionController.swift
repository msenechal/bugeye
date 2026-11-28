import BugeyeCore
import Foundation

/// A text field the canvas shows: where, for which annotation (nil: a new one), with what to start from.
public struct TextEntry: Hashable, Sendable {
    /// Image pixels: the top-left of the first line's box.
    public var origin: Point2D
    public var editingID: UUID?
    public var string: String
    /// Points.
    public var fontSize: Double
    public var color: RGBAColor

    public init(origin: Point2D, editingID: UUID?, string: String, fontSize: Double, color: RGBAColor) {
        self.origin = origin
        self.editingID = editingID
        self.string = string
        self.fontSize = fontSize
        self.color = color
    }
}

public enum InteractionResult: Hashable, Sendable {
    case none
    /// The canvas shows its text view for this entry (I6).
    case beginTextEntry(TextEntry)
}

/// Mouse and keyboard → document edits (§6.3). Pure: the canvas sends events in image pixels with the click count
/// and ⇧, and keeps `zoom` current from the clip view (§5.7). Not `@MainActor`; one per editor.
public final class InteractionController {
    /// Screen points (§4).
    public static let handleSize = 8.0
    public static let hitDistance = 6.0

    private enum Drag {
        case drawing(start: Point2D)
        case moving(id: UUID, last: Point2D)
        case resizing(id: UUID, original: AnnotationShape, handle: AnnotationHandle, grabOffset: Point2D)
        case cropping(start: Point2D)
    }

    public let document: EditorDocument
    public let imageSize: Size2D
    public var metrics: EditorMetrics
    /// The clip view's magnification.
    public var zoom: Double = 1
    /// The snapping hook (§8.3): sees each draft before it is added. Identity in Wave 1.
    public var snapping: (AnnotationShape) -> AnnotationShape = { $0 }

    public private(set) var tool: EditorTool = .default
    public private(set) var options = ToolOptions()
    public private(set) var selection: UUID?
    public private(set) var textEntry: TextEntry?
    private var draft: Annotation?
    private var draftCrop: Rect2D?
    private var drag: Drag?
    /// The annotation whose restyle is open (U5).
    private var restylingID: UUID?
    /// An unbracketed frame change (keyboard slider steps) is open (U5).
    private var frameRunOpen = false
    /// A bracketed frame change (a slider drag) is open.
    private var frameDragOpen = false

    public init(document: EditorDocument, imageSize: Size2D, metrics: EditorMetrics) {
        self.document = document
        self.imageSize = imageSize
        self.metrics = metrics
    }

    // MARK: What the canvas draws

    /// The Crop tool shows the whole image without the frame.
    public var showsFullImage: Bool { tool == .crop }

    /// State − hidden + draft + draft crop (I7).
    public var displayState: EditorState {
        var state = document.state
        if let hidden = textEntry?.editingID { state.annotations.removeAll { $0.id == hidden } }
        if let draft { state.annotations.append(draft) }
        if let draftCrop { state.crop = draftCrop }
        return state
    }

    /// The annotation being drawn, moved or resized (I7).
    public var activeID: UUID? {
        switch drag {
        case .drawing: draft?.id
        case .moving(let id, _), .resizing(let id, _, _, _): id
        case .cropping, nil: nil
        }
    }

    /// The annotation being re-edited, hidden while its text view is up.
    public var hiddenID: UUID? { textEntry?.editingID }

    public var isDragging: Bool { drag != nil }

    public var layout: CanvasLayout {
        CanvasLayout(
            imageSize: imageSize, state: document.state, pixelsPerPoint: metrics.ppp, showingFullImage: showsFullImage)
    }

    /// The crop, or the whole image, in image pixels.
    public var visibleRect: Rect2D {
        document.state.crop ?? Rect2D(x: 0, y: 0, width: imageSize.width, height: imageSize.height)
    }

    /// Screen points to image pixels at the current zoom.
    public func pixels(fromScreenPoints value: Double) -> Double {
        value * metrics.ppp / max(zoom, 0.0001)
    }

    // MARK: Tools and options

    public func setTool(_ newTool: EditorTool) {
        finishPendingChanges()
        cancelDrag()
        if newTool != .select { selection = nil }
        tool = newTool
    }

    /// Restyles the selected annotation (Select tool), coalescing a run on one annotation into one step (U5).
    public func setOptions(_ newOptions: ToolOptions) {
        options = newOptions
        guard tool == .select, let id = selection, let annotation = document.state.annotation(id) else { return }
        if restylingID != id {
            finishPendingChanges()
            document.beginChange()
            restylingID = id
        }
        let restyled = Self.restyle(annotation, with: newOptions)
        document.update { state in
            if let index = state.index(of: id) { state.annotations[index] = restyled }
        }
    }

    /// Closes an open restyle or keyboard frame run; every other action calls it first (U5).
    public func finishPendingChanges() {
        if restylingID != nil || frameRunOpen {
            document.endChange()
        }
        restylingID = nil
        frameRunOpen = false
    }

    // MARK: Mouse

    public func mouseDown(at p: Point2D, clickCount: Int, shift: Bool) -> InteractionResult {
        guard textEntry == nil, drag == nil else { return .none }
        finishPendingChanges()
        switch tool {
        case .select:
            return selectDown(at: p, clickCount: clickCount)
        case .crop:
            drag = .cropping(start: p)
            draftCrop = nil
            return .none
        case .text:
            if let hit = topmostHit(at: p, where: { if case .text = $0.shape { true } else { false } }) {
                return beginEditing(hit)
            }
            guard contains(visibleRect, p) else { return .none }
            let entry = TextEntry(
                origin: p, editingID: nil, string: "", fontSize: options.fontSize, color: options.color)
            textEntry = entry
            return .beginTextEntry(entry)
        case .step:
            guard contains(visibleRect, p) else { return .none }
            let step = Annotation(shape: .step(center: p), style: style(for: .step))
            document.apply { $0.annotations.append(step) }
            return .none
        case .arrow, .line, .rectangle, .ellipse, .pen, .highlighter, .blur:
            drag = .drawing(start: p)
            draft = Annotation(shape: draftShape(from: p, to: p, shift: shift, previous: nil), style: style(for: tool))
            return .none
        }
    }

    public func mouseDragged(to p: Point2D, shift: Bool) {
        switch drag {
        case .drawing(let start):
            guard let current = draft else { return }
            draft?.shape = draftShape(from: start, to: p, shift: shift, previous: current.shape)
        case .moving(let id, let last):
            let d = Point2D(x: p.x - last.x, y: p.y - last.y)
            document.update { state in
                if let index = state.index(of: id) {
                    state.annotations[index].shape = state.annotations[index].shape.translated(by: d)
                }
            }
            drag = .moving(id: id, last: p)
        case .resizing(let id, let original, let handle, let grabOffset):
            let target = Point2D(x: p.x + grabOffset.x, y: p.y + grabOffset.y)
            document.update { state in
                if let index = state.index(of: id) {
                    state.annotations[index].shape = original.resized(handle, to: target)
                }
            }
        case .cropping(let start):
            draftCrop = Rect2D(x: start.x, y: start.y, width: p.x - start.x, height: p.y - start.y).standardized
        case nil:
            break
        }
    }

    public func mouseUp(at p: Point2D, shift: Bool) {
        guard let current = drag else { return }
        mouseDragged(to: p, shift: shift)
        drag = nil
        switch current {
        case .drawing:
            let finished = draft
            draft = nil
            if let finished, let added = finalize(finished) {
                document.apply { $0.annotations.append(added) }
            }
        case .moving, .resizing:
            document.endChange()
        case .cropping:
            let rect = draftCrop
            draftCrop = nil
            if let rect, let crop = EditorGeometry.clampedCrop(rect, imageSize: imageSize) {
                document.apply { $0.crop = crop }
            }
        }
    }

    /// Esc: cancels a drag with no step, else deselects (E15).
    public func escape() {
        if drag != nil {
            cancelDrag()
        } else {
            selection = nil
        }
    }

    private func cancelDrag() {
        switch drag {
        case .moving, .resizing: document.cancelChange()
        case .drawing, .cropping, nil: break
        }
        drag = nil
        draft = nil
        draftCrop = nil
    }

    // MARK: Commands

    /// Backspace, Delete, Edit ▸ Delete: removes the selection in one step. False when nothing is selected.
    @discardableResult public func deleteSelection() -> Bool {
        guard drag == nil, let id = selection, document.state.annotation(id) != nil else { return false }
        finishPendingChanges()
        document.apply { $0.annotations.removeAll { $0.id == id } }
        selection = nil
        return true
    }

    public var canUndo: Bool { drag == nil && document.canUndo }
    public var canRedo: Bool { drag == nil && document.canRedo }

    /// Ignored during a drag (E15). Clears a selection whose annotation is gone (U7).
    public func undo() {
        guard drag == nil else { return }
        finishPendingChanges()
        document.undo()
        clearStaleSelection()
    }

    public func redo() {
        guard drag == nil else { return }
        finishPendingChanges()
        document.redo()
        clearStaleSelection()
    }

    public func resetCrop() {
        finishPendingChanges()
        document.apply { $0.crop = nil }
    }

    /// Turning the frame on sets the defaults (§5.6); either way one step.
    public func setFrameEnabled(_ enabled: Bool) {
        finishPendingChanges()
        document.apply { $0.frame = enabled ? BackgroundFrame() : nil }
    }

    /// A slider drag: begin, any number of `setFrame`, end → one step.
    public func beginFrameChange() {
        finishPendingChanges()
        document.beginChange()
        frameDragOpen = true
    }

    /// Outside a slider drag, opens a run the next other edit closes (U5, `e68db00`).
    public func setFrame(_ frame: BackgroundFrame) {
        if !frameDragOpen && !frameRunOpen {
            finishPendingChanges()
            document.beginChange()
            frameRunOpen = true
        }
        document.update { $0.frame = frame }
    }

    public func endFrameChange() {
        guard frameDragOpen else { return }
        frameDragOpen = false
        document.endChange()
    }

    // MARK: Text

    /// Adds, replaces or removes per §5.4: empty or whitespace-only text adds nothing and empties a re-edited
    /// annotation away; an unchanged re-edit makes no step.
    public func commitText(_ string: String) {
        guard let entry = textEntry else { return }
        textEntry = nil
        let isEmpty = string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let id = entry.editingID {
            document.apply { state in
                guard let index = state.index(of: id) else { return }
                if isEmpty {
                    state.annotations.remove(at: index)
                } else if case .text(let origin, _, let fontSize) = state.annotations[index].shape {
                    state.annotations[index].shape = .text(origin: origin, string: string, fontSize: fontSize)
                }
            }
            if isEmpty, selection == id { selection = nil }
        } else if !isEmpty {
            var style = style(for: .text)
            style.color = entry.color
            let text = Annotation(
                shape: .text(origin: entry.origin, string: string, fontSize: entry.fontSize), style: style)
            document.apply { $0.annotations.append(text) }
        }
    }

    public func cancelText() {
        textEntry = nil
    }

    // MARK: Helpers

    private func selectDown(at p: Point2D, clickCount: Int) -> InteractionResult {
        let state = displayState
        if let id = selection, let selected = state.annotation(id) {
            let half = pixels(fromScreenPoints: Self.handleSize) / 2
            if let handle = selected.handles(metrics).last(where: {
                abs($0.point.x - p.x) <= half && abs($0.point.y - p.y) <= half
            }) {
                document.beginChange()
                drag = .resizing(
                    id: id, original: selected.shape, handle: handle.handle,
                    grabOffset: Point2D(x: handle.point.x - p.x, y: handle.point.y - p.y))
                return .none
            }
        }
        guard let hit = topmostHit(at: p, where: { _ in true }) else {
            selection = nil
            return .none
        }
        select(hit)
        if clickCount >= 2, case .text = hit.shape {
            return beginEditing(hit)
        }
        document.beginChange()
        drag = .moving(id: hit.id, last: p)
        return .none
    }

    private func select(_ annotation: Annotation) {
        selection = annotation.id
        options = Self.loadOptions(options, from: annotation)
    }

    private func beginEditing(_ annotation: Annotation) -> InteractionResult {
        guard case .text(let origin, let string, let fontSize) = annotation.shape else { return .none }
        let entry = TextEntry(
            origin: origin, editingID: annotation.id, string: string, fontSize: fontSize, color: annotation.style.color)
        textEntry = entry
        return .beginTextEntry(entry)
    }

    private func topmostHit(at p: Point2D, where include: (Annotation) -> Bool) -> Annotation? {
        let tolerance = pixels(fromScreenPoints: Self.hitDistance)
        return displayState.annotations.reversed().first { include($0) && $0.hitTest(p, tolerance: tolerance, metrics) }
    }

    private func clearStaleSelection() {
        if let id = selection, document.state.annotation(id) == nil { selection = nil }
    }

    private func contains(_ r: Rect2D, _ p: Point2D) -> Bool {
        p.x >= r.minX && p.x <= r.maxX && p.y >= r.minY && p.y <= r.maxY
    }

    private func style(for tool: EditorTool) -> AnnotationStyle {
        AnnotationStyle(
            color: options.color, width: options.width, shadow: tool.options.contains(.shadow) && options.shadow)
    }

    private func draftShape(from start: Point2D, to p: Point2D, shift: Bool, previous: AnnotationShape?)
        -> AnnotationShape
    {
        switch tool {
        case .arrow: .arrow(from: start, to: shift ? EditorGeometry.snapped45(from: start, to: p) : p)
        case .line: .line(from: start, to: shift ? EditorGeometry.snapped45(from: start, to: p) : p)
        case .rectangle: .rectangle(EditorGeometry.rect(from: start, to: p, square: shift), filled: options.filled)
        case .ellipse: .ellipse(EditorGeometry.rect(from: start, to: p, square: shift), filled: options.filled)
        case .blur:
            .blur(
                EditorGeometry.rect(from: start, to: p, square: false), mode: options.blurMode,
                strength: options.blurStrength)
        case .pen:
            if case .pen(let points) = previous { .pen(points.last == p ? points : points + [p]) } else { .pen([p]) }
        case .highlighter:
            if case .highlighter(let points) = previous {
                .highlighter(points.last == p ? points : points + [p])
            } else {
                .highlighter([p])
            }
        case .select, .crop, .text, .step: .pen([p])
        }
    }

    /// §5.4: a blur is clamped to the visible rect; anything not meaningful, or whose bounds miss the visible rect,
    /// is dropped.
    private func finalize(_ annotation: Annotation) -> Annotation? {
        var result = annotation
        result.shape = snapping(result.shape)
        let visible = visibleRect
        if case .blur(let rect, let mode, let strength) = result.shape {
            guard let clamped = rect.standardized.intersection(visible) else { return nil }
            result.shape = .blur(clamped, mode: mode, strength: strength)
        }
        guard result.shape.isMeaningful, EditorGeometry.overlaps(result.bounds(metrics), visible) else { return nil }
        return result
    }

    /// The selected annotation's style and tool options, loaded before any restyle (`dbadb7c`).
    static func loadOptions(_ options: ToolOptions, from annotation: Annotation) -> ToolOptions {
        var o = options
        let tool = annotation.shape.tool
        if tool.options.contains(.color) { o.color = annotation.style.color }
        if tool.options.contains(.width) { o.width = annotation.style.width }
        if tool.options.contains(.shadow) { o.shadow = annotation.style.shadow }
        switch annotation.shape {
        case .rectangle(_, let filled), .ellipse(_, let filled): o.filled = filled
        case .text(_, _, let fontSize): o.fontSize = fontSize
        case .blur(_, let mode, let strength):
            o.blurMode = mode
            o.blurStrength = strength
        default: break
        }
        return o
    }

    /// The annotation with the options its tool shows applied.
    static func restyle(_ annotation: Annotation, with o: ToolOptions) -> Annotation {
        var a = annotation
        let tool = a.shape.tool
        if tool.options.contains(.color) { a.style.color = o.color }
        if tool.options.contains(.width) { a.style.width = o.width }
        if tool.options.contains(.shadow) { a.style.shadow = o.shadow }
        switch a.shape {
        case .rectangle(let rect, _): a.shape = .rectangle(rect, filled: o.filled)
        case .ellipse(let rect, _): a.shape = .ellipse(rect, filled: o.filled)
        case .text(let origin, let string, _): a.shape = .text(origin: origin, string: string, fontSize: o.fontSize)
        case .blur(let rect, _, _): a.shape = .blur(rect, mode: o.blurMode, strength: o.blurStrength)
        default: break
        }
        return a
    }
}
