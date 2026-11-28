import Foundation

// OCR-owned (OCR §3.4, T11, contracts K9): the one way a portable core decodes an image file into pixels.

/// What identifies a file's content without reading it. Every rewrite through CaptureFileWriter changes it.
public struct FileFingerprint: Hashable, Codable, Sendable {
    public var size: Int64
    /// Content-modification date, nanosecond precision.
    public var modified: Date

    public init(size: Int64, modified: Date) {
        self.size = size
        self.modified = modified
    }
}

public struct ImageFileInfo: Hashable, Sendable {
    public var width: Int
    public var height: Int
    public var fingerprint: FileFingerprint

    public init(width: Int, height: Int, fingerprint: FileFingerprint) {
        self.width = width
        self.height = height
        self.fingerprint = fingerprint
    }
}

public enum ImageFileError: Error, Hashable, Sendable {
    case missing(URL)
    case unreadable(URL)
}

/// Decodes image files (ImageIO on macOS). Slow: never call it on the main actor.
public protocol ImageFileReader: Sendable {
    /// Size and fingerprint of the first image in the file, without decoding pixels.
    func info(of url: URL) async throws -> ImageFileInfo
    /// Rows `rows` of the first image (all rows when nil), as RGBA8 in sRGB, premultiplied, top row first.
    func pixels(of url: URL, rows: Range<Int>?) async throws -> PixelBuffer
}
