import Foundation

// Every system service the core needs, as a protocol. Each has a fake in BugeyeTestSupport and, from its
// wave on, a macOS adapter in MacAdapters. A wave may change a port's shape, with a ledgered ruling.

// MARK: Screen

/// A display's identity as the system reports it (`CGDirectDisplayID` on macOS).
public struct DisplayID: Hashable, Codable, Sendable {
    public var rawValue: UInt32
    public init(_ rawValue: UInt32) { self.rawValue = rawValue }
}

public struct DisplayInfo: Hashable, Codable, Sendable {
    public var id: DisplayID
    /// The display's frame in global points.
    public var frame: Rect2D
    /// Pixels per point: 2 on a Retina display, 1 on the user's external 1080p monitor.
    public var scale: Double

    public init(id: DisplayID, frame: Rect2D, scale: Double) {
        self.id = id
        self.frame = frame
        self.scale = scale
    }
}

/// Screen pixels (ScreenCaptureKit on macOS).
public protocol ScreenSource: Sendable {
    func displays() async throws -> [DisplayInfo]
    /// Captures `rect` (in the display's points; nil for the whole display) at the display's full scale.
    func capture(display: DisplayID, rect: Rect2D?) async throws -> PixelBuffer
}

// MARK: Vision

/// A line of recognised text. `bounds` is in the image's pixels, top-left origin.
public struct OCRLine: Hashable, Codable, Sendable {
    public var text: String
    public var bounds: Rect2D
    public var confidence: Double

    public init(text: String, bounds: Rect2D, confidence: Double) {
        self.text = text
        self.bounds = bounds
        self.confidence = confidence
    }
}

/// OCR (Vision on macOS).
public protocol TextReader: Sendable {
    func recognizeText(in image: PixelBuffer) async throws -> [OCRLine]
}

/// Face detection (Vision). Rects in the image's pixels.
public protocol FaceFinder: Sendable {
    func faces(in image: PixelBuffer) async throws -> [Rect2D]
}

/// Rectangle detection (Vision). Rects in the image's pixels.
public protocol RectangleFinder: Sendable {
    func rectangles(in image: PixelBuffer) async throws -> [Rect2D]
}

// MARK: Accessibility

/// One element read through Accessibility.
public struct AXElementInfo: Hashable, Sendable {
    public var role: String
    public var title: String?
    /// Static text only. Always nil for text-entry and secure roles: typed text is never read (`design/11` §6).
    /// Not Codable on purpose: decoding would bypass the rule the initializer enforces.
    public var text: String?
    /// In global points.
    public var frame: Rect2D
    public var isTextEntry: Bool

    public init(role: String, title: String?, text: String?, frame: Rect2D, isTextEntry: Bool) {
        self.role = role
        self.title = title
        self.text = isTextEntry ? nil : text
        self.frame = frame
        self.isTextEntry = isTextEntry
    }
}

/// The Accessibility tree (AXUIElement on macOS). Every call may be slow: never call it on the main actor.
public protocol AXReader: Sendable {
    func element(at point: Point2D) async throws -> AXElementInfo?
    func elements(inWindowOf processID: Int32) async throws -> [AXElementInfo]
}

// MARK: Clipboard

/// What one clipboard write holds, as representations of a single item.
public struct ClipboardPayload: Hashable, Sendable {
    public var png: Data?
    public var fileURL: URL?
    public var text: String?

    public init(png: Data? = nil, fileURL: URL? = nil, text: String? = nil) {
        self.png = png
        self.fileURL = fileURL
        self.text = text
    }
}

/// The pasteboard (NSPasteboard on macOS).
public protocol ClipboardWriter: Sendable {
    func write(_ payload: ClipboardPayload) throws
}

// MARK: File metadata

/// Extended attributes on files (`getxattr`/`setxattr` on macOS). Only `CaptureFileWriter` rewrites
/// capture files; everything else reads and sets attributes through this port.
public protocol FileMetadataStore: Sendable {
    /// The attribute names on the file. Throws if the file is missing.
    func names(at url: URL) throws -> [String]
    /// The attribute's bytes, or nil when the file has no such attribute. Throws if the file is missing.
    func value(_ name: String, at url: URL) throws -> Data?
    func setValue(_ value: Data, _ name: String, at url: URL) throws
    /// Removing an attribute the file doesn't have is not an error.
    func removeValue(_ name: String, at url: URL) throws
}

// MARK: Search

/// One capture as the index and Spotlight know it.
public struct CaptureRecord: Hashable, Codable, Sendable {
    public var id: CaptureID
    public var path: String
    public var createdAt: Date
    public var text: String

    public init(id: CaptureID, path: String, createdAt: Date, text: String) {
        self.id = id
        self.path = path
        self.createdAt = createdAt
        self.text = text
    }
}

/// The full-text capture index (SQLite, which also runs on Linux).
public protocol CaptureIndexStore: Sendable {
    func upsert(_ record: CaptureRecord) async throws
    func remove(_ id: CaptureID) async throws
    func record(_ id: CaptureID) async throws -> CaptureRecord?
    func search(_ query: String, limit: Int) async throws -> [CaptureRecord]
}

/// Spotlight donation (Core Spotlight on macOS).
public protocol SpotlightDonor: Sendable {
    func donate(_ records: [CaptureRecord]) async throws
    func remove(_ ids: [CaptureID]) async throws
}

// MARK: Speech

public struct TranscriptSegment: Hashable, Codable, Sendable {
    public var text: String
    /// Seconds from the start of the audio.
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// On-device transcription (Speech on macOS).
public protocol SpeechTranscriber: Sendable {
    func transcribe(audioFile: URL) async throws -> [TranscriptSegment]
}

// MARK: Secrets

/// The name a secret is stored under.
public struct SecretKey: Hashable, Sendable {
    public var rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }

    /// The user's Anthropic API key.
    public static let anthropicAPIKey = SecretKey("anthropic-api-key")
}

/// Secrets (the Keychain on macOS). Never UserDefaults, never a file.
public protocol SecretStore: Sendable {
    func secret(for key: SecretKey) throws -> String?
    func setSecret(_ value: String, for key: SecretKey) throws
    /// Removing a secret that isn't there is not an error.
    func removeSecret(for key: SecretKey) throws
}

// MARK: Settings

/// A stored setting value.
public enum SettingValue: Hashable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
}

/// Key-value settings (UserDefaults on macOS).
public protocol SettingsStore: Sendable {
    func value(forKey key: String) -> SettingValue?
    /// nil removes the key.
    func setValue(_ value: SettingValue?, forKey key: String)
}
