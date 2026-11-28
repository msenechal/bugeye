import AVFoundation
import AppKit
import BugeyeCore
import BugeyeFeatures
import CoreMedia
import MacAdapters
import RecordingCore
import SwiftUI

/// Recording's wiring (contracts K7): the module, its router entries, the Recording pane, the quit participant,
/// the timeline store, crash recovery at launch and the `recording.state` debug command.
@MainActor
enum RecordingWiring {
    static let modules: [any FeatureModule] = [RecordingModule()]

    static func install(_ context: AppContext) {
        install(context, dependencies: liveDependencies(context))
    }

    /// Tests pass fakes.
    static func install(_ context: AppContext, dependencies: RecordingController.Dependencies) {
        let controller = RecordingController(context: context, dependencies: dependencies)
        context.retain(controller)
        if let windows = dependencies.surfaces as? RecordingWindows {
            windows.handlers = RecordingWindows.Handlers(
                bar: { [weak controller] in controller?.bar($0) },
                bubbleDoubleClicked: { [weak controller] in controller?.bubbleDoubleClicked() },
                cameraFailed: { [weak controller] in controller?.cameraFailed() })
        }
        let router = context.router
        router.onMenuItem(RecordingModule.recordMenuItem) { [weak controller] in controller?.toggle() }
        router.onHotkey(RecordingModule.toggleHotkey.id) { [weak controller] in controller?.toggle() }
        for id in [
            RecordingMenu.pause, RecordingMenu.resume, RecordingMenu.stop, RecordingMenu.restart, RecordingMenu.discard,
        ] {
            router.onMenuItem(id) { [weak controller] in controller?.menu(id) }
        }
        context.settingsPanes.register("recording") { [store = context.settingsStore] in
            AnyView(RecordingPane(store: store))
        }
        context.termination.addFinish { [weak controller] in await controller?.finishForQuit() }
        let timelines = TimelineStore(home: context.home)
        context.retain(TimelineSubscription(timelines.observe(context.captureEvents)))
        context.onLaunch { [weak controller] in
            Task { await controller?.recoverTakes() }
        }
        #if DEBUG
            DebugRecording.register(context, controller: controller)
        #endif
    }

    static func liveDependencies(_ context: AppContext) -> RecordingController.Dependencies {
        RecordingController.Dependencies(
            makeRecorder: { StreamRecorder(callbacks: $0) },
            surfaces: RecordingWindows(),
            overlays: RecordingOverlay(),
            permissions: SystemMediaPermissions(),
            reader: AXPointReader(),
            devices: { (CaptureDevices.microphones(), CaptureDevices.cameras()) },
            freeBytes: { DiskSpace.freeBytes(at: $0) },
            hostNow: { CMClockGetTime(CMClockGetHostTimeClock()).seconds },
            convert: { mov, mp4, deadline, progress in
                await MovieConverter.convert(mov, to: mp4, deadline: deadline, progress: progress)
            },
            firstFrame: { await FirstFrame.preview(of: $0) },
            display: { id in
                let bounds = CGDisplayBounds(id.rawValue)
                guard bounds.width > 0 else { return nil }
                let pixels = CGDisplayCopyDisplayMode(id.rawValue).map { Double($0.pixelWidth) } ?? bounds.width
                return (bounds, pixels / bounds.width)
            },
            primaryHeight: { NSScreen.screens.first?.frame.height ?? 0 })
    }
}

/// Keeps the timeline store's bus subscription alive for the app's life.
@MainActor
final class TimelineSubscription {
    let subscription: CaptureSubscription
    init(_ subscription: CaptureSubscription) { self.subscription = subscription }
}
