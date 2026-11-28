import AppKit
import BugeyeCore
import BugeyeFeatures
import BugeyeTestSupport
import CaptureCore
import Foundation
import MacAdapters
import Testing

@testable import BugeyeApp

private let display = DisplayInfo(id: DisplayID(1), frame: Rect2D(x: 0, y: 0, width: 400, height: 300), scale: 2)

private func frozen() throws -> FrozenDisplay {
    let buffer = try PixelBuffer(width: 800, height: 600, fill: RGBA8(red: 10, green: 20, blue: 30))
    return FrozenDisplay(display: display, image: CapturedImage(pixelBuffer: buffer), time: Date())
}

@MainActor
private func makeView(render: @escaping () -> OverlayRender?, send: @escaping (FlowEvent) -> Void = { _ in })
    -> SelectionOverlayView
{
    let view = SelectionOverlayView(
        session: SessionID(3), display: display, image: nil, pixelWidth: 800, visibleTopInset: 25)
    view.render = render
    view.send = send
    return view
}

@MainActor @Suite struct SelectionOverlayWindowTests {
    @Test func theWindowHasTheSpecsProperties() {
        let window = SelectionOverlayWindow(session: SessionID(1), display: display)
        defer { window.close() }
        #expect(window.styleMask == .borderless)
        #expect(window.level == .screenSaver)
        #expect(!window.isReleasedWhenClosed)
        #expect(window.collectionBehavior == [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle])
        #expect(!window.isOpaque && !window.hasShadow)
        #expect(window.acceptsMouseMovedEvents)
        #expect(window.canBecomeKey && window.canBecomeMain)
        #expect(window.frame == NSRect(x: 0, y: 0, width: 400, height: 300))
    }
}

@MainActor @Suite struct AppCaptureShellTests {
    @Test func finishingClosesTheOverlaysRatherThanHidingThem() throws {
        let shell = AppCaptureShell()
        shell.showOverlays(SessionID(1), frames: [try frozen()], mode: .area)
        let window = try #require(shell.overlays[SessionID(1)]?.first)
        #expect(window.isVisible)
        #expect(shell.overlayWindowNumbers(SessionID(1)) == [window.windowNumber])
        shell.closeOverlays(SessionID(1))
        #expect(!window.isVisible)
        #expect(window.contentView == nil)
        #expect(shell.overlays.isEmpty)
    }

    @Test func theSweepClosesOtherSessionsWindowsAndLogsVisibleOnes() throws {
        let shell = AppCaptureShell()
        var logged: [String] = []
        shell.onLog = { logged.append($0.1) }
        shell.showOverlays(SessionID(1), frames: [try frozen()], mode: .area)
        shell.showOverlays(SessionID(2), frames: [try frozen()], mode: .area)
        let old = try #require(shell.overlays[SessionID(1)]?.first)
        shell.sweepLeftovers(keeping: SessionID(2))
        #expect(!old.isVisible)
        #expect(shell.overlays.keys.sorted { $0.rawValue < $1.rawValue } == [SessionID(2)])
        #expect(logged == ["closing a leftover overlay \(old.windowNumber)"])
        shell.sweepLeftovers(keeping: nil)
        #expect(shell.overlays.isEmpty)
    }

    @Test func viewEventsReachTheController() async throws {
        let dir = try TempDirectory()
        let shell = AppCaptureShell()
        let source = FakeScreenSource(displays: [display])
        let controller = CaptureController(
            environment: CaptureEnvironment(
                screenSource: source, windowList: FakeWindowListReader(), pipeline: FakeImagePipeline(),
                permission: FakeScreenCapturePermission(granted: true), settings: InMemorySettingsStore(),
                writer: CaptureFileWriter(metadata: FakeFileMetadataStore()), clipboard: FakeClipboard(),
                notifier: FakeNotifier(), metadata: FakeFileMetadataStore(), home: dir.url.path, ownPID: 0,
                saveFolder: { (dir.url, "~/") }),
            bus: CaptureEventBus(), activity: ScreenActivity(), registrar: FakeHotkeyRegistrar(), shell: shell)
        shell.controller = controller
        controller.request(.area)
        await controller.waitUntil(.selecting)
        let window = try #require(shell.overlays.values.first?.first)
        let view = try #require(window.contentView as? SelectionOverlayView)
        view.keyDown(with: try #require(keyEvent(code: 53)))
        #expect(controller.phase == .idle)
        #expect(shell.overlays.isEmpty)
        #expect(!window.isVisible)
    }
}

@MainActor
func keyEvent(code: UInt16) -> NSEvent? {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
        characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)
}

