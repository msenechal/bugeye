import Foundation

/// The stable identity of a capture, used by provenance, search and collections.
/// Stored on the file in the `dev.msenechal.bugeye.id` extended attribute as a lowercase UUID string.
public struct CaptureID: Hashable, Sendable, CustomStringConvertible, Codable {
    public let uuid: UUID

    public init(_ uuid: UUID = UUID()) {
        self.uuid = uuid
    }

    /// Parses a UUID string in either case; nil for anything else.
    public init?(string: String) {
        guard let uuid = UUID(uuidString: string) else { return nil }
        self.uuid = uuid
    }

    /// The canonical form: lowercase, hyphenated.
    public var description: String { uuid.uuidString.lowercased() }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let id = CaptureID(string: string) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Not a capture ID: \(string)")
        }
        self = id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
