import AppKit
import BugeyeCore
import EditorCore
import MacAdapters
import SwiftUI

/// One editor window (§5.1, §5.2): toolbar, canvas in a centring scroll view, options strip. Answers the main
/// menu's selectors as the window's delegate, after the canvas in the responder chain; while the text view has
/// focus, it answers Cut, Copy, Paste, Delete, Select All, Undo and Redo itself (E24, §5.4).
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate, NSMenuItemValidation, EditorCanvasDelegate {
    let session: EditorSession
    let controller: InteractionController
    let canvas: EditorCanvasView
    let scrollView: NSScrollView
    let window: NSWindow
    let model = EditorViewModel()
    private weak var manager: EditorManager?
    private var boundsObserver: (any NSObjectProtocol)?
    /// Set once the unsaved-changes prompt (or a clean document) allows the close.
    private var closeAllowed = false

    init(session: EditorSession, capture: CGImage, blurCache: BlurCache, manager: EditorManager) {
        self.session = session
        self.manager = manager
        controller = InteractionController(
            document: session.document ?? EditorDocument(), imageSize: session.imageSize,
            metrics: EditorMetrics(ppp: session.item.pixelsPerPoint, measurer: CoreTextMeasurer()))
        canvas = EditorCanvasView(controller: controller, capture: capture, blurCache: blurCache)

        let clip = CenteringClipView()
        scrollView = NSScrollView()
        scrollView.contentView = clip
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = ZoomModel.range.lowerBound
        scrollView.maxMagnification = ZoomModel.range.upperBound
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .underPageBackgroundColor

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()

        let toolbar = NSHostingView(rootView: EditorToolbarView(model: model))
        let strip = NSHostingView(rootView: EditorOptionsStripView(model: model))
        let stack = NSStackView(views: [toolbar, Self.divider(), scrollView, Self.divider(), strip])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        for view in stack.arrangedSubviews {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        toolbar.heightAnchor.constraint(equalToConstant: 40).isActive = true
        strip.heightAnchor.constraint(equalToConstant: 36).isActive = true
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        window.contentView = stack

        window.title = session.name
        window.representedURL = session.item.fileURL
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(
            width: WindowSizing.minimumContentSize.width, height: WindowSizing.minimumContentSize.height)
        window.delegate = self
        canvas.delegate = self
        wireModel()
        sizeWindow()

        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.zoomChanged() }
        }
        canvasDidChange()
    }

    private static func divider() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    /// The canvas + 40 pt + chrome, at most 85 % of the main screen, centred (§5.1).
    private func sizeWindow() {
        let canvasSize = controller.layout.size
        let ppp = controller.metrics.ppp
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let size = WindowSizing.initialContentSize(
            canvasPoints: Size2D(width: canvasSize.width / ppp, height: canvasSize.height / ppp),
            screenVisible: Size2D(width: screen.width, height: screen.height))
        window.setContentSize(NSSize(width: size.width, height: size.height))
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        zoomToFit(nil)
    }

    func bringForward() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func retitle() {
        window.title = session.name
        window.representedURL = session.item.fileURL
    }

    // MARK: Chrome

    private func wireModel() {
        model.onTool = { [weak self] tool in self?.selectTool(tool) }
        model.onOptions = { [weak self] options in
            guard let self else { return }
            canvas.commitText()
            controller.setOptions(options)
            canvas.refresh()
        }
        model.onFrameEnabled = { [weak self] enabled in
            guard let self else { return }
            canvas.commitText()
            controller.setFrameEnabled(enabled)
            canvas.refresh()
        }
        model.onFrameDrag = { [weak self] dragging in
            guard let self else { return }
            if dragging {
                canvas.commitText()
                controller.beginFrameChange()
            } else {
                controller.endFrameChange()
            }
            canvas.refresh()
        }
        model.onFrame = { [weak self] frame in
            guard let self else { return }
            controller.setFrame(frame)
            canvas.refresh()
        }
        model.onFrameApply = { [weak self] frame in
            guard let self else { return }
            canvas.commitText()
            controller.applyFrame(frame)
            canvas.refresh()
        }
        model.onResetCrop = { [weak self] in
            guard let self else { return }
            canvas.commitText()
            controller.resetCrop()
            canvas.refresh()
        }
        model.onUndo = { [weak self] in self?.undo(nil) }
        model.onRedo = { [weak self] in self?.redo(nil) }
        model.onCopy = { [weak self] in self?.copyImage() }
        model.onSave = { [weak self] in self?.saveDocument(nil) }
        model.onFrameButton = { [weak self] in
            guard let self else { return }
            canvas.commitText()
            model.showingFramePopover.toggle()
        }
        let id = session.id
        model.dragHandle = { [weak self] in
            EditorDragHandleView(
                writeFile: { [weak self] in
                    guard let manager = self?.manager else { throw EditorLoadFailure(reason: "no editor") }
                    return try await manager.sessions.writeDragFile(id)
                })
        }
    }

    func canvasDidChange() {
        model.update(from: controller)
        window.isDocumentEdited = controller.document.isDirty
    }

    func canvasSelect(_ tool: EditorTool) {
        selectTool(tool)
    }

    func selectTool(_ tool: EditorTool) {
        canvas.commitText()
        controller.setTool(tool)
        canvas.refresh()
    }

    // MARK: Zoom (§5.7)

    private func zoomChanged() {
        controller.zoom = Double(scrollView.magnification)
        canvas.needsDisplay = true
    }

    private func setZoom(_ zoom: Double) {
        scrollView.magnification = CGFloat(ZoomModel.clamp(zoom))
        zoomChanged()
    }

    @objc func zoomIn(_ sender: Any?) { setZoom(ZoomModel.zoomIn(Double(scrollView.magnification))) }
    @objc func zoomOut(_ sender: Any?) { setZoom(ZoomModel.zoomOut(Double(scrollView.magnification))) }
    @objc func zoomToActualSize(_ sender: Any?) { setZoom(ZoomModel.actualSize) }

    @objc func zoomToFit(_ sender: Any?) {
        let viewport = scrollView.contentSize
        let size = canvas.frame.size
        setZoom(
            ZoomModel.fit(
                viewport: Size2D(width: viewport.width, height: viewport.height),
                canvas: Size2D(width: size.width, height: size.height)))
    }

    // MARK: Edit menu (E24)

    @objc func undo(_ sender: Any?) {
        canvas.commitText()
        controller.undo()
        canvas.refresh()
    }

    @objc func redo(_ sender: Any?) {
        canvas.commitText()
        controller.redo()
        canvas.refresh()
    }

    @objc func copy(_ sender: Any?) { copyImage() }
    @objc func cut(_ sender: Any?) {}
    @objc func paste(_ sender: Any?) {}
    @objc func selectAll(_ sender: Any?) {}

    @objc func delete(_ sender: Any?) {
        if controller.deleteSelection() { canvas.refresh() }
    }

    private func copyImage() {
        canvas.commitText()
        guard let manager else { return }
        let id = session.id
        Task { await manager.sessions.copy(id) }
    }

    // MARK: File menu

    @objc func saveDocument(_ sender: Any?) {
        canvas.commitText()
        guard let manager else { return }
        let id = session.id
        Task { [weak self] in
            _ = await manager.sessions.save(id)
            self?.canvasDidChange()
        }
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        canvas.commitText()
        guard let manager else { return }
        let id = session.id
        Task { _ = await manager.sessions.saveAs(id) }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)): controller.canUndo
        case #selector(redo(_:)): controller.canRedo
        case #selector(cut(_:)), #selector(paste(_:)), #selector(selectAll(_:)): false
        case #selector(delete(_:)): controller.selection != nil && !controller.isDragging
        case #selector(zoomIn(_:)): scrollView.magnification < CGFloat(ZoomModel.range.upperBound)
        case #selector(zoomOut(_:)): scrollView.magnification > CGFloat(ZoomModel.range.lowerBound)
        default: true
        }
    }

    // MARK: Closing (§5.9)

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        canvas.commitText()
        if closeAllowed || !controller.document.isDirty { return true }
        guard let manager else { return true }
        let id = session.id
        Task { [weak self] in
            guard await manager.sessions.shouldClose(id), let self else { return }
            closeAllowed = true
            window.close()
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
        boundsObserver = nil
        model.dragHandle = { NSView() }
        manager?.windowClosed(self)
    }
}

