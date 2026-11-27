import AICore
import Foundation
import Synchronization
import Testing

/// Loads a recorded fixture from `Fixtures/`.
func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

/// Any JSON value, compared structurally, so key order and whitespace don't matter.
enum JSONValue: Equatable, Decodable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

/// Plays back scripted HTTP answers in order and records every request.
final class RecordedTransport: HTTPTransport {
    enum Answer {
        case response(TransportResponse)
        case offline
    }

    private let state: Mutex<(answers: [Answer], requests: [TransportRequest])>

    init(_ answers: [Answer]) {
        state = Mutex((answers, []))
    }

    var requests: [TransportRequest] { state.withLock { $0.requests } }

    func send(_ request: TransportRequest) async throws -> TransportResponse {
        let answer: Answer? = state.withLock {
            $0.requests.append(request)
            return $0.answers.isEmpty ? nil : $0.answers.removeFirst()
        }
        switch answer {
        case .response(let response): return response
        case .offline, nil: throw URLError(.notConnectedToInternet)
        }
    }
}

extension RecordedTransport.Answer {
    /// An HTTP answer whose body is a recorded fixture.
    static func json(_ status: Int, _ fixtureName: String, headers: [String: String] = [:]) throws -> Self {
        .response(TransportResponse(status: status, headers: headers, body: try fixture(fixtureName)))
    }
}

/// Records the delays the client asks for instead of sleeping.
final class SleepRecorder: Sendable {
    private let delays = Mutex<[Duration]>([])
    var recorded: [Duration] { delays.withLock { $0 } }
    var sleep: @Sendable (Duration) async throws -> Void {
        { [self] duration in record(duration) }
    }

    private func record(_ duration: Duration) {
        delays.withLock { $0.append(duration) }
    }
}
