import BugeyeCore
import BugeyeFeatures
import Foundation
import SwiftUI
import os

/// Everything an epic's wiring may use, built before any wiring runs (contracts §4.5).
@MainActor
final class AppContext {
    let home: String
    let registry: FeatureRegistry
    let settingsStore: any SettingsStore
    let metadata: any FileMetadataStore
    let fileWriter: CaptureFileWriter
    let clipboard: any ClipboardWriter
    let notifier: any Notifier
    let screenPermission: any ScreenCapturePermission
    let general: GeneralSettings
    let captureEvents: CaptureEventBus
    let router: ActionRouter
    let settingsPanes: SettingsPanes
    let thumbnailDecorations: ThumbnailDecorations
    let screenActivity: ScreenActivity
    let areaSelector: AreaSelectorRelay
    let screenRecordingAlert: ScreenRecordingAlert
    let statusItem: StatusItemState
    let documentWindows: DocumentWindows
    let termination: TerminationGate
    let hotkeyStatus: HotkeyStatus
    #if DEBUG
        let debugCommands: DebugCommands
    #endif

    private var retained: [AnyObject] = []
    private var launchSteps: [@MainActor () -> Void] = []

    init(
        home: String, registry: FeatureRegistry, settingsStore: any SettingsStore, metadata: any FileMetadataStore,
        clipboard: any ClipboardWriter, notifier: any Notifier, screenPermission: any ScreenCapturePermission,
        general: GeneralSettings, applyActivationPolicy: @escaping @MainActor (ActivationPolicy) -> Void
    ) {
        self.home = home
        self.registry = registry
        self.settingsStore = settingsStore
        self.metadata = metadata
        fileWriter = CaptureFileWriter(metadata: metadata)
        self.clipboard = clipboard
        self.notifier = notifier
        self.screenPermission = screenPermission
        self.general = general
        let bus = CaptureEventBus()
        captureEvents = bus
        router = ActionRouter()
        settingsPanes = SettingsPanes()
        thumbnailDecorations = ThumbnailDecorations(bus: bus)
        screenActivity = ScreenActivity()
        areaSelector = AreaSelectorRelay()
        screenRecordingAlert = ScreenRecordingAlert()
        statusItem = StatusItemState()
        documentWindows = DocumentWindows(
            apply: applyActivationPolicy,
            onUnderflow: {
                Logger(subsystem: CaptureFolders.bundleID, category: "app")
                    .fault("A document window closed more often than one opened")
            })
        termination = TerminationGate()
        hotkeyStatus = HotkeyStatus()
        #if DEBUG
            debugCommands = DebugCommands()
        #endif
    }

    /// Keeps a controller alive for the app's life.
    func retain(_ object: AnyObject) {
        retained.append(object)
    }

    /// Runs after the menu bar exists, in registration order: global hotkeys, timers, crash recovery.
    /// `install` itself must not show a window, register a global hotkey or start a timer (tests build it).
    func onLaunch(_ step: @escaping @MainActor () -> Void) {
        launchSteps.append(step)
    }

    /// The shell calls this once, after the menu bar is built.
    func runLaunchSteps() {
        let steps = launchSteps
        launchSteps = []
        for step in steps { step() }
    }
}

/// Settings panes by section id (Capture, Quick Access, Recording, Capture's Shortcuts).
@MainActor
final class SettingsPanes {
    private var makers: [String: @MainActor () -> AnyView] = [:]
    /// Section ids registered more than once; the first stays. Launch fails unless this is empty.
    private(set) var duplicates: [String] = []

    func register(_ sectionID: String, _ make: @escaping @MainActor () -> AnyView) {
        guard makers[sectionID] == nil else { return duplicates.append(sectionID) }
        makers[sectionID] = make
    }

    func view(for sectionID: String) -> AnyView? {
        makers[sectionID]?()
    }

    func hasView(for sectionID: String) -> Bool {
        makers[sectionID] != nil
    }
}

/// Capture §5.5's alert, shown by Capture and Recording. Capture's wiring sets `presenter`; until then `show()` logs.
@MainActor
final class ScreenRecordingAlert {
    var presenter: (@MainActor () -> Void)?

    func show() {
        guard let presenter else {
            Logger(subsystem: CaptureFolders.bundleID, category: "app")
                .error("Screen Recording alert requested before Capture set a presenter")
            return
        }
        presenter()
    }
}

/// The status item's override, observed by `MenuBarController` (testable without an NSStatusItem).
@MainActor
final class StatusItemState {
    private(set) var override: StatusItemOverride?
    private(set) var owner: String?
    private var observers: [@MainActor () -> Void] = []

    /// nil restores the glyph and the module menu. Another owner's override is refused and logged.
    func setOverride(_ override: StatusItemOverride?, owner: String) {
        if let current = self.owner, current != owner {
            Logger(subsystem: CaptureFolders.bundleID, category: "app")
                .error(
                    "Status item override from \(owner, privacy: .public) refused: \(current, privacy: .public) holds it"
                )
            return
        }
        self.override = override
        self.owner = override == nil ? nil : owner
        for observer in observers { observer() }
    }

    func observe(_ handler: @escaping @MainActor () -> Void) {
        observers.append(handler)
    }
}

/// Which hotkeys registered (K34). Capture's registrar sets it; the status menu reads it.
@MainActor
final class HotkeyStatus {
    private var unregistered: Set<String> = []

    /// True unless `setRegistered(id, false)` was the last call for `id`.
    func isRegistered(_ id: String) -> Bool {
        !unregistered.contains(id)
    }

    func setRegistered(_ id: String, _ registered: Bool) {
        if registered { unregistered.remove(id) } else { unregistered.insert(id) }
    }
}
