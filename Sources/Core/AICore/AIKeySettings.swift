import BugeyeCore
import Foundation
import Observation

/// The AI pane's status line. Exactly one is shown (spec §5.3).
public enum AIKeyStatus: Hashable, Sendable, CaseIterable {
    case noKey, savedNotTested, works, rejected, refused, unreachable, saveFailed

    public var message: String {
        switch self {
        case .noKey: "No key saved."
        case .savedNotTested: "Key saved. Not tested yet."
        case .works: "Key works."
        case .rejected: "Key was rejected. Check it and save it again."
        case .refused: "Key works, but Anthropic refused the request. Check your plan and the model in Settings."
        case .unreachable: "Couldn't reach Anthropic. Check your connection."
        case .saveFailed: "Couldn't save the key. Try again."
        }
    }

    /// The status a finished key test shows (plan ruling P7).
    public static func afterTest(_ result: Result<LLMResponse, LLMError>) -> AIKeyStatus {
        switch result {
        case .success:
            return .works
        // A 2xx answer we couldn't read still proves the key was accepted.
        case .failure(.decoding):
            return .works
        case .failure(.missingKey):
            return .noKey
        case .failure(.http(let status, let type, let message, let code)):
            return afterHTTPError(status: status, type: type, message: message, code: code)
        // Anthropic answered: a refusal means the key works but the request was refused, and a cut-off
        // answer still proves the key was accepted.
        case .failure(.refused):
            return .refused
        case .failure(.truncated):
            return .works
        case .failure(.transport):
            return .unreachable
        }
    }

    /// Authentication failures say the key is wrong; account and model problems say the key works but the
    /// request was refused; everything else (rate limits and 5xx after the retries) is "couldn't reach".
    static func afterHTTPError(status: Int, type: String?, message: String?, code: String?) -> AIKeyStatus {
        switch status {
        case 401:
            return .rejected
        case 403:
            // A permission error means the key authenticated but may not do this; anything else is an auth failure.
            return type == "permission_error" ? .refused : .rejected
        case 400:
            // Only a request the account or model can't serve; a malformed request is a bug, not the user's plan.
            let text = (message ?? "").lowercased()
            return text.contains("model") || text.contains("anthropic-beta") ? .refused : .unreachable
        case 402, 404:
            return .refused
        case 429:
            return code == "enforced_spend_limit_reached" ? .refused : .unreachable
        default:
            return .unreachable
        }
    }
}

/// The AI pane's logic: save the key to the Keychain, test it with one tiny request. Portable, so it is
/// tested on Linux; the SwiftUI pane only renders it.
@MainActor @Observable
public final class AIKeySettings {
    public private(set) var status: AIKeyStatus
    public private(set) var isTesting = false

    @ObservationIgnored private let secrets: any SecretStore
    @ObservationIgnored private let client: any LLMClient
    @ObservationIgnored private let model: @MainActor () -> String
    /// Bumped by every save, so a load or test that finishes after a new key was saved doesn't report on it.
    @ObservationIgnored private var generation = 0
    /// The latest Keychain write. Each write waits for the one before it, so the Keychain always ends up
    /// with the last key saved; reads wait for it too, so they never see a key that is being replaced.
    @ObservationIgnored private var lastWrite: Task<Bool, Never>?

    /// Touches nothing slow: the status starts at "No key saved." and `load()` reads the Keychain.
    public init(secrets: any SecretStore, client: any LLMClient, model: @escaping @MainActor () -> String) {
        self.secrets = secrets
        self.client = client
        self.model = model
        status = .noKey
    }

    /// Reads whether a key is stored, off the main actor (the Keychain can block on a prompt or a locked
    /// keychain). The app calls it once at launch. Ignored if a key was saved meanwhile.
    public func load() async {
        let started = generation
        _ = await lastWrite?.value
        let stored = await Self.hasKey(secrets)
        guard generation == started else { return }
        status = stored ? .savedNotTested : .noKey
    }

    /// Saves the typed key (trimmed), from the Save button or Return. An empty field changes nothing:
    /// removing a key is not a Wave 0 feature, and a stray click or Return must not delete it. If the Keychain
    /// refuses, the status says so and any key stored before stays. The Keychain write runs off the main actor;
    /// if another save starts meanwhile, the later one decides the status.
    public func save(_ typed: String) async {
        let key = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        generation += 1
        let started = generation
        // A test still running is about the old key: its answer is ignored, so the new key can be tested now.
        isTesting = false
        let secrets = secrets
        let previous = lastWrite
        let write = Task.detached { () -> Bool in
            _ = await previous?.value
            do {
                try secrets.setSecret(key, for: .anthropicAPIKey)
                return true
            } catch {
                return false
            }
        }
        lastWrite = write
        let stored = await write.value
        guard generation == started else { return }
        status = stored ? .savedNotTested : .saveFailed
    }

    /// Seconds each attempt of the key test waits. With the client's two retries, a stalled connection shows
    /// "Couldn't reach Anthropic." after under a minute instead of the transport's 10-minute default per try.
    public static let testTimeout: TimeInterval = 15

    /// The request "Test key" sends: the smallest that proves the key works.
    public func testRequest() -> LLMRequest {
        LLMRequest(
            model: model(), messages: [.user("Reply with OK.")], maxTokens: 32, effort: .low, timeout: Self.testTimeout)
    }

    public func testKey() async {
        guard !isTesting else { return }
        isTesting = true
        let started = generation
        // A stale test (a new key was saved meanwhile) must not end the test that replaced it.
        defer { if generation == started { isTesting = false } }
        _ = await lastWrite?.value
        guard await Self.hasKey(secrets) else {
            if generation == started { status = .noKey }
            return
        }
        guard generation == started else { return }
        let result: Result<LLMResponse, LLMError>
        do {
            result = .success(try await client.send(testRequest()))
        } catch {
            result = .failure(error)
        }
        guard generation == started else { return }
        status = AIKeyStatus.afterTest(result)
    }

    /// Whether a non-empty key is stored, read off the main actor.
    private static func hasKey(_ secrets: any SecretStore) async -> Bool {
        await offMainActor {
            guard let key = (try? secrets.secret(for: .anthropicAPIKey)) ?? nil else { return false }
            return !key.isEmpty
        }
    }

    /// Runs blocking work (Keychain calls) on the cooperative pool, never on the main actor.
    private nonisolated static func offMainActor<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(operation: work).value
    }
}
