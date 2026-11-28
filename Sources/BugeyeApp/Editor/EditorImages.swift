import BugeyeCore
import CoreGraphics
import EditorCore
import Foundation
import ImageIO
import MacAdapters
import Synchronization
import UniformTypeIdentifiers

/// ImageIO and rendering for the editor (E11): decode for display in the file's own colour space, the export
/// render through the display-list executor, PNG encoding. Everything here may run off the main actor.
enum EditorImages {
    /// The capture's colour space when it is RGB and can back a bitmap, else sRGB (§5.8).
    static func workingSpace(of image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb, space.supportsOutput { return space }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    /// Decodes the PNG at `url` as is: no colour conversion, no downscale. Nil when missing or unreadable.
    static func decode(_ url: URL) -> Result<CGImage, EditorLoadFailure> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(EditorLoadFailure(reason: "missing"))
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return .failure(EditorLoadFailure(reason: "unreadable")) }
        return .success(image)
    }

    static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    struct ExportFailed: Error, LocalizedError {
        var errorDescription: String? { "The image couldn't be rendered." }
    }

    /// The export render (§5.8): the base list of `state` with nothing active or hidden, in the capture's colour
    /// space, as a `CGImage`.
    static func render(state: EditorState, capture: CGImage, metrics: EditorMetrics, blur: BlurCache) -> CGImage? {
        let list = EditorRenderer.export(
            state: state, imageSize: Size2D(width: Double(capture.width), height: Double(capture.height)),
            metrics: metrics)
        let executor = DisplayListExecutor(
            images: { $0 == EditorRenderer.captureImageID ? capture : nil },
            blur: { _, rect, effect in blur.image(capture, rect: rect, effect: effect) })
        return executor.render(list, colorSpace: workingSpace(of: capture))
    }

    /// Render, PNG and the 480 px preview: what save, copy and the drag handle need.
    static func export(state: EditorState, capture: CGImage, metrics: EditorMetrics, blur: BlurCache) throws
        -> ExportedImage
    {
        guard let image = render(state: state, capture: capture, metrics: metrics, blur: blur),
            let png = encodePNG(image)
        else { throw ExportFailed() }
        return ExportedImage(png: png, preview: PixelBufferImages.preview(image))
    }
}

/// Blur and pixelate results by (source rect, effect), from the original capture only (E5, §7). Cleared past 64
/// entries. Thread-safe: exports read it off the main actor while the canvas reads it on it.
final class BlurCache: Sendable {
    struct Key: Hashable {
        var rect: Rect2D
        var effect: BlurEffect
    }

    static let limit = 64
    private let entries = Mutex<[Key: CGImage]>([:])
    private let inFlight = Mutex<Set<Key>>([])

    /// The cached result, or nil.
    func cached(rect: Rect2D, effect: BlurEffect) -> CGImage? {
        entries.withLock { $0[Key(rect: rect, effect: effect)] }
    }

    /// The result, computed now on the calling thread if needed. Exports call this off the main actor.
    func image(_ capture: CGImage, rect: Rect2D, effect: BlurEffect) -> CGImage? {
        if let hit = cached(rect: rect, effect: effect) { return hit }
        guard let result = Self.compute(capture, rect: rect, effect: effect) else { return nil }
        store(Key(rect: rect, effect: effect), result)
        return result
    }

    /// For the canvas on the main actor: the cached result, else nil, computing it off the main actor and calling
    /// `ready` on the main actor when it is in the cache (plan review A, Minor 8).
    func imageOrSchedule(
        _ capture: CGImage, rect: Rect2D, effect: BlurEffect, ready: @escaping @MainActor @Sendable () -> Void
    ) -> CGImage? {
        let key = Key(rect: rect, effect: effect)
        if let hit = entries.withLock({ $0[key] }) { return hit }
        let start = inFlight.withLock { $0.insert(key).inserted }
        guard start else { return nil }
        Task.detached(priority: .userInitiated) { [self] in
            if let result = Self.compute(capture, rect: rect, effect: effect) { store(key, result) }
            inFlight.withLock { _ = $0.remove(key) }
            await ready()
        }
        return nil
    }

    var count: Int { entries.withLock { $0.count } }

    private func store(_ key: Key, _ image: CGImage) {
        entries.withLock {
            if $0.count >= Self.limit { $0.removeAll() }
            $0[key] = image
        }
    }

    /// Extracts `rect` in the capture's own colour space with no conversion, runs `RegionEffects`, and wraps the
    /// result in the same space (E5).
    static func compute(_ capture: CGImage, rect: Rect2D, effect: BlurEffect) -> CGImage? {
        let space = EditorImages.workingSpace(of: capture)
        guard let source = PixelBufferImages.pixelBuffer(capture, rect: rect, colorSpace: space) else { return nil }
        let result: PixelBuffer
        switch effect {
        case .pixelate(let cellSize): result = RegionEffects.pixelate(source, cellSize: cellSize)
        case .gaussian(let radius): result = RegionEffects.gaussianBlur(source, radius: radius)
        }
        return PixelBufferImages.cgImage(result, colorSpace: space)
    }
}
