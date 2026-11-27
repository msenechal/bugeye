import AICore
import BugeyeCore
import Foundation
import Testing

@Suite struct AnthropicWireTests {
    @Test func theKeyTestRequestMatchesItsFixture() throws {
        let request = LLMRequest(
            model: "claude-opus-5-5", messages: [.user("Reply with OK.")], maxTokens: 32, effort: .low)
        let http = try AnthropicWire.httpRequest(for: request, apiKey: "sk-ant-test")

        #expect(http.url.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(http.method == "POST")
        #expect(
            http.headers == [
                "x-api-key": "sk-ant-test",
                "anthropic-version": "2026-10-21",
                "content-type": "application/json",
                "anthropic-beta": "server-side-fallback-2026-07-01",
            ])
        #expect(try JSONValue.parse(http.body) == JSONValue.parse(fixture("request-key-test")))
    }

    @Test func imagesGoFirstAsBase64AndHaikuGetsNoFallback() throws {
        let request = LLMRequest(
            model: "claude-haiku-5-5", system: "You write captions.",
            messages: [
                LLMMessage(
                    role: .user,
                    content: [
                        .image(mediaType: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47])),
                        .text("Describe this screenshot."),
                    ])
            ], maxTokens: 1024)
        let http = try AnthropicWire.httpRequest(for: request, apiKey: "k")

        #expect(http.headers["anthropic-beta"] == nil)
        #expect(try JSONValue.parse(http.body) == JSONValue.parse(fixture("request-image-haiku")))
    }

    @Test func aResponseJoinsTextBlocksAndSkipsThinking() throws {
        let response = try AnthropicWire.response(from: fixture("response-end-turn"))
        #expect(
            response
                == LLMResponse(
                    id: "msg_01XFDUDYJgAACzvnptvVoYEL", model: "claude-opus-5-5", stopReason: .endTurn, text: "OK",
                    inputTokens: 14, outputTokens: 6))
    }

    @Test func aRefusalCarriesItsCategory() throws {
        let response = try AnthropicWire.response(from: fixture("response-refusal"))
        #expect(response.stopReason == .refusal(category: "cyber"))
        #expect(throws: LLMError.refused(category: "cyber")) { try response.completeText() }
    }

    @Test func aServerSideFallbackIsReadLikeAnyAnswer() throws {
        let response = try AnthropicWire.response(from: fixture("response-fallback"))
        #expect(response.model == "claude-opus-4-8")
        #expect(try response.completeText() == "Here is the caption.")
    }

    @Test func aCutOffAnswerIsNotComplete() throws {
        let response = try AnthropicWire.response(from: fixture("response-max-tokens"))
        #expect(response.stopReason == .maxTokens)
        #expect(throws: LLMError.truncated) { try response.completeText() }
    }

    @Test func unknownStopReasonsAreKept() throws {
        let body = #"{"id":"m","model":"x","content":[],"stop_reason":"something_new","usage":{}}"#
        #expect(try AnthropicWire.response(from: Data(body.utf8)).stopReason == .other("something_new"))
    }

    @Test func anUnreadableBodyIsADecodingError() {
        #expect(throws: LLMError.self) { try AnthropicWire.response(from: Data("<html>".utf8)) }
    }

    @Test func errorBodiesGiveTypeMessageAndCode() throws {
        #expect(
            AnthropicWire.apiError(from: try fixture("error-429-spend-cap"))
                == AnthropicWire.APIError(
                    type: "rate_limit_error", message: "You have reached your monthly spend limit.",
                    code: "enforced_spend_limit_reached"))
        #expect(
            AnthropicWire.apiError(from: Data("nope".utf8))
                == AnthropicWire.APIError(type: nil, message: nil, code: nil))
    }
}