/// The drag handle (§5.8, plan P11): mouse-down starts the export and the drag file off the main actor; the drag
/// begins on the first mouse-dragged event after the file is ready. A failure beeps and the drag never starts.
@MainActor
final class EditorDragHandleView: NSView, NSDraggingSource {
    private let writeFile: @MainActor () async throws -> URL
    private var pending: Task<URL?, Never>?
    private var ready: URL?

    init(writeFile: @escaping @MainActor () async throws -> URL) {
        self.writeFile = writeFile
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        let image = NSImageView(
            image: NSImage(
                systemSymbolName: EditorStrings.dragSymbol, accessibilityDescription: EditorStrings.dragTooltip)
                ?? NSImage())
        image.frame = bounds
        image.autoresizingMask = [.width, .height]
        addSubview(image)
        toolTip = EditorStrings.dragTooltip
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func mouseDown(with event: NSEvent) {
        ready = nil
        let write = writeFile
        pending = Task { [weak self] in
            do {
                let url = try await write()
                self?.ready = url
                return url
            } catch {
                NSSound.beep()
                return nil
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let url = ready else { return }
        ready = nil
        pending = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSImage(systemSymbolName: EditorStrings.dragSymbol, accessibilityDescription: nil) ?? NSImage()
        item.setDraggingFrame(bounds, contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        pending = nil
        ready = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation
    {
        .copy
    }
}
