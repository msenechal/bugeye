import Foundation

// The LLMClient port and its portable value types. The Anthropic wire format lives in AICore.

/// How hard the model thinks. Sent as `output_config.effort`.
public enum LLMEffort: String, Hashable, Codable, Sendable, CaseIterable {
    case low, medium, high, xhigh, max
}

public enum LLMRole: String, Hashable, Codable, Sendable {
    case user, assistant
}

public enum LLMContent: Hashable, Sendable {
    case text(String)
    /// An image, placed before the text that refers to it. Downscale it to what the feature needs first.
    case image(mediaType: String, data: Data)
}

public struct LLMMessage: Hashable, Sendable {
    public var role: LLMRole
    public var content: [LLMContent]

    public init(role: LLMRole, content: [LLMContent]) {
        self.role = role
        self.content = content
    }

    public static func user(_ text: String) -> LLMMessage {
        LLMMessage(role: .user, content: [.text(text)])
    }
}

public struct LLMRequest: Hashable, Sendable {
    /// The model ID. A setting (`AppSettings.aiModel`), so the user can pick a cheaper model.
    public var model: String
    public var system: String?
    public var messages: [LLMMessage]
    public var maxTokens: Int
    public var effort: LLMEffort?

    public init(model: String, system: String? = nil, messages: [LLMMessage], maxTokens: Int, effort: LLMEffort? = nil)
    {
        self.model = model
        self.system = system
        self.messages = messages
        self.maxTokens = maxTokens
        self.effort = effort
    }
}

/// Why the model stopped. Always check it before reading the text.
public enum LLMStopReason: Hashable, Sendable {
    case endTurn
    case maxTokens
    case stopSequence
    case toolUse
    case pauseTurn
    case refusal(category: String?)
    case other(String)
}

public struct LLMResponse: Hashable, Sendable {
    public var id: String
    /// The model that produced the answer (a server-side fallback may differ from the one requested).
    public var model: String
    public var stopReason: LLMStopReason
    /// Every text block, joined in order. Thinking and unknown blocks are left out.
    public var text: String
    public var inputTokens: Int
    public var outputTokens: Int

    public init(
        id: String, model: String, stopReason: LLMStopReason, text: String, inputTokens: Int, outputTokens: Int
    ) {
        self.id = id
        self.model = model
        self.stopReason = stopReason
        self.text = text
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    /// The text, once the stop reason says it's complete. A refusal or a cut-off answer throws, so the
    /// caller falls back to its non-AI result (`design/13` §5).
    public func completeText() throws(LLMError) -> String {
        switch stopReason {
        case .refusal(let category): throw .refused(category: category)
        case .maxTokens: throw .truncated
        default: return text
        }
    }
}

public enum LLMError: Error, Hashable, Sendable {
    /// No API key is saved.
    case missingKey
    /// The API answered with an error status that was not retried, or still failed after the retries.
    /// `type` is `error.type` and `code` is `error.details.error_code` from the body, when present.
    case http(status: Int, type: String?, message: String?, code: String? = nil)
    /// The request never got an HTTP answer (offline, DNS, timeout), after the retries.
    case transport(String)
    /// The answer wasn't the JSON we expect.
    case decoding(String)
    case refused(category: String?)
    case truncated
}

/// Claude (or any model) behind one call. `AnthropicClient` in AICore; `FakeLLM` in tests.
public protocol LLMClient: Sendable {
    func send(_ request: LLMRequest) async throws(LLMError) -> LLMResponse
}
