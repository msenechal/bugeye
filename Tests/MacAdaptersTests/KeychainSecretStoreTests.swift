import BugeyeCore
import Foundation
import MacAdapters
import Testing

/// Real Keychain round trips under a unique service name, never the app's own. Opt-in with
/// BUGEYE_KEYCHAIN_TESTS=1 (the macOS CI job sets it) so a locked keychain can't stall a local run.
@Suite(
    .enabled(if: ProcessInfo.processInfo.environment["BUGEYE_KEYCHAIN_TESTS"] == "1"),
    .timeLimit(.minutes(1)))
struct KeychainSecretStoreTests {
    @Test func setReadReplaceAndRemove() throws {
        let store = KeychainSecretStore(service: "dev.msenechal.bugeye.tests.\(UUID().uuidString)")
        defer { try? store.removeSecret(for: .anthropicAPIKey) }

        #expect(try store.secret(for: .anthropicAPIKey) == nil)
        try store.setSecret("sk-ant-one", for: .anthropicAPIKey)
        #expect(try store.secret(for: .anthropicAPIKey) == "sk-ant-one")
        try store.setSecret("sk-ant-two", for: .anthropicAPIKey)
        #expect(try store.secret(for: .anthropicAPIKey) == "sk-ant-two")
        try store.removeSecret(for: .anthropicAPIKey)
        try store.removeSecret(for: .anthropicAPIKey)
        #expect(try store.secret(for: .anthropicAPIKey) == nil)
    }

    @Test func theDefaultServiceIsTheBundleID() {
        #expect(KeychainSecretStore().service == "dev.msenechal.bugeye")
    }
}
