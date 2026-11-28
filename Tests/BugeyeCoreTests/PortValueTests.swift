import BugeyeCore
import Testing

@Suite struct PortValueTests {
    @Test func theAnthropicKeyHasAFixedName() {
        #expect(SecretKey.anthropicAPIKey.rawValue == "anthropic-api-key")
    }

    @Test func completeTextChecksTheStopReason() throws {
        func response(_ reason: LLMStopReason) -> LLMResponse {
            LLMResponse(id: "msg_1", model: "m", stopReason: reason, text: "Hi", inputTokens: 1, outputTokens: 1)
        }
        #expect(try response(.endTurn).completeText() == "Hi")
        #expect(throws: LLMError.refused(category: "cyber")) {
            try response(.refusal(category: "cyber")).completeText()
        }
        #expect(throws: LLMError.truncated) { try response(.maxTokens).completeText() }
    }
}
