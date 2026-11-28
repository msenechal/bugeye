import AppKit
import BugeyeCore
import BugeyeFeatures
import BugeyeTestSupport
import Foundation
import RecordingCore
import Testing

@testable import BugeyeApp

@MainActor @Suite struct RecordingWiringTests {
    private func dependencies(_ surfaces: FakeSurfaces) -> RecordingController.Dependencies {
        RecordingController.Dependencies(
            makeRecorder: { _ in FakeRecorder() }, surfaces: surfaces, overlays: nil,
            permissions: FakeMediaPermissions(), reader: nil, devices: { ([], []) },
            freeBytes: { _ in 50_000_000_000 }, hostNow: { 1000 }, convert: { _, mp4, _, _ in .converted(mp4) },
            firstFrame: { _ in nil }, display: { _ in (CGRect(x: 0, y: 0, width: 1512, height: 982), 2) },
            primaryHeight: { 982 })
    }

    @Test func theModuleIsRecording() {
        #expect(RecordingWiring.modules.map(\.id) == ["recording"])
    }

    @Test func installRegistersTheMenuHotkeyOverrideEntriesPaneAndDebugCommand() throws {
        let home = try TempDirectory("home")
        defer { home.remove() }
        let context = AppContext.testing(home: home.url.path, modules: [GeneralModule(), RecordingModule()])
        RecordingWiring.install(context, dependencies: dependencies(FakeSurfaces()))
        #expect(context.router.duplicates.isEmpty)
        #expect(context.router.isMenuItemEnabled("recording.record"))
        for id in ["recording.pause", "recording.resume", "recording.stop", "recording.restart", "recording.discard"] {
            #expect(context.router.isMenuItemEnabled(id))
        }
        #expect(context.settingsPanes.hasView(for: "recording"))
        #expect(context.settingsPanes.duplicates.isEmpty)
        #if DEBUG
            #expect(context.debugCommands.handler(for: "recording.state")?("") == "idle")
        #endif
        // The hotkey starts a selection.
        let selector = FakeAreaSelector(results: [])
        context.areaSelector.target = selector
        #expect(context.router.performHotkey("recording.toggle"))
        #expect(context.screenActivity.active == [.recordingSetup])
    }

    @Test func aCrashedTakeIsRecoveredAtLaunchWithItsNotice() async throws {
        let home = try TempDirectory("home")
        defer { home.remove() }
        let notifier = FakeNotifier()
        let settings = InMemorySettingsStore([OutputSettings.Key.copyToClipboard: .bool(false)])
        let context = AppContext.testing(
            home: home.url.path, settings: settings, notifier: notifier, modules: [GeneralModule(), RecordingModule()])
        let events = CaptureEventRecorder(context.captureEvents)
        let folder = CaptureFolders.recordingsInProgress(home: home.url.path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let movie = folder.appendingPathComponent(TakeRecovery.movieName(take: UUID()))
        try Data(repeating: 7, count: 100_000).write(to: movie)
        let old = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes([.modificationDate: old, .creationDate: old], ofItemAtPath: movie.path)
        let controller = RecordingController(context: context, dependencies: dependencies(FakeSurfaces()))
        await controller.recoverTakes()
        #expect(events.events.map(\.change) == [.created])
        #expect(events.events.first?.item.fileURL.pathExtension == "mov")
        #expect(
            notifier.posts.contains(
                FakeNotifier.Post(
                    title: "Recovered a recording",
                    body: "Bugeye quit while recording. What was recorded has been kept.")))
        #expect(!FileManager.default.fileExists(atPath: movie.path))
    }
}
