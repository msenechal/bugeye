import AppKit
import BugeyeCore
import BugeyeFeatures
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: CaptureFolders.bundleID, category: "app")
    private var services: AppServices?
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private var mainMenu: NSMenu?
    #if DEBUG
        private var debugChannel: DebugChannel?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        let services: AppServices
        do {
            services = try AppServices.live(applyActivationPolicy: { [weak self] in self?.applyActivationPolicy($0) })
        } catch {
            // Two modules claim the same slot, or two wirings the same id: a programming error that tests catch first.
            log.fault("Bugeye can't start: \(String(describing: error), privacy: .public)")
            NSApp.terminate(nil)
            return
        }
        self.services = services
        let context = services.context
        // Never shown while Bugeye is a menu-bar agent, but it makes ⌘V, ⌘C, ⌘A, ⌘Z and ⌘W work in Settings, and it
        // is the menu bar while a document window is open (plan P10).
        let mainMenu = MainMenuInstaller.menu(for: services.registry)
        self.mainMenu = mainMenu
        NSApp.mainMenu = mainMenu
        services.general.ensureFolderExists()
        // Reads the Keychain off the main actor; the AI pane shows "No key saved." until it answers.
        Task { await services.aiKey.load() }

        let settingsWindow = SettingsWindowController(
            panes: SettingsLayout.panes(for: services.registry), general: services.general, ai: services.aiKey,
            settingsPanes: context.settingsPanes)
        self.settingsWindow = settingsWindow

        let menuBar = MenuBarController(
            registry: services.registry, settings: services.settingsStore, router: context.router,
            hotkeyStatus: context.hotkeyStatus, statusItemState: context.statusItem, display: SystemStatusItemDisplay())
        let log = self.log
        menuBar.onChoose = { id in
            switch id {
            case StatusMenu.aboutID:
                NSApp.activate()
                NSApp.orderFrontStandardAboutPanel(nil)
            case StatusMenu.settingsID:
                settingsWindow.show()
            case StatusMenu.quitID:
                NSApp.terminate(nil)
            default:
                if !context.router.performMenuItem(id) {
                    log.error("no action for \(id, privacy: .public)")
                }
            }
        }
        self.menuBar = menuBar

        Task { await services.requestNotificationAuthorization() }
        context.runLaunchSteps()

        #if DEBUG
            startDebugChannel(services)
        #endif
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let services else { return .terminateNow }
        return Self.terminationReply(gate: services.context.termination) { allowed in
            NSApp.reply(toApplicationShouldTerminate: allowed)
        }
    }

    /// Answers `.terminateLater` and replies with the gate's answer once every participant has run (K11).
    static func terminationReply(gate: TerminationGate, reply: @escaping @MainActor (Bool) -> Void)
        -> NSApplication.TerminateReply
    {
        Task { @MainActor in reply(await gate.shouldTerminate()) }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        #if DEBUG
            debugChannel?.stop()
        #endif
    }

    private func applyActivationPolicy(_ policy: ActivationPolicy) {
        guard let mainMenu else { return }
        let apply = MainMenuInstaller.applier(
            menu: mainMenu, setPolicy: { NSApp.setActivationPolicy($0) }, setMainMenu: { NSApp.mainMenu = $0 },
            activate: { NSApp.activate() })
        apply(policy)
    }

    #if DEBUG
        private func startDebugChannel(_ services: AppServices) {
            let context = services.context
            let commands = context.debugCommands
            let handler = DebugCommandHandler(
                moduleIDs: services.registry.moduleIDs, router: context.router, settings: services.settingsStore,
                bus: context.captureEvents, registered: { commands.handler(for: $0) })
            let channel = DebugChannel(path: DebugChannel.defaultSocketPath(), handler: handler)
            do {
                try channel.start()
                debugChannel = channel
            } catch {
                log.error("Debug channel didn't start: \(String(describing: error), privacy: .public)")
            }
        }
    #endif
}
