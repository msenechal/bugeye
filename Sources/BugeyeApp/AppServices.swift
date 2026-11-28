import AICore
import BugeyeCore
import BugeyeFeatures
import Foundation
import MacAdapters
import TextCore

/// The composition root: every adapter and model the app runs on, built once at launch. Features add their
/// modules and installs in their own `Wiring/<Epic>Wiring.swift` and nowhere else (`design/14` R1, K7).
@MainActor
struct AppServices {
    static let modules: [any FeatureModule] =
        [GeneralModule()] + CaptureWiring.modules + QuickAccessWiring.modules + EditorWiring.modules
        + RecordingWiring.modules + TextWiring.modules

    /// Why the app can't start: a programming error that tests catch first.
    enum LaunchError: Error, Equatable {
        case conflicts([FeatureConflict])
        case duplicates(router: [String], settingsPanes: [String], debugCommands: [String])
    }

    let registry: FeatureRegistry
    let settingsStore: any SettingsStore
    let secrets: any SecretStore
    let metadata: any FileMetadataStore
    let llm: any LLMClient
    let general: GeneralSettings
    let aiKey: AIKeySettings
    let context: AppContext
    let text: TextServices
    /// Asks for notification permission; the shell calls it once at launch (contracts §4.4).
    let requestNotificationAuthorization: @Sendable () async -> Void

    static func live(applyActivationPolicy: @escaping @MainActor (ActivationPolicy) -> Void) throws(LaunchError)
        -> AppServices
    {
        let notifier = UserNotificationNotifier()
        return try AppServices(
            settingsStore: UserDefaultsSettingsStore(), secrets: KeychainSecretStore(), metadata: XattrMetadataStore(),
            home: FileManager.default.homeDirectoryForCurrentUser.path, clipboard: PasteboardClipboardWriter(),
            notifier: notifier, screenPermission: SystemScreenCapturePermission(),
            applyActivationPolicy: applyActivationPolicy,
            requestNotificationAuthorization: { await notifier.requestAuthorization() })
    }

    /// Builds the registry and the `AppContext`, then runs the installs in the order Capture, Quick Access,
    /// Editor, Recording, Text. `extraInstall` runs after them (tests only). Throws on a registry conflict and on
    /// any duplicate router, Settings-pane or debug-command registration.
    init(
        settingsStore: any SettingsStore, secrets: any SecretStore, metadata: any FileMetadataStore, home: String,
        llm: (any LLMClient)? = nil, clipboard: any ClipboardWriter, notifier: any Notifier,
        screenPermission: any ScreenCapturePermission,
        applyActivationPolicy: @escaping @MainActor (ActivationPolicy) -> Void = { _ in },
        requestNotificationAuthorization: @escaping @Sendable () async -> Void = {},
        extraInstall: @MainActor (AppContext) -> Void = { _ in }
    ) throws(LaunchError) {
        let registry: FeatureRegistry
        do {
            registry = try FeatureRegistry(Self.modules)
        } catch {
            throw .conflicts(error.conflicts)
        }
        self.registry = registry
        self.settingsStore = settingsStore
        self.secrets = secrets
        self.metadata = metadata
        let llm = llm ?? AnthropicClient(secrets: secrets)
        self.llm = llm
        let general = GeneralSettings(store: settingsStore, home: home)
        self.general = general
        aiKey = AIKeySettings(secrets: secrets, client: llm, model: { general.settings.aiModel })
        self.requestNotificationAuthorization = requestNotificationAuthorization

        let context = AppContext(
            home: home, registry: registry, settingsStore: settingsStore, metadata: metadata, clipboard: clipboard,
            notifier: notifier, screenPermission: screenPermission, general: general,
            applyActivationPolicy: applyActivationPolicy)
        self.context = context
        CaptureWiring.install(context)
        QuickAccessWiring.install(context)
        EditorWiring.install(context)
        RecordingWiring.install(context)
        text = TextWiring.install(context)
        extraInstall(context)

        #if DEBUG
            let debugDuplicates = context.debugCommands.duplicates
        #else
            let debugDuplicates: [String] = []
        #endif
        let router = context.router.duplicates
        let panes = context.settingsPanes.duplicates
        guard router.isEmpty, panes.isEmpty, debugDuplicates.isEmpty else {
            throw .duplicates(router: router, settingsPanes: panes, debugCommands: debugDuplicates)
        }
    }
}
