import AppKit
import BugeyeCore
import MacAdapters
import RecordingCore

/// The click rings and keystroke badge over the recorded area (§5.4), drawn through the Editor's display-list
/// executor (contracts K10). One borderless, click-through window at `.screenSaver` level; in the video (an
/// exception to the app's exclusion). A 60 Hz timer in `.common` modes runs only while something animates, then
/// draws one last empty frame and stops.
@MainActor
final class RecordingOverlay: OverlayPresenting {
    private let window: OverlayWindow
    private let view: OverlayView
    private var timer: Timer?
    private var clicks = false
    private var keys = false
    private var showAllKeys = false
    /// The area's top-left in Quartz global points: clicks arrive in Quartz points.
    private var origin: CGPoint = .zero
    private let primaryHeight: @MainActor () -> CGFloat
    private let now: @MainActor () -> Double

    init(
        measurer: any TextMeasuring = CoreTextMeasurer(),
        primaryHeight: @escaping @MainActor () -> CGFloat = { NSScreen.screens.first?.frame.height ?? 0 },
        now: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }
    ) {
        view = OverlayView(measurer: measurer)
        window = OverlayWindow(view: view)
        self.primaryHeight = primaryHeight
        self.now = now
    }

    isolated deinit {
        timer?.invalidate()
    }

    var windowIDs: [CGWindowID] {
        window.windowNumber > 0 ? [CGWindowID(window.windowNumber)] : []
    }

    func show(area: CGRect) {
        place(area)
        window.orderFrontRegardless()
    }

    func start(area: CGRect, clicks: Bool, keys: Bool, showAllKeys: Bool) {
        self.clicks = clicks
        self.keys = keys
        self.showAllKeys = showAllKeys
        show(area: area)
    }

    func click(_ button: TimelineButton, at quartz: Point2D) {
        guard clicks else { return }
        view.rings.click(button, at: Point2D(x: quartz.x - origin.x, y: quartz.y - origin.y), time: now())
        animate()
    }

    func key(_ press: KeyPress) {
        guard keys, !press.isRepeat,
            let label = KeystrokeFormatter.label(
                keyCode: press.keyCode, characters: press.characters, modifiers: press.modifiers,
                showAllKeys: showAllKeys)
        else { return }
        view.badge.press(label, at: now())
        animate()
    }

    func move(area: CGRect) { place(area) }

    func stop() {
        timer?.invalidate()
        timer = nil
        view.rings = ClickRings()
        view.badge = KeystrokeBadge()
        window.orderOut(nil)
    }

    /// Whether the timer is running (tests).
    var isAnimating: Bool { timer != nil }

    private func place(_ area: CGRect) {
        origin = CGPoint(x: area.minX, y: primaryHeight() - area.maxY)
        window.setFrame(area, display: true)
    }

    private func animate() {
        view.time = now()
        view.needsDisplay = true
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.frame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func frame() {
        let time = now()
        view.time = time
        view.needsDisplay = true
        if !view.rings.isAnimating(at: time), !view.badge.isVisible(at: time) {
            // The frame just requested is the last, empty one.
            timer?.invalidate()
            timer = nil
        }
    }
}

final class OverlayWindow: NSWindow {
    init(view: NSView) {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        contentView = view
    }
}

/// Draws the rings and the badge, top-left in the area's points (the list's size), through the executor.
final class OverlayView: NSView {
    var rings = ClickRings()
    var badge = KeystrokeBadge()
    var time = 0.0
    private let measurer: any TextMeasuring
    private let executor = DisplayListExecutor()

    init(measurer: any TextMeasuring) {
        self.measurer = measurer
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override var isFlipped: Bool { true }

    /// The lists drawn at `time` (tests).
    func lists() -> [DisplayList] {
        let size = Size2D(width: bounds.width, height: bounds.height)
        var lists = [rings.displayList(at: time, area: size)]
        if let badgeList = badge.displayList(at: time, area: size, measurer: measurer) { lists.append(badgeList) }
        return lists
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        for list in lists() { executor.execute(list, in: context, contextIsFlipped: true) }
    }
}
