import AppKit
import BugeyeCore
import BugeyeFeatures
import EditorCore
import MacAdapters

/// What the canvas tells its window controller.
@MainActor
protocol EditorCanvasDelegate: AnyObject {
    /// The document, the selection, the tool or the options changed: refresh the chrome.
    func canvasDidChange()
    /// A letter key chose a tool.
    func canvasSelect(_ tool: EditorTool)
}

/// The flipped canvas (§4, §8.1): one view point per canvas point (canvas pixels / ppp), the scroll view's
/// magnification does the zoom. Draws the cached base, then the active annotation and the overlay live (E10).
/// Owns the one reusable text view (E6).
@MainActor
final class EditorCanvasView: NSView, NSTextViewDelegate {
    let controller: InteractionController
    let capture: CGImage
    let blurCache: BlurCache
    weak var delegate: EditorCanvasDelegate?

    /// The rasterised base and the list it was made from (`645eecd`).
    private var cachedBase: (list: DisplayList, image: CGImage)?
    /// How many times the base was rasterised: a test hook.
    private(set) var baseRenderCount = 0

    /// The one text view, created on first use and reused (E6, `design/03` §5.4).
    private(set) var textView: NSTextView?
    private var textUndoManager = UndoManager()

    init(controller: InteractionController, capture: CGImage, blurCache: BlurCache) {
        self.controller = controller
        self.capture = capture
        self.blurCache = blurCache
        super.init(frame: .zero)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var ppp: Double { controller.metrics.ppp }
    var isEditingText: Bool { textView.map { !$0.isHidden } ?? false }

    /// Resizes to the layout, redraws, resets cursors and tells the delegate.
    func refresh() {
        let size = controller.layout.size
        let frameSize = NSSize(width: size.width / ppp, height: size.height / ppp)
        if frame.size != frameSize { setFrameSize(frameSize) }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        delegate?.canvasDidChange()
    }

    // MARK: Drawing

    func currentLists() -> EditorLists {
        EditorRenderer.lists(
            state: controller.displayState, layout: controller.layout, metrics: controller.metrics,
            active: controller.activeID, hidden: controller.hiddenID,
            selection: controller.tool == .select ? controller.selection : nil, cropMode: controller.showsFullImage,
            zoom: controller.zoom)
    }

    private func executor() -> DisplayListExecutor {
        let capture = self.capture
        let cache = blurCache
        let base = cachedBase?.image
        return DisplayListExecutor(
            images: { id in
                switch id {
                case EditorRenderer.captureImageID: capture
                case "base": base
                default: nil
                }
            },
            blur: { _, rect, effect in
                cache.imageOrSchedule(capture, rect: rect, effect: effect) { [weak self] in
                    self?.cachedBase = nil
                    self?.needsDisplay = true
                }
            })
    }

    /// The base, rasterised again only when its list changed.
    func baseImage(for list: DisplayList) -> CGImage? {
        if let cachedBase, cachedBase.list == list { return cachedBase.image }
        guard let image = executor().render(list, colorSpace: EditorImages.workingSpace(of: capture)) else {
            return nil
        }
        baseRenderCount += 1
        cachedBase = (list, image)
        return image
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let lists = currentLists()
        _ = baseImage(for: lists.base)
        context.saveGState()
        context.scaleBy(x: 1 / ppp, y: 1 / ppp)
        let executor = executor()
        let base = DisplayList(
            size: lists.base.size,
            commands: [.image(imageID: "base", rect: Rect2D(origin: .zero, size: lists.base.size))])
        executor.execute(base, in: context, contextIsFlipped: true)
        executor.execute(lists.active, in: context, contextIsFlipped: true)
        executor.execute(lists.overlay, in: context, contextIsFlipped: true)
        context.restoreGState()
    }

    // MARK: Cursor

    override func resetCursorRects() {
        let cursor: NSCursor =
            switch controller.tool.cursor {
            case .arrow: .arrow
            case .iBeam: .iBeam
            case .crosshair: .crosshair
            }
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: Mouse

    /// View points → image pixels through the layout (§4).
    func imagePoint(_ event: NSEvent) -> Point2D {
        let p = convert(event.locationInWindow, from: nil)
        return controller.layout.imagePoint(fromCanvas: Point2D(x: p.x * ppp, y: p.y * ppp))
    }

    override func mouseDown(with event: NSEvent) {
        // A click elsewhere while typing commits and does nothing else (§5.4).
        if isEditingText {
            commitText()
            return
        }
        window?.makeFirstResponder(self)
        let result = controller.mouseDown(
            at: imagePoint(event), clickCount: event.clickCount, shift: event.modifierFlags.contains(.shift))
        if case .beginTextEntry(let entry) = result { showTextView(entry) }
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        guard controller.isDragging else { return }
        controller.mouseDragged(to: imagePoint(event), shift: event.modifierFlags.contains(.shift))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard controller.isDragging else { return }
        controller.mouseUp(at: imagePoint(event), shift: event.modifierFlags.contains(.shift))
        refresh()
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        var modifiers: Set<KeyModifier> = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        switch EditorShortcuts.action(
            keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "", modifiers: modifiers)
        {
        case .tool(let tool): delegate?.canvasSelect(tool)
        case .escape:
            controller.escape()
            refresh()
        case .delete:
            if controller.deleteSelection() { refresh() } else { super.keyDown(with: event) }
        case nil: super.keyDown(with: event)
        }
    }

    // MARK: Text entry

    func showTextView(_ entry: TextEntry) {
        let view = textView ?? makeTextView()
        textUndoManager = UndoManager()
        view.font = NSFont.boldSystemFont(ofSize: entry.fontSize)
        view.textColor = NSColor(
            srgbRed: entry.color.red, green: entry.color.green, blue: entry.color.blue, alpha: entry.color.alpha)
        view.insertionPointColor = view.textColor ?? .labelColor
        view.string = entry.string
        let canvas = controller.layout.canvasPoint(fromImage: entry.origin)
        let origin = NSPoint(x: canvas.x / ppp, y: canvas.y / ppp)
        view.frame = NSRect(origin: origin, size: NSSize(width: max(80, bounds.width - origin.x), height: 10))
        view.sizeToFit()
        view.isHidden = false
        window?.makeFirstResponder(view)
        view.selectAll(nil)
        needsDisplay = true
    }

    private func makeTextView() -> NSTextView {
        let view = NSTextView(frame: .zero)
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.isHorizontallyResizable = true
        view.isVerticallyResizable = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.delegate = self
        view.isHidden = true
        addSubview(view)
        textView = view
        return view
    }

    /// Commits typed text, if any (§5.4: before every toolbar, options or frame action, undo, save, copy, close or
    /// tool change). Returns true when a text view was up.
    @discardableResult func commitText() -> Bool {
        guard let view = textView, !view.isHidden else { return false }
        let string = view.string
        hideTextView()
        controller.commitText(string)
        refresh()
        return true
    }

    func cancelText() {
        guard isEditingText else { return }
        hideTextView()
        controller.cancelText()
        refresh()
    }

    private func hideTextView() {
        guard let view = textView else { return }
        view.isHidden = true
        view.string = ""
        if window?.firstResponder === view { window?.makeFirstResponder(self) }
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                commitText()
            }
            return true
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            textView.insertNewlineIgnoringFieldEditor(nil)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancelText()
            return true
        default:
            return false
        }
    }

    func textDidChange(_ notification: Notification) {
        textView?.sizeToFit()
    }

    /// ⌘Z while typing undoes the typing, not the document (§5.4).
    func undoManager(for view: NSTextView) -> UndoManager? { textUndoManager }
}

/// Centres a document smaller than the viewport (`design/03` §1.6).
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        let size = document.frame.size
        if rect.width > size.width { rect.origin.x = (size.width - rect.width) / 2 }
        if rect.height > size.height { rect.origin.y = (size.height - rect.height) / 2 }
        return rect
    }
}
