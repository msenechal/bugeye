import AppKit
import BugeyeCore
import BugeyeFeatures
import CaptureCore
import MacAdapters
import SwiftUI

/// The Capture epic's wiring (K7, C12): its module, its router registrations, the `AreaSelector` Recording calls,
/// the Screen Recording alert, the Capture and Shortcuts panes, and the launch steps (global hotkeys, launch notices,
/// the temp purge at launch and hourly).
@MainActor
enum CaptureWiring {
    static let modules: [any FeatureModule] = [CaptureModule()]

    /// The macOS adapters Capture runs on; tests pass fakes.
    struct Adapters {
        var screenSource: any ScreenSource
        var windowList: any WindowListReader
        var pipeline: any ImagePipeline
        var registrar: any HotkeyRegistrar
        var systemShortcuts: any SystemShortcutReader

        static func live() -> Adapters {
            Adapters(
                screenSource: ScreenCaptureKitSource(), windowList: CGWindowListReader(), pipeline: ImageIOPipeline(),
                registrar: CarbonHotkeyRegistrar(), systemShortcuts: SystemShortcutDefaultsReader())
        }
    }

    /// What `install` built, for tests and the debug channel.
    struct Installed {
        let controller: CaptureController
        let shell: AppCaptureShell
        let shortcuts: ShortcutsModel
    }

    static func install(_ context: AppContext) {
        install(context, adapters: .live())
    }

    @discardableResult
    static func install(_ context: AppContext, adapters: Adapters) -> Installed {
        let shell = AppCaptureShell()
        let general = context.general
        let environment = CaptureEnvironment(
            screenSource: adapters.screenSource, windowList: adapters.windowList, pipeline: adapters.pipeline,
            permission: context.screenPermission, settings: context.settingsStore, writer: context.fileWriter,
            clipboard: context.clipboard, notifier: context.notifier, metadata: context.metadata, home: context.home,
            ownPID: ProcessInfo.processInfo.processIdentifier,
            saveFolder: { (general.folderURL, general.displayedFolder) })
        let controller = CaptureController(
            environment: environment, bus: context.captureEvents, activity: context.screenActivity,
            registrar: adapters.registrar, shell: shell)
        shell.controller = controller
        shell.presentAlert = { [weak context] in context?.screenRecordingAlert.show() }

        let permission = context.screenPermission
        context.screenRecordingAlert.presenter = { ScreenRecordingAlertPresenter.present(permission: permission) }
        context.areaSelector.target = controller

        let router = context.router
        router.onMenuItem(CaptureModule.ID.area) { controller.request(.area) }
        router.onMenuItem(CaptureModule.ID.window) { controller.request(.window) }
        router.onMenuItem(CaptureModule.ID.fullscreen) { controller.request(.fullscreen) }
        router.onHotkey(CaptureModule.ID.fullscreen) { controller.request(.fullscreen) }
        router.onHotkey(CaptureModule.ID.allDisplays) { controller.request(.allDisplays) }
        router.onHotkey(CaptureModule.ID.area) { controller.request(.area) }

        let reader = adapters.systemShortcuts
        let status = context.hotkeyStatus
        let shortcuts = ShortcutsModel(
            specs: context.registry.hotkeys, store: context.settingsStore, registrar: adapters.registrar,
            systemCombos: {
                ShortcutConflicts.enabledSystemCombos(hotkeys: reader.symbolicHotkeys(), model: reader.hardwareModel())
            },
            onPress: { router.performHotkey($0) }, onRegistration: { status.setRegistered($0, $1) },
            log: { [weak shell] in shell?.log(.hotkeys, $0) })

        let store = context.settingsStore
        let paneModel = CapturePaneModel(store: store)
        let shortcutsPane = ShortcutsPaneModel(model: shortcuts)
        context.settingsPanes.register(CaptureModule.ID.module) { AnyView(CapturePane(model: paneModel)) }
        context.settingsPanes.register(SettingsLayout.shortcutsPane.id) { AnyView(ShortcutsPane(model: shortcutsPane)) }

        let notifier = context.notifier
        context.onLaunch {
            shortcuts.registerAll()
            // The notifier holds posts until authorization is answered (contracts §4.4).
            for notice in shortcuts.launchNotices() { notifier.post(title: notice.title, body: notice.body) }
            Task { await controller.purgeTemp(skippingKnown: false) }
            let timer = Timer.scheduledTimer(withTimeInterval: TempJanitor.interval, repeats: true) { _ in
                MainActor.assumeIsolated {
                    _ = Task { await controller.purgeTemp(skippingKnown: true) }
                }
            }
            context.retain(timer)
            let observer = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { controller.send(.displaysChanged) }
            }
            context.retain(observer as AnyObject)
        }

        #if DEBUG
            DebugCaptureCommands.register(context.debugCommands, controller: controller)
        #endif
        context.retain(controller)
        context.retain(shell)
        context.retain(shortcuts)
        context.retain(paneModel)
        context.retain(shortcutsPane)
        return Installed(controller: controller, shell: shell, shortcuts: shortcuts)
    }
}
