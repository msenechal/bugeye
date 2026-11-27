import BugeyeCore
import Foundation
import Synchronization

/// The error fakes throw when a test asks them to fail.
public struct FakeFailure: Error, Equatable {
    public let message: String
    public init(_ message: String = "fake failure") { self.message = message }
}

/// Displays and images given by the test.
public final class FakeScreenSource: ScreenSource {
    private let state: Mutex<(displays: [DisplayInfo], images: [DisplayID: PixelBuffer])>

    public init(displays: [DisplayInfo] = [], images: [DisplayID: PixelBuffer] = [:]) {
        state = Mutex((displays, images))
    }

    public func displays() async throws -> [DisplayInfo] {
        state.withLock { $0.displays }
    }

    public func capture(display: DisplayID, rect: Rect2D?) async throws -> PixelBuffer {
        guard let image = state.withLock({ $0.images[display] }) else { throw FakeFailure("no image for display") }
        return image
    }
}

/// Returns the lines the test gives, for any image.
public struct FakeTextReader: TextReader {
    public var lines: [OCRLine]
    public init(lines: [OCRLine] = []) { self.lines = lines }
    public func recognizeText(in image: PixelBuffer) async throws -> [OCRLine] { lines }
}

public struct FakeFaceFinder: FaceFinder {
    public var faces: [Rect2D]
    public init(faces: [Rect2D] = []) { self.faces = faces }
    public func faces(in image: PixelBuffer) async throws -> [Rect2D] { faces }
}

public struct FakeRectangleFinder: RectangleFinder {
    public var rectangles: [Rect2D]
    public init(rectangles: [Rect2D] = []) { self.rectangles = rectangles }
    public func rectangles(in image: PixelBuffer) async throws -> [Rect2D] { rectangles }
}

/// An Accessibility tree given by the test: the element at a point is the last one containing it.
public struct FakeAXReader: AXReader {
    public var elementsByProcess: [Int32: [AXElementInfo]]
    public init(elementsByProcess: [Int32: [AXElementInfo]] = [:]) { self.elementsByProcess = elementsByProcess }

    public func element(at point: Point2D) async throws -> AXElementInfo? {
        elementsByProcess.values.flatMap { $0 }.last { $0.frame.contains(point) }
    }

    public func elements(inWindowOf processID: Int32) async throws -> [AXElementInfo] {
        elementsByProcess[processID] ?? []
    }
}

/// Records every payload written.
public final class FakeClipboard: ClipboardWriter {
    private let payloads = Mutex<[ClipboardPayload]>([])
    public init() {}
    public var written: [ClipboardPayload] { payloads.withLock { $0 } }
    public func write(_ payload: ClipboardPayload) throws { payloads.withLock { $0.append(payload) } }
}

/// An index in memory. Search matches records whose text contains the query, case-insensitively,
/// newest first.
public final class FakeCaptureIndexStore: CaptureIndexStore {
    private let records = Mutex<[CaptureID: CaptureRecord]>([:])
    public init() {}

    public func upsert(_ record: CaptureRecord) async throws { records.withLock { $0[record.id] = record } }
    public func remove(_ id: CaptureID) async throws { records.withLock { _ = $0.removeValue(forKey: id) } }
    public func record(_ id: CaptureID) async throws -> CaptureRecord? { records.withLock { $0[id] } }

    public func search(_ query: String, limit: Int) async throws -> [CaptureRecord] {
        let all = records.withLock { Array($0.values) }
        return Array(
            all.filter { $0.text.localizedCaseInsensitiveContains(query) }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(max(0, limit)))
    }
}

/// Records donations and removals.
public final class FakeSpotlightDonor: SpotlightDonor {
    private let state = Mutex<(donated: [CaptureRecord], removed: [CaptureID])>(([], []))
    public init() {}
    public var donated: [CaptureRecord] { state.withLock { $0.donated } }
    public var removed: [CaptureID] { state.withLock { $0.removed } }
    public func donate(_ records: [CaptureRecord]) async throws { state.withLock { $0.donated += records } }
    public func remove(_ ids: [CaptureID]) async throws { state.withLock { $0.removed += ids } }
}

public struct FakeSpeechTranscriber: SpeechTranscriber {
    public var segments: [TranscriptSegment]
    public init(segments: [TranscriptSegment] = []) { self.segments = segments }
    public func transcribe(audioFile: URL) async throws -> [TranscriptSegment] { segments }
}

/// Answers with scripted results, in order, and records every request. Running out of answers is a
/// test bug, reported as a transport error.
public final class FakeLLM: LLMClient {
    private let state: Mutex<(answers: [Result<LLMResponse, LLMError>], requests: [LLMRequest])>

    public init(_ answers: [Result<LLMResponse, LLMError>] = []) {
        state = Mutex((answers, []))
    }

    public var requests: [LLMRequest] { state.withLock { $0.requests } }

    public func enqueue(_ answer: Result<LLMResponse, LLMError>) {
        state.withLock { $0.answers.append(answer) }
    }

    public func send(_ request: LLMRequest) async throws(LLMError) -> LLMResponse {
        let answer: Result<LLMResponse, LLMError>? = state.withLock {
            $0.requests.append(request)
            return $0.answers.isEmpty ? nil : $0.answers.removeFirst()
        }
        guard let answer else { throw .transport("FakeLLM has no scripted answer") }
        return try answer.get()
    }

    /// A plain successful answer.
    public static func reply(_ text: String, model: String = "claude-opus-5-5") -> LLMResponse {
        LLMResponse(id: "msg_fake", model: model, stopReason: .endTurn, text: text, inputTokens: 1, outputTokens: 1)
    }
}
