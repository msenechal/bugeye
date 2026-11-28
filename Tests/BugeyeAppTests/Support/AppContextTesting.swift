import BugeyeCore
import BugeyeFeatures
import BugeyeTestSupport
import Foundation

@testable import BugeyeApp

/// Records what a context's `DocumentWindows` applied.
@MainActor
final class ActivationPolicyLog {
    private(set) var applied: [ActivationPolicy] = []
    func record(_ policy: ActivationPolicy) { applied.append(policy) }
}

extension AppContext {
    /// The one test builder for `AppContext` (contract, K40). Every port defaults to its fake; every shell object
    /// (bus, router, gates, …) is a fresh real instance; the activation-policy closure records its calls in
    /// `policies`. Pass `home` from a `TempDirectory`. `modules` must not conflict.
    static func testing(
        home: String, settings: InMemorySettingsStore = .init(), metadata: FakeFileMetadataStore = .init(),
        notifier: FakeNotifier = .init(), clipboard: FakeClipboard = .init(),
        screenPermission: FakeScreenCapturePermission = .init(granted: true),
        modules: [any FeatureModule] = [GeneralModule()], policies: ActivationPolicyLog = ActivationPolicyLog()
    ) -> AppContext {
        let registry: FeatureRegistry
        do {
            registry = try FeatureRegistry(modules)
        } catch {
            preconditionFailure("AppContext.testing: modules conflict: \(error.conflicts)")
        }
        return AppContext(
            home: home, registry: registry, settingsStore: settings, metadata: metadata, clipboard: clipboard,
            notifier: notifier, screenPermission: screenPermission,
            general: GeneralSettings(store: settings, home: home),
            applyActivationPolicy: { policies.record($0) })
    }
}
