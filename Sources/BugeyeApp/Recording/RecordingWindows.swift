import AVFoundation
import AppKit
import BugeyeCore
import RecordingCore
import SwiftUI

/// The set-up and recording windows (§5.1–5.4): border, options bar, countdown, webcam bubble, alerts.
/// Every one is excluded from the video by the app exclusion, except the bubble (an exception window).
@MainActor
final class RecordingWindows: RecordingSurfaces {
    struct Handlers {
        var bar: @MainActor (OptionsBarAction) -> Void = { _ in }
        var bubbleDoubleClicked: @MainActor () -> Void = {}
        var cameraFailed: @MainActor () -> Void = {}
    }

    var handlers = Handlers()
    private var border: BorderWindow?
    private var bar: OptionsPanel?
    private var barHost: NSHostingView<OptionsBarView>?
    private var barSelection: CGRect = .zero
    private var barWholeDisplay = false
    private var countdown: CountdownPanel?
    private(set) var bubble: WebcamBubble?
    private var bubbleCorner: BubbleCorner = .bottomRight
    private var bubbleArea: CGRect = .zero
    private var alertOpen = false

    // MARK: Border

    func showBorder(_ frame: CGRect, recording: Bool) {
        let window = border ?? BorderWindow()
        border = window
        window.show(around: frame, recording: recording, wholeDisplay: isWholeDisplay(frame))
    }

    func closeBorder() {
        border?.orderOut(nil)
        border = nil
    }

    // MARK: Options bar

    func showBar(around selection: CGRect, wholeDisplay: Bool, state: OptionsBarState) {
        closeBar()
        barSelection = selection
        barWholeDisplay = wholeDisplay
        let panel = OptionsPanel()
        panel.onCancel = { [weak self] in self?.handlers.bar(.cancel) }
        let host = NSHostingView(
            rootView: OptionsBarView(state: state, action: { [weak self] in self?.handlers.bar($0) }))
        panel.contentView = host
        bar = panel
        barHost = host
        place(panel, host: host)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func updateBar(_ state: OptionsBarState) {
        guard let panel = bar, let host = barHost else { return }
        host.rootView = OptionsBarView(state: state, action: { [weak self] in self?.handlers.bar($0) })
        place(panel, host: host)
    }

    func closeBar() {
        bar?.orderOut(nil)
        bar = nil
        barHost = nil
    }

    /// Re-placed whenever its width changes (`OptionsBarPlacement`).
    private func place(_ panel: NSPanel, host: NSView) {
        let size = host.fittingSize
        guard let screen = screen(containing: barSelection) else { return }
        let full = screen.frame
        let visible = screen.visibleFrame
        func topLeft(_ r: CGRect) -> Rect2D {
            Rect2D(x: r.minX, y: full.maxY - r.maxY, width: r.width, height: r.height)
        }
        let origin = OptionsBarPlacement.origin(
            bar: Size2D(width: size.width, height: size.height), selection: topLeft(barSelection),
            screen: topLeft(visible), wholeDisplay: barWholeDisplay)
        panel.setFrame(
            CGRect(x: origin.x, y: full.maxY - origin.y - size.height, width: size.width, height: size.height),
            display: true)
    }

    // MARK: Countdown

    func showCountdown(_ digit: Int, in frame: CGRect) {
        let panel = countdown ?? CountdownPanel()
        panel.onCancel = { [weak self] in self?.handlers.bar(.cancel) }
        countdown = panel
        panel.show(digit, centredIn: frame)
    }

    func closeCountdown() {
        countdown?.orderOut(nil)
        countdown = nil
    }

    // MARK: Bubble

    func setBubble(_ wish: BubbleWish?, area: CGRect) {
        bubbleArea = area
        let current = bubble.map { BubbleWish(cameraDevice: $0.cameraDevice, size: $0.size) }
        switch BubbleChange.decide(current: current, wish: wish) {
        case .none:
            return
        case .remove:
            bubble?.close()
            bubble = nil
        case .create, .recreate:
            bubble?.close()
            guard let wish else { return }
            let made = WebcamBubble(cameraDevice: wish.cameraDevice, size: wish.size)
            made.onDoubleClick = { [weak self] in self?.handlers.bubbleDoubleClicked() }
            made.onUnavailable = { [weak self] in self?.handlers.cameraFailed() }
            made.onDropped = { [weak self] centre in self?.dropped(at: centre) }
            bubble = made
            layoutBubble()
            made.orderFrontRegardless()
        case .resize:
            guard let wish else { return }
            bubble?.size = wish.size
            layoutBubble()
        }
    }

    func moveBubble(area: CGRect) {
        bubbleArea = area
        layoutBubble()
    }

    private func dropped(at centre: CGPoint) {
        guard let screen = screen(containing: bubbleArea) else { return }
        let top = screen.frame.maxY
        let area = Rect2D(
            x: bubbleArea.minX, y: top - bubbleArea.maxY, width: bubbleArea.width, height: bubbleArea.height)
        bubbleCorner = BubbleLayout.corner(nearest: Point2D(x: centre.x, y: top - centre.y), area: area)
        layoutBubble()
    }

    private func layoutBubble() {
        guard let bubble, let screen = screen(containing: bubbleArea) else { return }
        let top = screen.frame.maxY
        let area = Rect2D(
            x: bubbleArea.minX, y: top - bubbleArea.maxY, width: bubbleArea.width, height: bubbleArea.height)
        let frame = BubbleLayout.frame(corner: bubbleCorner, size: bubble.size, area: area)
        bubble.setFrame(
            CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height), display: true)
    }

