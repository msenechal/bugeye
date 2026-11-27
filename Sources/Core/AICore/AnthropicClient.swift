import BugeyeCore
import Foundation

/// `LLMClient` over the Anthropic Messages API. The key comes from the `SecretStore` on every call, so a
/// key saved in Settings is used at once. There is no official Swift SDK, so this is plain HTTP.
public struct AnthropicClient: LLMClient {
    private let secrets: any SecretStore
    private let transport: any HTTPTransport
    private let policy: RetryPolicy
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        secrets: any SecretStore, transport: any HTTPTransport = URLSessionTransport(),
        policy: RetryPolicy = RetryPolicy(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.secrets = secrets
        self.transport = transport
        self.policy = policy
        self.sleep = sleep
    }

    public func send(_ request: LLMRequest) async throws(LLMError) -> LLMResponse {
        guard let key = (try? secrets.secret(for: .anthropicAPIKey)) ?? nil, !key.isEmpty else {
            throw .missingKey
        }
        let httpRequest: TransportRequest
        do {
            httpRequest = try AnthropicWire.httpRequest(for: request, apiKey: key)
        } catch {
            throw .decoding("Couldn't encode the request: \(error)")
        }

        var retries = 0
        while true {
            let failure: LLMError
            let outcome: RetryPolicy.Outcome
            do {
                let response = try await transport.send(httpRequest)
                if (200..<300).contains(response.status) {
                    return try AnthropicWire.response(from: response.body)
                }
                let apiError = AnthropicWire.apiError(from: response.body)
                failure = .http(
                    status: response.status, type: apiError.type, message: apiError.message, code: apiError.code)
                outcome = .status(
                    response.status, retryAfter: response.header("retry-after"),
                    shouldRetry: response.header("x-should-retry"), errorCode: apiError.code)
            } catch let error as LLMError {
                throw error
            } catch is CancellationError {
                throw .transport("cancelled")
            } catch {
                failure = .transport(String(describing: error))
                outcome = .connectionFailed
            }

            guard let delay = policy.delay(after: outcome, retriesSoFar: retries) else { throw failure }
            do {
                try await sleep(delay)
            } catch {
                throw .transport("cancelled")
            }
            retries += 1
        }
    }
}
