import AICore
import BugeyeCore
import BugeyeTestSupport
import Foundation
import Testing

@Suite struct AnthropicClientTests {
    let request = LLMRequest(model: "claude-opus-5-5", messages: [.user("Reply with OK.")], maxTokens: 32, effort: .low)
    let secrets = FakeSecretStore([.anthropicAPIKey: "sk-ant-test"])
    let sleeper = SleepRecorder()

    func client(_ transport: RecordedTransport, secrets: FakeSecretStore? = nil) -> AnthropicClient {
        AnthropicClient(secrets: secrets ?? self.secrets, transport: transport, sleep: sleeper.sleep)
    }

    @Test func sendsTheKeyFromTheSecretStore() async throws {
        let transport = RecordedTransport([try .json(200, "response-end-turn")])
        let response = try await client(transport).send(request)
        #expect(response.text == "OK")
        #expect(transport.requests.map { $0.headers["x-api-key"] } == ["sk-ant-test"])
    }

    @Test func noKeyMeansNoRequest() async {
        let transport = RecordedTransport([])
        await #expect(throws: LLMError.missingKey) {
            try await client(transport, secrets: FakeSecretStore()).send(request)
        }
        await #expect(throws: LLMError.missingKey) {
            try await client(transport, secrets: FakeSecretStore([.anthropicAPIKey: ""])).send(request)
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func retriesOverloadThenSucceeds() async throws {
        let transport = RecordedTransport([
            try .json(529, "error-529"), try .json(429, "error-429-rate-limit", headers: ["Retry-After": "2"]),
            try .json(200, "response-end-turn"),
        ])
        #expect(try await client(transport).send(request).text == "OK")
        #expect(transport.requests.count == 3)
        #expect(sleeper.recorded == [.milliseconds(500), .seconds(2)])
    }

    @Test func aCancelledRequestIsNotRetried() async {
        let transport = RecordedTransport([.cancelled])
        await #expect(throws: LLMError.transport("cancelled")) {
            try await client(transport).send(request)
        }
        #expect(transport.requests.count == 1)
        #expect(sleeper.recorded.isEmpty)
    }

    @Test func givesUpAfterTwoRetries() async throws {
        let transport = RecordedTransport([
            try .json(529, "error-529"), try .json(529, "error-529"), try .json(529, "error-529"),
            try .json(200, "response-end-turn"),
        ])
        await #expect(throws: LLMError.http(status: 529, type: "overloaded_error", message: "Overloaded")) {
            try await client(transport).send(request)
        }
        #expect(transport.requests.count == 3)
    }

    @Test func aRejectedKeyIsNotRetried() async throws {
        let transport = RecordedTransport([try .json(401, "error-401"), try .json(200, "response-end-turn")])
        await #expect(
            throws: LLMError.http(status: 401, type: "authentication_error", message: "invalid x-api-key")
        ) {
            try await client(transport).send(request)
        }
        #expect(transport.requests.count == 1)
        #expect(sleeper.recorded.isEmpty)
    }

    @Test func aBadRequestIsNotRetried() async throws {
        let transport = RecordedTransport([try .json(400, "error-400"), try .json(200, "response-end-turn")])
        await #expect(throws: LLMError.self) { try await client(transport).send(request) }
        #expect(transport.requests.count == 1)
    }

    @Test func aSpendCapIsNotRetried() async throws {
        let transport = RecordedTransport([try .json(429, "error-429-spend-cap"), try .json(200, "response-end-turn")])
        await #expect(
            throws: LLMError.http(
                status: 429, type: "rate_limit_error", message: "You have reached your monthly spend limit.",
                code: "enforced_spend_limit_reached")
        ) {
            try await client(transport).send(request)
        }
        #expect(transport.requests.count == 1)
    }

    @Test func offlineIsRetriedThenReportedAsTransport() async throws {
        let transport = RecordedTransport([.offline, .offline, .offline])
        do {
            _ = try await client(transport).send(request)
            Issue.record("expected a transport error")
        } catch {
            guard case .transport = error else {
                Issue.record("expected .transport, got \(error)")
                return
            }
        }
        #expect(transport.requests.count == 3)
    }

    @Test func aRefusalIsAnAnswerNotAnError() async throws {
        let transport = RecordedTransport([try .json(200, "response-refusal")])
        let response = try await client(transport).send(request)
        #expect(response.stopReason == .refusal(category: "cyber"))
        #expect(transport.requests.count == 1)
    }
}
