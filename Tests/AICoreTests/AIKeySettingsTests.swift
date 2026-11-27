import AICore
import BugeyeCore
import BugeyeTestSupport
import Foundation
import Synchronization
import Testing

@MainActor @Suite struct AIKeySettingsTests {
    @Test func statusLinesAreExactlyTheSpecs() {
        #expect(
            AIKeyStatus.allCases.map(\.message) == [
                "No key saved.",
                "Key saved. Not tested yet.",
                "Key works.",
                "Key was rejected. Check it and save it again.",
                "Key works, but Anthropic refused the request. Check your plan and the model in Settings.",
                "Couldn't reach Anthropic. Check your connection.",
            ])
    }

    @Test func startsFromWhatTheKeychainHolds() {
        #expect(AIKeySettings(secrets: FakeSecretStore(), client: FakeLLM(), model: { "m" }).status == .noKey)
        let saved = FakeSecretStore([.anthropicAPIKey: "sk"])
        #expect(AIKeySettings(secrets: saved, client: FakeLLM(), model: { "m" }).status == .savedNotTested)
    }

    @Test func savingStoresTheTrimmedKeyInTheSecretStore() throws {
        let secrets = FakeSecretStore()
        let settings = AIKeySettings(secrets: secrets, client: FakeLLM(), model: { "m" })
        settings.save("  sk-ant-123 \n")
        #expect(try secrets.secret(for: .anthropicAPIKey) == "sk-ant-123")
        #expect(settings.status == .savedNotTested)
    }

    @Test func savingAnEmptyFieldChangesNothing() throws {
        let secrets = FakeSecretStore([.anthropicAPIKey: "sk"])
        let settings = AIKeySettings(secrets: secrets, client: FakeLLM(), model: { "m" })
        settings.save("   ")
        #expect(try secrets.secret(for: .anthropicAPIKey) == "sk")
        #expect(settings.status == .savedNotTested)
    }

    @Test func savingANewKeyReplacesTheOldOne() throws {
        let secrets = FakeSecretStore([.anthropicAPIKey: "old"])
        let settings = AIKeySettings(secrets: secrets, client: FakeLLM(), model: { "m" })
        settings.save("new")
        #expect(try secrets.secret(for: .anthropicAPIKey) == "new")
    }

    @Test func aKeychainFailureShowsWhatIsStillStored() {
        let secrets = FakeSecretStore()
        let settings = AIKeySettings(secrets: secrets, client: FakeLLM(), model: { "m" })
        secrets.failNextWrite()
        settings.save("sk")
        #expect(settings.status == .noKey)
    }

    @Test func aFailedSaveOverAnOlderKeyDoesNotClaimTheNewOneWasSaved() async throws {
        let secrets = FakeSecretStore([.anthropicAPIKey: "old"])
        let settings = AIKeySettings(
            secrets: secrets, client: FakeLLM([.success(FakeLLM.reply("OK"))]), model: { "m" })
        await settings.testKey()
        #expect(settings.status == .works)
        secrets.failNextWrite()
        settings.save("new")
        // The old key is still the one stored and it still works: nothing changed, so the status doesn't either.
        #expect(settings.status == .works)
        #expect(try secrets.secret(for: .anthropicAPIKey) == "old")
    }

    @Test func testingSendsOneTinyRequestWithTheChosenModel() async {
        let llm = FakeLLM([.success(FakeLLM.reply("OK"))])
        let settings = AIKeySettings(
            secrets: FakeSecretStore([.anthropicAPIKey: "sk"]), client: llm, model: { "claude-haiku-5-5" })
        await settings.testKey()
        #expect(settings.status == .works)
        #expect(
            llm.requests == [
                LLMRequest(
                    model: "claude-haiku-5-5", messages: [.user("Reply with OK.")], maxTokens: 32, effort: .low,
                    timeout: 15)
            ])
        #expect(!settings.isTesting)
    }

    @Test func testingWithoutAKeySendsNothing() async {
        let llm = FakeLLM()
        let settings = AIKeySettings(secrets: FakeSecretStore(), client: llm, model: { "m" })
        await settings.testKey()
        #expect(settings.status == .noKey)
        #expect(llm.requests.isEmpty)
    }

    @Test(arguments: [
        // Authentication failures: the key is wrong.
        (LLMError.http(status: 401, type: "authentication_error", message: "invalid x-api-key"), AIKeyStatus.rejected),
        (.http(status: 403, type: "authentication_error", message: nil), .rejected),
        (.http(status: 403, type: nil, message: nil), .rejected),
        // The key works, but the account or the model can't serve the request.
        (.http(status: 403, type: "permission_error", message: "not allowed for this credential"), .refused),
        (.http(status: 400, type: "invalid_request_error", message: "model: claude-nope is not supported"), .refused),
        (
            .http(
                status: 400, type: "invalid_request_error",
                message: "Unexpected value(s) for the `anthropic-beta` header"), .refused
        ),
        (.http(status: 402, type: "billing_error", message: "Your credit balance is too low"), .refused),
        (.http(status: 404, type: "not_found_error", message: "model: claude-nope"), .refused),
        (
            .http(
                status: 429, type: "rate_limit_error", message: "monthly spend limit",
                code: "enforced_spend_limit_reached"), .refused
        ),
        // Nothing to do with the key or the plan: the network, load, or our own request.
        (.http(status: 429, type: "rate_limit_error", message: "per-minute rate limit"), .unreachable),
        (.http(status: 529, type: "overloaded_error", message: "Overloaded"), .unreachable),
        (.http(status: 500, type: "api_error", message: nil), .unreachable),
        (.http(status: 400, type: "invalid_request_error", message: "messages: roles must alternate"), .unreachable),
        (.transport("offline"), .unreachable),
        (.decoding("bad body"), .works),
        // Anthropic answered, so the key works: a refusal is the "refused" line, a cut-off answer still works.
        (.refused(category: "cyber"), .refused),
        (.truncated, .works),
        (.missingKey, .noKey),
    ])
    func failuresMapToTheStatusLine(error: LLMError, expected: AIKeyStatus) async {
        let settings = AIKeySettings(
            secrets: FakeSecretStore([.anthropicAPIKey: "sk"]), client: FakeLLM([.failure(error)]), model: { "m" })
        await settings.testKey()
        #expect(settings.status == expected)
    }

    @Test func theSpendCapCodeReachesTheStatusLineThroughTheClient() async throws {
        let body =
            #"{"type":"error","error":{"type":"rate_limit_error","message":"cap","details":{"error_code":"enforced_spend_limit_reached"}}}"#
        let transport = RecordedTransport([.response(TransportResponse(status: 429, body: Data(body.utf8)))])
        let secrets = FakeSecretStore([.anthropicAPIKey: "sk"])
        let settings = AIKeySettings(
            secrets: secrets, client: AnthropicClient(secrets: secrets, transport: transport, sleep: { _ in }),
            model: { "claude-opus-5-5" })
        await settings.testKey()
        #expect(settings.status == .refused)
    }

    @Test func aTestThatFinishesAfterANewSaveIsIgnored() async {
        let gate = GatedLLM()
        let settings = AIKeySettings(secrets: FakeSecretStore([.anthropicAPIKey: "old"]), client: gate, model: { "m" })
        let test = Task { await settings.testKey() }
        await gate.waitUntilCalled()
        settings.save("new")
        gate.release(.failure(.http(status: 401, type: nil, message: nil)))
        await test.value
        #expect(settings.status == .savedNotTested)
    }

    @Test func aNewKeyCanBeTestedWhileAnOldTestIsStillRunning() async throws {
        let llm = SequencedLLM()
        let settings = AIKeySettings(secrets: FakeSecretStore([.anthropicAPIKey: "old"]), client: llm, model: { "m" })
        let old = Task { await settings.testKey() }
        await llm.waitUntilCalled()
        settings.save("new")
        // Without this, the second press would wait for a stale answer that may never come.
        try #require(!settings.isTesting)
        let new = Task { await settings.testKey() }
        await llm.waitUntilCalled()
        #expect(settings.isTesting)
        llm.release(call: 0, .failure(.http(status: 401, type: nil, message: nil)))
        await old.value
        // The stale answer neither changes the status nor ends the new test.
        #expect(settings.isTesting)
        #expect(settings.status == .savedNotTested)
        llm.release(call: 1, .success(FakeLLM.reply("OK")))
        await new.value
        #expect(settings.status == .works)
        #expect(!settings.isTesting)
    }
}

