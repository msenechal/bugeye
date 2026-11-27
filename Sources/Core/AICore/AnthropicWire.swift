import BugeyeCore
import Foundation

/// The Messages API on the wire (`POST /v1/messages`), per the `claude-api` skill as of November 2026.
public enum AnthropicWire {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let apiVersion = "2026-10-21"
    public static let fallbackBeta = "server-side-fallback-2026-07-01"

    /// Models that take `fallbacks: "default"`: on a refusal the API re-runs the request on a fallback
    /// model inside the same call. Other models (Haiku 5.5 among them) reject the parameter.
    public static let modelsWithServerSideFallback: Set<String> = [
        "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5", "claude-fable-5-2", "claude-fable-5-1",
    ]

    public static func httpRequest(for request: LLMRequest, apiKey: String) throws -> TransportRequest {
        let usesFallback = modelsWithServerSideFallback.contains(request.model)
        var headers = [
            "x-api-key": apiKey,
            "anthropic-version": apiVersion,
            "content-type": "application/json",
        ]
        if usesFallback { headers["anthropic-beta"] = fallbackBeta }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let body = try encoder.encode(Body(request, fallback: usesFallback))
        return TransportRequest(url: endpoint, method: "POST", headers: headers, body: body)
    }

    /// Decodes a 2xx body. Unknown content block types (thinking, fallback, future ones) are skipped.
    public static func response(from data: Data) throws(LLMError) -> LLMResponse {
        let message: Message
        do {
            message = try JSONDecoder().decode(Message.self, from: data)
        } catch {
            throw .decoding(String(describing: error))
        }
        return LLMResponse(
            id: message.id,
            model: message.model,
            stopReason: stopReason(message.stop_reason, details: message.stop_details),
            text: message.content.compactMap { $0.type == "text" ? $0.text : nil }.joined(),
            inputTokens: message.usage?.input_tokens ?? 0,
            outputTokens: message.usage?.output_tokens ?? 0)
    }

    /// The `error` object of a non-2xx body, when there is one.
    public struct APIError: Hashable, Sendable {
        public var type: String?
        public var message: String?
        public var code: String?

        public init(type: String?, message: String?, code: String?) {
            self.type = type
            self.message = message
            self.code = code
        }
    }

    public static func apiError(from data: Data) -> APIError {
        guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) else {
            return APIError(type: nil, message: nil, code: nil)
        }
        return APIError(
            type: envelope.error?.type, message: envelope.error?.message, code: envelope.error?.details?.error_code)
    }

    static func stopReason(_ raw: String?, details: StopDetails?) -> LLMStopReason {
        switch raw {
        case "end_turn": .endTurn
        case "max_tokens": .maxTokens
        case "stop_sequence": .stopSequence
        case "tool_use": .toolUse
        case "pause_turn": .pauseTurn
        case "refusal": .refusal(category: details?.category)
        case let other: .other(other ?? "")
        }
    }

    // MARK: Request body

    struct Body: Encodable {
        let model: String
        let max_tokens: Int
        let system: String?
        let messages: [WireMessage]
        let output_config: OutputConfig?
        let fallbacks: String?

        init(_ request: LLMRequest, fallback: Bool) {
            model = request.model
            max_tokens = request.maxTokens
            system = request.system
            messages = request.messages.map(WireMessage.init)
            output_config = request.effort.map { OutputConfig(effort: $0.rawValue) }
            fallbacks = fallback ? "default" : nil
        }
    }

    struct OutputConfig: Encodable {
        let effort: String
    }

    struct WireMessage: Encodable {
        let role: String
        let content: [Block]

        init(_ message: LLMMessage) {
            role = message.role.rawValue
            content = message.content.map(Block.init)
        }
    }

    struct Block: Encodable {
        let type: String
        let text: String?
        let source: ImageSource?

        init(_ content: LLMContent) {
            switch content {
            case .text(let text):
                type = "text"
                self.text = text
                source = nil
            case .image(let mediaType, let data):
                type = "image"
                text = nil
                source = ImageSource(type: "base64", media_type: mediaType, data: data.base64EncodedString())
            }
        }
    }

    struct ImageSource: Encodable {
        let type: String
        let media_type: String
        let data: String
    }

    // MARK: Response body

    struct Message: Decodable {
        let id: String
        let model: String
        let content: [ContentBlock]
        let stop_reason: String?
        let stop_details: StopDetails?
        let usage: Usage?
    }

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    struct StopDetails: Decodable {
        let category: String?
    }

    struct Usage: Decodable {
        let input_tokens: Int?
        let output_tokens: Int?
    }

    struct ErrorEnvelope: Decodable {
        struct Details: Decodable { let error_code: String? }
        struct Body: Decodable {
            let type: String?
            let message: String?
            let details: Details?
        }
        let error: Body?
    }
}