@MainActor
func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint, flags: NSEvent.ModifierFlags = []) -> NSEvent? {
    NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
        clickCount: 1, pressure: 1)
}

@MainActor @Suite struct SelectionOverlayViewTests {
    let live = OverlayRender(mode: .area, selection: nil, hovered: nil, hint: nil)

    @Test func mouseEventsBecomeFlowEventsWithViewPointsAndModifiers() throws {
        var events: [FlowEvent] = []
        let view = makeView(render: { live }, send: { events.append($0) })
        view.mouseDown(with: try #require(mouseEvent(.leftMouseDown, at: NSPoint(x: 10, y: 20), flags: [.shift])))
        view.mouseDragged(
            with: try #require(mouseEvent(.leftMouseDragged, at: NSPoint(x: 30, y: 40), flags: [.option])))
        view.mouseUp(with: try #require(mouseEvent(.leftMouseUp, at: NSPoint(x: 30, y: 40))))
        view.rightMouseDown(with: try #require(mouseEvent(.rightMouseDown, at: NSPoint(x: 1, y: 1))))
        #expect(
            events == [
                .mouseDown(SessionID(3), DisplayID(1), ViewPoint(x: 10, y: 20), Modifiers(shift: true)),
                .mouseDragged(SessionID(3), DisplayID(1), ViewPoint(x: 30, y: 40), Modifiers(option: true)),
                .mouseUp(SessionID(3), DisplayID(1), ViewPoint(x: 30, y: 40)),
                .rightMouseDown(SessionID(3)),
            ])
    }

    @Test func keysBecomeEscapeSpaceAndReturn() throws {
        var events: [FlowEvent] = []
        let view = makeView(render: { live }, send: { events.append($0) })
        for code: UInt16 in [53, 49, 36, 76] { view.keyDown(with: try #require(keyEvent(code: code))) }
        #expect(
            events == [
                .key(SessionID(3), .escape), .key(SessionID(3), .space), .key(SessionID(3), .return),
                .key(SessionID(3), .return),
            ])
    }

    @Test func aFinishedSelectionsViewIgnoresALateMouseEntered() throws {
        var events: [FlowEvent] = []
        let view = makeView(render: { nil }, send: { events.append($0) })
        let entered = try #require(
            NSEvent.enterExitEvent(
                with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, trackingNumber: 0, userData: nil))
        view.mouseEntered(with: entered)
        #expect(events.isEmpty)
    }

    @Test func aDragInvalidatesOnlyTheSelectionAndItsReadout() {
        var selection: DisplayRect? = DisplayRect(x: 10, y: 10, width: 50, height: 40)
        let view = makeView(render: { OverlayRender(mode: .area, selection: selection, hovered: nil, hint: nil) })
        view.invalidate(DisplayRect(x: 9, y: 9, width: 52, height: 42))
        let expected = view.viewRect(DisplayRect(x: 9, y: 9, width: 52, height: 42))
            .union(view.readoutFrame(for: selection!))
        #expect(view.damage == expected)
        #expect(view.damage.width < view.bounds.width && view.damage.height < view.bounds.height)
        selection = nil
        view.invalidate(nil)
        #expect(view.damage == view.bounds.union(expected))
    }

    @Test func theHintSitsTwelvePointsBelowTheVisibleFrameCentred() {
        let view = makeView(render: { nil })
        let frame = view.hintFrame("Drag an area")
        #expect(abs(frame.midX - 200) < 0.5)
        #expect(abs(frame.maxY - (300 - 25 - 12)) < 0.5)
    }
}

@MainActor @Suite struct ScreenRecordingAlertTests {
    @Test func openSystemSettingsRequestsAccessThenOpensThePane() {
        let permission = FakeScreenCapturePermission(granted: false)
        var opened: [URL] = []
        ScreenRecordingAlertPresenter.handle(.openSystemSettings, permission: permission, open: { opened.append($0) })
        #expect(permission.requestCount == 1)
        #expect(
            opened == [URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!])
    }

    @Test func relaunchAndCancel() {
        let permission = FakeScreenCapturePermission(granted: false)
        var relaunched = 0
        ScreenRecordingAlertPresenter.handle(
            .relaunch, permission: permission, open: { _ in }, relaunch: { relaunched += 1 })
        ScreenRecordingAlertPresenter.handle(
            .cancel, permission: permission, open: { _ in }, relaunch: { relaunched += 10 })
        #expect(relaunched == 1)
        #expect(permission.requestCount == 0)
    }

    @Test func theRelaunchScriptPollsThePidThenOpensTheBundleByPath() throws {
        let args = ScreenRecordingAlertPresenter.relaunchArguments(
            pid: 4242, bundlePath: "/Users/me/Applications/Bugeye.app")
        #expect(args.count == 5 && args[0] == "-c" && args[2] == "sh")
        #expect(args[3] == "4242" && args[4] == "/Users/me/Applications/Bugeye.app")
        #expect(args[1].contains("kill -0") && args[1].contains("sleep 0.1") && args[1].contains("-lt 50"))
        #expect(!args[1].contains("4242"))
        // The script really exits at once for a pid that's gone, and runs `open` with the path.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        let dir = try TempDirectory()
        let marker = dir.url.appendingPathComponent("opened").path
        let script = args[1].replacingOccurrences(of: "open \"$2\"", with: "touch \"$2\"")
        process.arguments = ["-c", script, "sh", "999999", marker]
        try process.run()
        process.waitUntilExit()
        #expect(FileManager.default.fileExists(atPath: marker))
    }
}

@MainActor @Suite struct CapturePaneTests {
    @Test func togglesWriteTheirKeys() {
        let store = InMemorySettingsStore()
        let model = CapturePaneModel(store: store)
        #expect(model.copyToClipboard && model.saveToFolder && !model.downscaleToPoints)
        model.copyToClipboard = false
        model.downscaleToPoints = true
        #expect(store.value(forKey: "capture.copyToClipboard") == .bool(false))
        #expect(store.value(forKey: "capture.downscaleToPoints") == .bool(true))
        #expect(
            CaptureSettings.load(from: store)
                == CaptureSettings(copyToClipboard: false, saveToFolder: true, downscaleToPoints: true))
    }

    @Test func thePaneBuilds() {
        _ = CapturePane(model: CapturePaneModel(store: InMemorySettingsStore())).body
    }
}

@MainActor @Suite struct ShortcutsPaneTests {
    @Test func typedKeysMapToInputs() {
        #expect(ShortcutKeyInput.from(keyCode: 53, characters: "\u{1B}", flags: []) == .escape)
        #expect(ShortcutKeyInput.from(keyCode: 51, characters: "\u{7F}", flags: []) == .delete)
        #expect(ShortcutKeyInput.from(keyCode: 117, characters: nil, flags: []) == .delete)
        #expect(
            ShortcutKeyInput.from(keyCode: 20, characters: "3", flags: [.shift, .command])
                == .combo(KeyCombo("3", [.shift, .command])))
        #expect(
            ShortcutKeyInput.from(keyCode: 0, characters: "A", flags: [.control]) == .combo(KeyCombo("a", [.control])))
        #expect(ShortcutKeyInput.from(keyCode: 122, characters: nil, flags: []) == .ignored)
    }

    @Test func thePaneModelFollowsTheModel() {
        let store = InMemorySettingsStore()
        let model = ShortcutsModel(
            specs: CaptureModule().hotkeys(), store: store, registrar: FakeHotkeyRegistrar(), systemCombos: { [] },
            onPress: { _ in }, onRegistration: { _, _ in }, log: { _ in })
        let pane = ShortcutsPaneModel(model: model)
        model.registerAll()
        pane.handle(.delete, for: "capture.area")
        #expect(pane.fieldText(pane.rows[2]) == "None")
        pane.handle(.combo(KeyCombo("x", [.control])), for: "capture.area")
        #expect(pane.fieldText(pane.rows[2]) == "⌃X")
        _ = ShortcutsPane(model: pane).body
    }
}