    // MARK: Alerts (§5.3)

    func confirm(_ kind: ConfirmKind) async -> Bool {
        let alert = NSAlert()
        switch kind {
        case .restart:
            alert.messageText = RecordingStrings.restartTitle
            alert.informativeText = RecordingStrings.restartBody
            alert.addButton(withTitle: RecordingStrings.restart)
        case .discard:
            alert.messageText = RecordingStrings.discardTitle
            alert.informativeText = RecordingStrings.discardBody
            alert.addButton(withTitle: RecordingStrings.discard)
        }
        alert.addButton(withTitle: RecordingStrings.cancel)
        NSApp.activate()
        alertOpen = true
        defer { alertOpen = false }
        return alert.runModal() == .alertFirstButtonReturn
    }

    func dismissConfirm() {
        if alertOpen { NSApp.abortModal() }
    }

    // MARK: Helpers

    private func screen(containing frame: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
    }

    private func isWholeDisplay(_ frame: CGRect) -> Bool {
        NSScreen.screens.contains { $0.frame == frame }
    }
}

// MARK: - Border (§5.1)

/// 2 pt white dashed (6 on, 4 off) while configuring, solid systemRed 2 pt while recording, 3 pt outside the
/// area (inset 3 pt for a whole display). Borderless, click-through, `.statusBar` level, never in the video.
final class BorderWindow: NSWindow {
    static let gap: CGFloat = 3
    private let line = BorderView()

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        isReleasedWhenClosed = false
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = line
    }

    func show(around area: CGRect, recording: Bool, wholeDisplay: Bool) {
        let frame = wholeDisplay ? area : area.insetBy(dx: -Self.gap - 2, dy: -Self.gap - 2)
        setFrame(frame, display: false)
        line.recording = recording
        line.wholeDisplay = wholeDisplay
        line.needsDisplay = true
        orderFrontRegardless()
    }
}

final class BorderView: NSView {
    var recording = false
    var wholeDisplay = false

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = wholeDisplay ? BorderWindow.gap + 1 : 1
        let path = NSBezierPath(rect: bounds.insetBy(dx: inset, dy: inset))
        path.lineWidth = 2
        if recording {
            NSColor.systemRed.setStroke()
        } else {
            NSColor.white.setStroke()
            path.setLineDash([6, 4], count: 2, phase: 0)
        }
        path.stroke()
    }
}

// MARK: - Options bar (§5.2)

/// `[.nonactivatingPanel, .borderless]`, `.statusBar`, can become key, stays when Bugeye deactivates; Esc through
/// both `keyDown` (53) and `cancelOperation(_:)` (a focused toggle sends the latter, `design/04` §3).
final class OptionsPanel: NSPanel {
    var onCancel: () -> Void = {}

    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel() } else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { onCancel() }
}