/// An LLM whose calls each wait for their own answer, released by the test in any order.
final class SequencedLLM: LLMClient {
    private let called = AsyncStream<Void>.makeStream()
    private let pending = Mutex<[Int: CheckedContinuation<Result<LLMResponse, LLMError>, Never>]>([:])
    private let early = Mutex<[Int: Result<LLMResponse, LLMError>]>([:])
    private let count = Mutex(0)

    func send(_ request: LLMRequest) async throws(LLMError) -> LLMResponse {
        let index = count.withLock { n in
            defer { n += 1 }
            return n
        }
        let answer = await withCheckedContinuation { continuation in
            if let ready = early.withLock({ $0.removeValue(forKey: index) }) {
                continuation.resume(returning: ready)
            } else {
                pending.withLock { $0[index] = continuation }
            }
            called.continuation.yield()
        }
        return try answer.get()
    }

    func waitUntilCalled() async {
        var iterator = called.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func release(call index: Int, _ answer: Result<LLMResponse, LLMError>) {
        if let continuation = pending.withLock({ $0.removeValue(forKey: index) }) {
            continuation.resume(returning: answer)
        } else {
            early.withLock { $0[index] = answer }
        }
    }
}

/// An LLM whose answer the test releases by hand, to order events without sleeping.
final class GatedLLM: LLMClient {
    private let called = AsyncStream<Void>.makeStream()
    private let answers = AsyncStream<Result<LLMResponse, LLMError>>.makeStream()

    func send(_ request: LLMRequest) async throws(LLMError) -> LLMResponse {
        called.continuation.yield()
        var iterator = answers.stream.makeAsyncIterator()
        guard let answer = await iterator.next() else { throw .transport("no answer") }
        return try answer.get()
    }

    func waitUntilCalled() async {
        var iterator = called.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func release(_ answer: Result<LLMResponse, LLMError>) {
        answers.continuation.yield(answer)
    }
}
