import BugeyeCore
import Foundation
import Synchronization

/// Images and fingerprints by URL, changeable while a test runs (OCR §3.4). Thread-safe.
public final class FakeImageFileReader: ImageFileReader, Sendable {
    public typealias Hook = @Sendable (FakeImageFileReader, URL, Range<Int>?) -> Void

    private struct State {
        var files: [URL: (image: PixelBuffer, fingerprint: FileFingerprint)] = [:]
        var failures: [URL: any Error] = [:]
        var calls: [(url: URL, rows: Range<Int>?)] = []
        var beforePixels: Hook?
    }

    private let state = Mutex(State())

    public init() {}

    /// Puts (or replaces) a file.
    public func set(_ url: URL, image: PixelBuffer, fingerprint: FileFingerprint) {
        state.withLock { $0.files[url] = (image, fingerprint) }
    }

    /// Removes a file: later calls throw `ImageFileError.missing`.
    public func remove(_ url: URL) {
        state.withLock { $0.files[url] = nil }
    }

    /// Makes every later call for `url` throw `error` (nil clears it).
    public func fail(_ url: URL, with error: (any Error)?) {
        state.withLock { $0.failures[url] = error }
    }

    /// Runs at the start of every `pixels` call, after it is recorded and before the pixels are taken.
    public var beforePixels: Hook? {
        get { state.withLock { $0.beforePixels } }
        set { state.withLock { $0.beforePixels = newValue } }
    }

    /// Every `pixels` call, in order.
    public var calls: [(url: URL, rows: Range<Int>?)] { state.withLock { $0.calls } }

    public func info(of url: URL) async throws -> ImageFileInfo {
        let file = try lookup(url)
        return ImageFileInfo(width: file.image.width, height: file.image.height, fingerprint: file.fingerprint)
    }

    public func pixels(of url: URL, rows: Range<Int>?) async throws -> PixelBuffer {
        let hook = state.withLock { state in
            state.calls.append((url, rows))
            return state.beforePixels
        }
        hook?(self, url, rows)
        let image = try lookup(url).image
        guard let rows else { return image }
        let clamped = rows.clamped(to: 0..<image.height)
        guard !clamped.isEmpty else { throw ImageFileError.unreadable(url) }
        let start = clamped.lowerBound * image.bytesPerRow
        let end = clamped.upperBound * image.bytesPerRow
        return try PixelBuffer(
            width: image.width, height: clamped.count, bytesPerRow: image.bytesPerRow,
            bytes: Array(image.bytes[start..<end]))
    }

    private func lookup(_ url: URL) throws -> (image: PixelBuffer, fingerprint: FileFingerprint) {
        let (file, failure) = state.withLock { ($0.files[url], $0.failures[url]) }
        if let failure { throw failure }
        guard let file else { throw ImageFileError.missing(url) }
        return file
    }
}
