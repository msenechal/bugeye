import AppKit
import BugeyeCore
import BugeyeFeatures
import BugeyeTestSupport
import CaptureCore
import Foundation
import Testing

@testable import BugeyeApp

@MainActor @Suite struct CaptureWiringTests {
    @MainActor struct Setup {
        let dir: TempDirectory
        let context: AppContext
        let registrar = FakeHotkeyRegistrar()
        let notifier = FakeNotifier()
        let source = FakeScreenSource(displays: [
            DisplayInfo(id: DisplayID(1), frame: Rect2D(x: 0, y: 0, width: 400, height: 300), scale: 2)
        ])
        let installed: CaptureWiring.Installed

        init(taken: Set<GlobalKey> = [], system: [Int: SymbolicHotkey]? = nil) throws {
            dir = try TempDirectory()
            context = AppContext.testing(
                home: dir.url.path, notifier: notifier, modules: [GeneralModule()] + CaptureWiring.modules)
            registrar.taken = taken
            // Every macOS screenshot shortcut off unless the test says otherwise.
            let off = Dictionary(
                uniqueKeysWithValues: [28, 29, 30, 31, 184, 181].map {
                    ($0, SymbolicHotkey(enabled: false, parameters: []))
                })
            installed = CaptureWiring.install(
                context,
                adapters: CaptureWiring.Adapters(
                    screenSource: source, windowList: FakeWindowListReader(), pipeline: FakeImagePipeline(),
                    registrar: registrar, systemShortcuts: FakeSystemShortcutReader(hotkeys: system ?? off)))
        }
    }

    @Test func theModuleIsCaptures() {
        #expect(CaptureWiring.modules.map(\.id) == ["capture"])
    }

    @Test func menuItemsAndHotkeysAreRoutedAndTheSelectorAndAlertAreSet() throws {
        let s = try Setup()
        for id in ["capture.area", "capture.window", "capture.fullscreen"] {
            #expect(s.context.router.isMenuItemEnabled(id))
        }
        #expect(s.context.router.duplicates.isEmpty)
        #expect(s.context.areaSelector.target === s.installed.controller)
        #expect(s.context.screenRecordingAlert.presenter != nil)
        #expect(s.context.settingsPanes.hasView(for: "capture"))
        #expect(s.context.settingsPanes.hasView(for: "shortcuts"))
        #expect(s.context.settingsPanes.duplicates.isEmpty)
        // install itself registers no global hotkey (contracts §4.5).
        #expect(s.registrar.registered.isEmpty)
    }

    @Test func launchRegistersEveryHotkeyAndAPressStartsACapture() async throws {
        let s = try Setup()
        s.context.runLaunchSteps()
        defer { s.installed.launch.stop() }
        #expect(Set(s.registrar.registered.keys) == ["capture.fullscreen", "capture.allDisplays", "capture.area"])
        #expect(s.context.hotkeyStatus.isRegistered("capture.area"))
        #expect(s.registrar.press("capture.area"))
        await s.installed.controller.waitUntil(.selecting)
        #expect(s.context.screenActivity.active == [.screenshotSelection])
        s.installed.controller.send(.globalEscape)
        #expect(s.installed.controller.phase == .idle)
        #expect(s.installed.shell.overlays.isEmpty)
    }

    @Test func aTakenKeyIsMarkedUnregisteredAndAnnouncedAtLaunch() throws {
        let s = try Setup(taken: [GlobalKey("4", command: true, shift: true)])
        s.context.runLaunchSteps()
        defer { s.installed.launch.stop() }
        #expect(!s.context.hotkeyStatus.isRegistered("capture.area"))
        #expect(
            s.notifier.posts == [
                FakeNotifier.Post(
                    title: "Some Bugeye shortcuts are taken",
                    body: "⇧⌘4 is taken by another app. Choose another in Bugeye Settings \u{2192} Shortcuts.")
            ])
    }

    @Test func macOSConflictsAreAnnouncedAtLaunch() throws {
        let s = try Setup(system: [:])
        s.context.runLaunchSteps()
        defer { s.installed.launch.stop() }
        #expect(s.notifier.posts.map(\.title) == ["macOS screenshot shortcuts are still on"])
        #expect(
            s.notifier.posts.first?.body
                == "Disable ⇧⌘3 and ⇧⌘4 in System Settings \u{2192} Keyboard \u{2192} Keyboard Shortcuts \u{2192} Screenshots, so Bugeye receives them."
        )
    }

    @Test func aMenuItemCapturesAndAnnouncesTheFullScreen() async throws {
        let s = try Setup()
        try FileManager.default.createDirectory(at: s.context.general.folderURL, withIntermediateDirectories: true)
        let recorder = CaptureEventRecorder(s.context.captureEvents)
        #expect(s.context.router.performMenuItem("capture.fullscreen"))
        await s.installed.controller.settle()
        #expect(recorder.changes == [.created])
        #expect(recorder.events.first?.origin == "capture")
    }

    @Test func theLaunchPurgeRemovesOldTempFiles() async throws {
        let s = try Setup()
        let temp = CaptureFolders.temp(home: s.dir.url.path)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let old = temp.appendingPathComponent("old.png")
        FileManager.default.createFile(atPath: old.path, contents: Data())
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -2 * 86400)], ofItemAtPath: old.path)
        s.context.runLaunchSteps()
        defer { s.installed.launch.stop() }
        #expect(await s.installed.launch.purge?.value == 1)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(s.installed.launch.timer?.isValid == true)
        #expect(s.installed.launch.timer?.timeInterval == 3600)
    }

    @Test func aDisplayChangeCancelsTheSelection() async throws {
        let s = try Setup()
        s.context.runLaunchSteps()
        defer { s.installed.launch.stop() }
        #expect(s.context.router.performMenuItem("capture.area"))
        await s.installed.controller.waitUntil(.selecting)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // The observer runs on the main queue, now or on its next turn.
        await s.installed.controller.waitUntil(.idle)
        #expect(s.installed.controller.phase == .idle)
        #expect(s.installed.shell.overlays.isEmpty)
    }

    #if DEBUG
        @Test func theDebugClickCommandNeedsALiveSelection() throws {
            let s = try Setup()
            #expect(s.context.debugCommands.handler(for: "capture.click")?("1 10 10") == "error: no selection is up")
            #expect(
                s.context.debugCommands.handler(for: "capture.click")?("x")
                    == "error: usage: capture.click <display id> <x> <y>")
        }

        @Test func theDebugStateCommandAnswers() throws {
            let s = try Setup()
            #expect(s.context.debugCommands.handler(for: "capture.state")?("") == "idle")
        }
    #endif
}
