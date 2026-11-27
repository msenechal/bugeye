import BugeyeCore
import BugeyeTestSupport
import Foundation
import Testing

@Suite struct FakeServicesTests {
    @Test func fakeLLMAnswersInOrderAndRecordsRequests() async throws {
        let llm = FakeLLM([.success(FakeLLM.reply("one")), .failure(.truncated)])
        let request = LLMRequest(model: "claude-opus-5-5", messages: [.user("Hi")], maxTokens: 10)

        #expect(try await llm.send(request).text == "one")
        await #expect(throws: LLMError.truncated) { try await llm.send(request) }
        await #expect(throws: LLMError.transport("FakeLLM has no scripted answer")) { try await llm.send(request) }
        #expect(llm.requests.count == 3)
    }

    @Test func fakeSecretStoreCanFailOneWrite() throws {
        let secrets = FakeSecretStore()
        secrets.failNextWrite()
        #expect(throws: FakeSecretStore.WriteFailed.self) { try secrets.setSecret("k", for: .anthropicAPIKey) }
        try secrets.setSecret("k", for: .anthropicAPIKey)
        #expect(try secrets.secret(for: .anthropicAPIKey) == "k")
        try secrets.removeSecret(for: .anthropicAPIKey)
        #expect(try secrets.secret(for: .anthropicAPIKey) == nil)
    }

    @Test func inMemorySettingsStoreRemovesOnNil() {
        let store = InMemorySettingsStore(["a": .bool(true)])
        store.setValue(nil, forKey: "a")
        store.setValue(.int(3), forKey: "b")
        #expect(store.all == ["b": .int(3)])
    }

    @Test func fakeIndexSearchesTextNewestFirst() async throws {
        let index = FakeCaptureIndexStore()
        let old = CaptureRecord(
            id: CaptureID(), path: "/a", createdAt: Date(timeIntervalSince1970: 1), text: "Login error")
        let new = CaptureRecord(
            id: CaptureID(), path: "/b", createdAt: Date(timeIntervalSince1970: 2), text: "error 500")
        try await index.upsert(old)
        try await index.upsert(new)
        #expect(try await index.search("ERROR", limit: 10) == [new, old])
        #expect(try await index.search("error", limit: 1) == [new])
        try await index.remove(new.id)
        #expect(try await index.record(new.id) == nil)
    }

    @Test func tempDirectoriesAreUnique() throws {
        let a = try TempDirectory()
        let b = try TempDirectory()
        defer {
            a.remove()
            b.remove()
        }
        #expect(a.url != b.url)
        #expect(try a.contents() == [])
    }
}
