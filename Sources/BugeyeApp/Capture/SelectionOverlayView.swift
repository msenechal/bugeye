import AppKit
import BugeyeCore
import CaptureCore
import MacAdapters

/// Draws one display's overlay from the controller's `OverlayRender` and turns `NSEvent`s into `FlowEvent`s, nothing
/// else (Capture §7). Its own coordinates are view-local (bottom-left, points), which `ViewPoint` names. Crosshair and
/// loupe are moved subviews: a mouse move never redraws the frozen image (design/02 §3.2).
@MainActor
final class SelectionOverlayView: NSView {
    let session: SessionID
    let display: DisplayInfo
    let image: CGImage?
    /// Image pixels per point (design/02 §2.3).
    let scale: Double
    /// Points from the display's top to its visible frame's top (the menu bar), for the hint.
    let visibleTopInset: Double
    /// What to draw now; nil once the selection has ended.
    var render: () -> OverlayRender? = { nil }
    var send: (FlowEvent) -> Void = { _ in }
    /// Every rect invalidated since creation (tests read it).
    private(set) var damage: NSRect = .zero

    private let horizontal = PassThroughView()
    private let vertical = PassThroughView()
    private var trackingArea: NSTrackingArea?
    private let loupe: LoupeView
    private var lastLabelFrame: NSRect?

    init(session: SessionID, display: DisplayInfo, image: CGImage?, pixelWidth: Int, visibleTopInset: Double) {
        self.session = session
        self.display = display
        self.image = image
        scale = display.frame.width > 0 ? Double(pixelWidth) / display.frame.width : 1
        self.visibleTopInset = visibleTopInset
        loupe = LoupeView(image: image)
        super.init(frame: NSRect(x: 0, y: 0, width: display.frame.width, height: display.frame.height))
        wantsLayer = true
        for line in [horizontal, vertical] {
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.6).cgColor
            addSubview(line)
        }
        addSubview(loupe)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    /// Every click inside the overlay is the overlay's own: the crosshair lines and the loupe never take it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        return bounds.contains(local) ? self : nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: Drawing

