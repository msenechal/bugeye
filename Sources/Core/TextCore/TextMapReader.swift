import BugeyeCore
import Foundation

/// Reads one image into a `TextMap`, strip by strip, with the 2× enlargement and a timeout per strip (OCR §5.3).
public struct TextMapReader: Sendable {
    public enum Source: Sendable {
        case buffer(PixelBuffer)
        /// Decoded strip by strip through `ImageFileReader.pixels(of:rows:)`.
        case file(URL)
    }

    /// T9: a strip that takes longer fails the read with `timedOut`.
    public static let defaultStripTimeout: Duration = .seconds(10)

    private let reader: any TextReader
    private let files: any ImageFileReader
    private let stripTimeout: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        reader: any TextReader, files: any ImageFileReader, clock: any Clock<Duration> = ContinuousClock(),
        stripTimeout: Duration = TextMapReader.defaultStripTimeout
    ) {
        self.reader = reader
        self.files = files
        self.stripTimeout = stripTimeout
        sleep = { try await clock.sleep(for: $0) }
    }

    /// The image's map in its own pixels. `pixelsPerPoint` is the capture's real scale. `beforeStrip` runs before
    /// each strip, between two cancellation checks; its error stops the read (plan P5). Throws `TextMapError` or
    /// `CancellationError`, never a partial map.
    public func read(
        _ source: Source, pixelsPerPoint: Double, beforeStrip: @Sendable () async throws -> Void = {}
    ) async throws -> TextMap {
        let width: Int
        let height: Int
        switch source {
        case .buffer(let buffer):
            (width, height) = (buffer.width, buffer.height)
        case .file(let url):
            let info = try await decoding(url) { try await files.info(of: url) }
            (width, height) = (info.width, info.height)
        }
        let plan = StripPlan(pixelsPerPoint: pixelsPerPoint)
        let strips = plan.strips(height: height)
        var stripLines: [[TextLine]] = []
        for (index, strip) in strips.enumerated() {
            try Task.checkCancellation()
            try await beforeStrip()
            try Task.checkCancellation()
            var image: PixelBuffer
            switch source {
            case .buffer(let buffer):
                image = strips.count == 1 ? buffer : try PixelResample.rows(buffer, strip)
            case .file(let url):
                image = try await decoding(url) { try await files.pixels(of: url, rows: strip) }
            }
            if plan.scale == 2 { image = PixelResample.enlarged2x(image) }
            let lines = try await recognize(image, strip: index)
            let stripMap = TextMapBuilder.build(lines, width: image.width, height: image.height)
            let mapped = stripMap.mapped(
                scale: 1 / Double(plan.scale), offset: Point2D(x: 0, y: Double(strip.lowerBound)), width: width,
                height: height)
            stripLines.append(mapped.lines)
        }
        let merged = Self.merge(stripLines, strips: strips, overlap: plan.overlap)
        return TextMap(width: width, height: height, lines: TextMapBuilder.ordered(merged))
    }

    /// The strip merge (OCR §5.3.1). For each strip after the first, with top band `[start, start + overlap)`: a
    /// line entirely inside the band is dropped; a line starting in the band and ending below it replaces every
    /// kept line from the strips above that it overlaps with positive area; every other line is kept.
    static func merge(_ stripLines: [[TextLine]], strips: [Range<Int>], overlap: Int) -> [TextLine] {
        guard var kept = stripLines.first else { return [] }
        for index in stripLines.indices.dropFirst() {
            let start = Double(strips[index].lowerBound)
            let bandEnd = start + Double(overlap)
            var added: [TextLine] = []
            for line in stripLines[index] {
                if line.box.minY >= start, line.box.maxY <= bandEnd { continue }
                if line.box.minY < bandEnd {
                    kept.removeAll { $0.box.intersection(line.box) != nil }
                }
                added.append(line)
            }
            kept += added
        }
        return kept
    }

    /// One `TextReader` call under the strip timeout. A reader error becomes `recognitionFailed`; the timeout
    /// becomes `timedOut(strip:)`; cancellation stays `CancellationError`.
    private func recognize(_ image: PixelBuffer, strip: Int) async throws -> [OCRLine] {
        let reader = self.reader
        let sleep = self.sleep
        let timeout = stripTimeout
        do {
            return try await withThrowingTaskGroup(of: [OCRLine]?.self) { group in
                group.addTask { try await reader.recognizeText(in: image) }
                group.addTask {
                    try await sleep(timeout)
                    return nil
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw CancellationError() }
                guard let lines = first else { throw TextMapError.timedOut(strip: strip) }
                return lines
            }
        } catch let error as TextMapError {
            throw error
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw TextMapError.recognitionFailed(String(describing: error))
        }
    }

    /// An `ImageFileReader` call: any error but cancellation becomes `unreadable(url)` (plan P6).
    private func decoding<T>(_ url: URL, _ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw TextMapError.unreadable(url)
        }
    }
}
