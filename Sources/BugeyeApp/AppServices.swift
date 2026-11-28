import AICore
import BugeyeCore
import BugeyeFeatures
import Foundation
import MacAdapters

/// The composition root: every adapter and model the app runs on, built once at launch. Features add
/// their module to `modules` and nothing else (`design/14` R1).
@MainActor
struct AppServices {
    static let modules: [any FeatureModule] = [GeneralModule()]

    let registry: FeatureRegistry
    let settingsStore: any SettingsStore
    let secrets: any SecretStore
    let metadata: any FileMetadataStore
    let llm: any LLMClient
    let general: GeneralSettings
    let aiKey: AIKeySettings

    static func live() throws(FeatureRegistryError) -> AppServices {
        try AppServices(
            settingsStore: UserDefaultsSettingsStore(), secrets: KeychainSecretStore(), metadata: XattrMetadataStore(),
            home: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    init(
        settingsStore: any SettingsStore, secrets: any SecretStore, metadata: any FileMetadataStore, home: String,
        llm: (any LLMClient)? = nil
    ) throws(FeatureRegistryError) {
        registry = try FeatureRegistry(Self.modules)
        self.settingsStore = settingsStore
        self.secrets = secrets
        self.metadata = metadata
        let llm = llm ?? AnthropicClient(secrets: secrets)
        self.llm = llm
        let general = GeneralSettings(store: settingsStore, home: home)
        self.general = general
        aiKey = AIKeySettings(secrets: secrets, client: llm, model: { general.settings.aiModel })
    }
}