    var displaySize: Size2D { display.pointSize }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if let image { context.draw(image, in: bounds) }
        guard let state = render() else { return }
        let dim = NSColor.black.withAlphaComponent(0.4)
        switch state.mode {
        case .area:
            let path = NSBezierPath(rect: bounds)
            if let selection = state.selection.map(viewRect) {
                path.append(NSBezierPath(rect: selection))
                path.windingRule = .evenOdd
            }
            dim.setFill()
            path.fill()
            if let selection = state.selection {
                NSColor.white.setStroke()
                let border = NSBezierPath(rect: viewRect(selection).insetBy(dx: 0.5, dy: 0.5))
                border.lineWidth = 1
                border.stroke()
                drawReadout(for: selection)
            }
        case .window:
            dim.setFill()
            bounds.fill()
            if let hovered = state.hovered.map(viewRect) {
                context.saveGState()
                context.clip(to: hovered)
                if let image { context.draw(image, in: bounds) }
                context.restoreGState()
                NSColor.systemBlue.withAlphaComponent(0.2).setFill()
                hovered.fill(using: .sourceOver)
                NSColor.systemBlue.setStroke()
                let border = NSBezierPath(rect: hovered.insetBy(dx: 1.5, dy: 1.5))
                border.lineWidth = 3
                border.stroke()
            }
        }
        if let hint = state.hint { drawHint(hint) }
    }

    func viewRect(_ rect: DisplayRect) -> NSRect {
        let view = rect.viewRect(displayHeight: displaySize.height).raw
        return NSRect(x: view.minX, y: view.minY, width: view.width, height: view.height)
    }

    static let readoutAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white,
    ]
    static let hintAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white,
    ]
    static let boxPadding = NSSize(width: 10, height: 5)

    /// The readout's box in view coordinates for a selection.
    func readoutFrame(for selection: DisplayRect) -> NSRect {
        let text = NSAttributedString(
            string: SelectionGeometry.readoutText(selection), attributes: Self.readoutAttributes)
        let size = text.size()
        let box = Size2D(
            width: size.width + 2 * Self.boxPadding.width, height: size.height + 2 * Self.boxPadding.height)
        return viewRect(SelectionGeometry.readoutFrame(selection: selection, labelSize: box, displaySize: displaySize))
    }

    private func drawReadout(for selection: DisplayRect) {
        let frame = readoutFrame(for: selection)
        lastLabelFrame = frame
        drawBox(
            frame,
            text: NSAttributedString(
                string: SelectionGeometry.readoutText(selection), attributes: Self.readoutAttributes))
    }

    /// C22: centred, its top 12 pt below the top of the visible frame.
    func hintFrame(_ hint: String) -> NSRect {
        let size = NSAttributedString(string: hint, attributes: Self.hintAttributes).size()
        let width = size.width + 2 * Self.boxPadding.width
        let height = size.height + 2 * Self.boxPadding.height
        let top = bounds.height - visibleTopInset - 12
        return NSRect(x: (bounds.width - width) / 2, y: top - height, width: width, height: height)
    }

    private func drawHint(_ hint: String) {
        drawBox(hintFrame(hint), text: NSAttributedString(string: hint, attributes: Self.hintAttributes))
    }

    private func drawBox(_ frame: NSRect, text: NSAttributedString) {
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6).fill()
        text.draw(at: NSPoint(x: frame.minX + Self.boxPadding.width, y: frame.minY + Self.boxPadding.height))
    }

    /// Invalidates `rect` (display-local; nil for everything) plus the old and new readout boxes.
    func invalidate(_ rect: DisplayRect?) {
        var dirty = rect.map(viewRect) ?? bounds
        if rect != nil {
            if let old = lastLabelFrame { dirty = dirty.union(old) }
            if let selection = render()?.selection { dirty = dirty.union(readoutFrame(for: selection)) }
        }
        damage = damage.isEmpty ? dirty : damage.union(dirty)
        setNeedsDisplay(dirty)
        updateCursorViews()
    }

    // MARK: Crosshair and loupe

    private var pointer: NSPoint?

    /// Shows crosshair and loupe at a point in this view, without redrawing the frozen image.
    func showPointer(at point: NSPoint) {
        // A point outside the view (the pointer is on another display) hides crosshair and loupe.
        pointer = bounds.contains(point) ? point : nil
        updateCursorViews()
    }

    /// True while crosshair and loupe are shown (tests).
    var showsCursorViews: Bool { !horizontal.isHidden }

    private func updateCursorViews() {
        let areaMode = render()?.mode != .window
        let visible = areaMode && pointer != nil
        horizontal.isHidden = !visible
        vertical.isHidden = !visible
        loupe.isHidden = !visible
        guard visible, let pointer else { return }
        horizontal.frame = NSRect(x: 0, y: pointer.y.rounded(.down), width: bounds.width, height: 1)
        vertical.frame = NSRect(x: pointer.x.rounded(.down), y: 0, width: 1, height: bounds.height)
        let local = ViewPoint(x: pointer.x, y: pointer.y).displayLocal(displayHeight: displaySize.height)
        loupe.frame = viewRect(SelectionGeometry.loupeFrame(pointer: local, displaySize: displaySize))
        if let image {
            loupe.sample = SelectionGeometry.loupeSample(
                pointerPixelX: Int(local.x * scale), pointerPixelY: Int(local.y * scale), imageWidth: image.width,
                imageHeight: image.height)
        }
    }

    // MARK: Events → flow

    func viewPoint(_ event: NSEvent) -> ViewPoint {
        let point = convert(event.locationInWindow, from: nil)
        return ViewPoint(x: point.x, y: point.y)
    }

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> Modifiers {
        Modifiers(shift: flags.contains(.shift), option: flags.contains(.option))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = viewPoint(event)
        showPointer(at: NSPoint(x: point.x, y: point.y))
        send(.pointerMoved(session, display.id, point))
    }

    override func mouseExited(with event: NSEvent) {
        pointer = nil
        updateCursorViews()
    }

    override func mouseEntered(with event: NSEvent) {
        // A finished selection's view ignores a late mouseEntered (design/02 §3.1); the flow checks it too.
        guard render() != nil else { return }
        send(.pointerEntered(session, display.id, buttonDown: NSEvent.pressedMouseButtons != 0))
    }

    override func mouseDown(with event: NSEvent) {
        send(.mouseDown(session, display.id, viewPoint(event), Self.modifiers(event.modifierFlags)))
    }

    override func mouseDragged(with event: NSEvent) {
        let point = viewPoint(event)
        showPointer(at: NSPoint(x: point.x, y: point.y))
        send(.mouseDragged(session, display.id, point, Self.modifiers(event.modifierFlags)))
    }

    override func mouseUp(with event: NSEvent) {
        send(.mouseUp(session, display.id, viewPoint(event)))
    }

    override func rightMouseDown(with event: NSEvent) {
        send(.rightMouseDown(session))
    }

    /// Esc, Space and Return; a held Space or Return doesn't repeat, and other keys are dropped without a beep.
    override func keyDown(with event: NSEvent) {
        guard let key = Self.key(event.keyCode) else { return }
        if event.isARepeat, key != .escape { return }
        send(.key(session, key))
    }

    /// 53 Esc, 49 Space, 36 Return, 76 keypad Enter.
    static func key(_ code: UInt16) -> KeyPress? {
        switch code {
        case 53: .escape
        case 49: .space
        case 36, 76: .return
        default: nil
        }
    }
}

/// A view that never takes a click (the crosshair lines).
@MainActor
final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A 120 pt circle magnifying a 15 × 15-pixel sample without smoothing, with a white 2 pt ring and a red square
/// on the pointer's pixel (Capture §5.2). Redraws only itself.
@MainActor
final class LoupeView: NSView {
    let image: CGImage?
    var sample: LoupeSample? {
        didSet { if sample != oldValue { needsDisplay = true } }
    }

    init(image: CGImage?) {
        self.image = image
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let image, let sample else { return }
        let circle = bounds.insetBy(dx: 1, dy: 1)
        context.saveGState()
        context.addEllipse(in: circle)
        context.clip()
        context.interpolationQuality = .none
        let r = sample.rect.raw
        if let crop = image.cropping(to: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height)) {
            context.draw(crop, in: circle)
        }
        let cell = circle.width / Double(SelectionGeometry.loupeSamplePixels)
        let marker = NSRect(
            x: circle.minX + Double(sample.markerColumn) * cell,
            y: circle.maxY - Double(sample.markerRow + 1) * cell, width: cell, height: cell)
        NSColor.systemRed.setStroke()
        NSBezierPath(rect: marker).stroke()
        context.restoreGState()
        NSColor.white.setStroke()
        let ring = NSBezierPath(ovalIn: circle)
        ring.lineWidth = 2
        ring.stroke()
    }
}
