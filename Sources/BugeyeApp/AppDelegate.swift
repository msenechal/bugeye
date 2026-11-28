import AppKit
import BugeyeFeatures
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "dev.msenechal.bugeye", category: "app")
    private var services: AppServices?
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    #if DEBUG
        private var debugChannel: DebugChannel?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        let services: AppServices
        do {
            services = try AppServices.live()
        } catch {
            // Two modules claim the same slot: a programming error that tests catch first.
            log.fault("Feature modules conflict: \(String(describing: error.conflicts), privacy: .public)")
            NSApp.terminate(nil)
            return
        }
        self.services = services
        // Never shown (menu-bar agent), but it makes ⌘V, ⌘C, ⌘A, ⌘Z and ⌘W work in the Settings window.
        NSApp.mainMenu = MainMenu.make()
        services.general.ensureFolderExists()
        // Reads the Keychain off the main actor; the AI pane shows "No key saved." until it answers.
        Task { await services.aiKey.load() }

        let settingsWindow = SettingsWindowController(
            panes: SettingsLayout.panes(for: services.registry), general: services.general, ai: services.aiKey)
        self.settingsWindow = settingsWindow

        let menuBar = MenuBarController(entries: StatusMenu.entries(for: services.registry))
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
                break  // Module items arrive with their wave.
            }
        }
        self.menuBar = menuBar

        #if DEBUG
            startDebugChannel(moduleIDs: services.registry.moduleIDs)
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        #if DEBUG
            debugChannel?.stop()
        #endif
    }

    #if DEBUG
        private func startDebugChannel(moduleIDs: [String]) {
            let channel = DebugChannel(
                path: DebugChannel.defaultSocketPath(), handler: DebugCommandHandler(moduleIDs: moduleIDs))
            do {
                try channel.start()
                debugChannel = channel
            } catch {
                log.error("Debug channel didn't start: \(String(describing: error), privacy: .public)")
            }
        }
    #endif
}