struct OptionsBarView: View {
    let state: OptionsBarState
    let action: (OptionsBarAction) -> Void

    typealias S = RecordingStrings

    var body: some View {
        HStack(spacing: 10) {
            Button(S.record) { action(.record) }
                .keyboardShortcut(.defaultAction)
                .tint(.red)
                .buttonStyle(.borderedProminent)
                .help(S.recordTooltip)
            micControl
            toggle(S.systemAudio, isOn: state.options.systemAudio, help: S.systemAudioTooltip) {
                action(.change(.systemAudio($0)))
            }
            camControl
            toggle(S.keys, isOn: state.options.keys, help: keysHelp) { action(.change(.keys($0))) }
            toggle(S.clicks, isOn: state.options.clicks, help: S.clicksTooltip) { action(.change(.clicks($0))) }
            Menu("⚙") {
                Menu(S.frameRate) {
                    Button(S.fps30) { action(.change(.fps(30))) }
                    Button(S.fps60) { action(.change(.fps(60))) }
                }
                Menu(S.quality) {
                    Button(S.standard) { action(.change(.quality(.standard))) }
                    Button(S.high) { action(.change(.quality(.high))) }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(S.optionsTooltip)
            Button("✕") { action(.cancel) }
                .buttonStyle(.plain)
                .help(S.cancelTooltip)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(NightChrome.color(NightChrome.textHex))
        .background(
            LinearGradient(
                colors: [
                    NightChrome.color(NightChrome.gradientTopHex), NightChrome.color(NightChrome.gradientBottomHex),
                ],
                startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .fixedSize()
    }

    @ViewBuilder private var micControl: some View {
        let denied = state.permissions.microphone == .denied
        HStack(spacing: 4) {
            toggle(S.mic, isOn: state.options.mic && !denied, help: denied ? S.micDenied : S.micTooltip) {
                action(.change(.mic($0)))
            }
            .disabled(denied)
            if state.effective.mic {
                Picker(
                    "", selection: Binding(get: { state.options.micDevice }, set: { action(.change(.micDevice($0))) })
                ) {
                    Text(S.defaultDevice).tag("")
                    ForEach(state.microphones, id: \.id) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    @ViewBuilder private var camControl: some View {
        let denied = state.permissions.camera == .denied
        let none = state.cameras.isEmpty
        HStack(spacing: 2) {
            toggle(
                S.cam, isOn: state.options.camera && !denied && !none,
                help: none ? S.noCamera : denied ? S.cameraDenied : S.camTooltip
            ) { action(.change(.camera($0))) }
            .disabled(denied || none)
            Menu("⌄") {
                Menu(S.size) {
                    Button(S.small) { action(.change(.bubbleSize(.small))) }
                    Button(S.medium) { action(.change(.bubbleSize(.medium))) }
                    Button(S.large) { action(.change(.bubbleSize(.large))) }
                }
                if state.cameras.count > 1 {
                    Menu(S.camera) {
                        ForEach(state.cameras, id: \.id) { camera in
                            Button(camera.name) { action(.change(.cameraDevice(camera.id))) }
                        }
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(denied || none)
        }
    }

    private var keysHelp: String {
        state.permissions.accessibility == .granted ? S.keysTooltip : S.keysNeedAccessibility
    }

    private func toggle(_ title: String, isOn: Bool, help: String, set: @escaping (Bool) -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: set))
            .toggleStyle(.button)
            .help(help)
    }
}

// MARK: - Countdown (§5.1, V22)

/// 140 × 140 pt, night gradient, 28 pt corners, 72 pt bold digits in the accent colour. Made key without
/// activating Bugeye, so it takes Esc itself (`keyDown` 53 and `cancelOperation(_:)`).
final class CountdownPanel: NSPanel {
    static let side: CGFloat = 140
    var onCancel: () -> Void = {}
    private let host = NSHostingView(rootView: CountdownView(digit: 3))

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: Self.side, height: Self.side),
            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = host
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel() } else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { onCancel() }

    func show(_ digit: Int, centredIn area: CGRect) {
        host.rootView = CountdownView(digit: digit)
        setFrame(
            CGRect(x: area.midX - Self.side / 2, y: area.midY - Self.side / 2, width: Self.side, height: Self.side),
            display: true)
        orderFrontRegardless()
        makeKey()
    }
}

struct CountdownView: View {
    let digit: Int

    var body: some View {
        Text("\(digit)")
            .font(.system(size: 72, weight: .bold))
            .foregroundStyle(NightChrome.color(NightChrome.accentHex))
            .frame(width: CountdownPanel.side, height: CountdownPanel.side)
            .background(
                LinearGradient(
                    colors: [
                        NightChrome.color(NightChrome.gradientTopHex), NightChrome.color(NightChrome.gradientBottomHex),
                    ], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 28))
    }
}

// MARK: - Webcam bubble (§5.4)

/// Round, mirrored, 3 pt white border, shadow. Dragged anywhere; on release the window reports its centre so the
/// owner snaps it to a corner. Double-click cycles the size. In the video (an exception window).
final class WebcamBubble: NSPanel {
    let cameraDevice: String
    var size: BubbleSize
    var onDoubleClick: () -> Void = {}
    var onUnavailable: () -> Void = {}
    var onDropped: (CGPoint) -> Void = { _ in }
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "dev.msenechal.bugeye.recording.camera")
    private var observers: [NSObjectProtocol] = []
    private var dragStart: CGPoint?

    init(cameraDevice: String, size: BubbleSize) {
        self.cameraDevice = cameraDevice
        self.size = size
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: size.diameter, height: size.diameter),
            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .screenSaver
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let view = NSView()
        view.wantsLayer = true
        contentView = view
        configure(view)
    }

    private func configure(_ view: NSView) {
        let device =
            AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video,
                position: .unspecified
            ).devices.first { $0.uniqueID == cameraDevice } ?? AVCaptureDevice.default(for: .video)
        guard let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            DispatchQueue.main.async { [weak self] in self?.onUnavailable() }
            return
        }
        session.sessionPreset = .high
        session.addInput(input)
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.connection?.automaticallyAdjustsVideoMirroring = false
        preview.connection?.isVideoMirrored = true
        preview.frame = view.bounds
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        preview.borderColor = NSColor.white.cgColor
        preview.borderWidth = 3
        preview.masksToBounds = true
        view.layer?.addSublayer(preview)
        let center = NotificationCenter.default
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observers.append(
                center.addObserver(forName: name, object: session, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onUnavailable() }
                })
        }
        let session = UncheckedBox(session)
        sessionQueue.async { session.value.startRunning() }
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        contentView?.layer?.sublayers?.forEach { $0.cornerRadius = frameRect.width / 2 }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick()
            return
        }
        dragStart = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let mouse = NSEvent.mouseLocation
        setFrameOrigin(CGPoint(x: mouse.x - start.x, y: mouse.y - start.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragStart = nil
        onDropped(CGPoint(x: frame.midX, y: frame.midY))
    }

    override func close() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        let session = UncheckedBox(session)
        sessionQueue.async { session.value.stopRunning() }
        super.close()
    }
}

// MARK: - Recording pane (§4)

struct RecordingPane: View {
    let store: any SettingsStore
    @State private var codec: VideoCodec
    @State private var showAllKeys: Bool

    init(store: any SettingsStore) {
        self.store = store
        let options = RecordingSettings.load(from: store)
        _codec = State(initialValue: options.codec)
        _showAllKeys = State(initialValue: options.showAllKeys)
    }

    var body: some View {
        Form {
            Picker(RecordingStrings.videoFormat, selection: $codec) {
                Text(RecordingStrings.h264).tag(VideoCodec.h264)
                Text(RecordingStrings.hevc).tag(VideoCodec.hevc)
            }
            .onChange(of: codec) { _, value in RecordingSettings.write(.codec(value), to: store) }
            Text(RecordingStrings.videoFormatNote).font(.footnote).foregroundStyle(.secondary)
            Toggle(RecordingStrings.showAllKeys, isOn: $showAllKeys)
                .onChange(of: showAllKeys) { _, value in RecordingSettings.write(.showAllKeys(value), to: store) }
            Text(RecordingStrings.showAllKeysNote).font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
