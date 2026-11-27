import BugeyeCore
import Foundation
import Observation

/// The AI pane's status line. Exactly one is shown (spec §5.3).
public enum AIKeyStatus: Hashable, Sendable, CaseIterable {
    case noKey, savedNotTested, works, rejected, refused, unreachable

    public var message: String {
        switch self {
        case .noKey: "No key saved."
        case .savedNotTested: "Key saved. Not tested yet."
        case .works: "Key works."
        case .rejected: "Key was rejected. Check it and save it again."
        case .refused: "Key works, but Anthropic refused the request. Check your plan and the model in Settings."
        case .unreachable: "Couldn't reach Anthropic. Check your connection."
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
        case .failure(.transport), .failure(.refused), .failure(.truncated):
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
    /// Bumped by every save, so a test that finishes after a new key was saved doesn't report on it.
    @ObservationIgnored private var generation = 0

    public init(secrets: any SecretStore, client: any LLMClient, model: @escaping @MainActor () -> String) {
        self.secrets = secrets
        self.client = client
        self.model = model
        status = Self.hasKey(secrets) ? .savedNotTested : .noKey
    }

    /// Saves the typed key (trimmed), from the Save button or Return. An empty field changes nothing:
    /// removing a key is not a Wave 0 feature, and a stray click or Return must not delete it. If the Keychain refuses, the status shows
    /// whatever is still stored.
    public func save(_ typed: String) {
        let key = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        generation += 1
        do {
            try secrets.setSecret(key, for: .anthropicAPIKey)
        } catch {
            // Fall through: the status below shows what the Keychain holds.
        }
        status = Self.hasKey(secrets) ? .savedNotTested : .noKey
    }

    /// The request "Test key" sends: the smallest that proves the key works.
    public func testRequest() -> LLMRequest {
        LLMRequest(model: model(), messages: [.user("Reply with OK.")], maxTokens: 32, effort: .low)
    }

    public func testKey() async {
        guard !isTesting else { return }
        guard Self.hasKey(secrets) else {
            status = .noKey
            return
        }
        isTesting = true
        defer { isTesting = false }
        let started = generation
        let result: Result<LLMResponse, LLMError>
        do {
            result = .success(try await client.send(testRequest()))
        } catch {
            result = .failure(error)
        }
        guard generation == started else { return }
        status = AIKeyStatus.afterTest(result)
    }

    private static func hasKey(_ secrets: any SecretStore) -> Bool {
        guard let key = (try? secrets.secret(for: .anthropicAPIKey)) ?? nil else { return false }
        return !key.isEmpty
    }
}
