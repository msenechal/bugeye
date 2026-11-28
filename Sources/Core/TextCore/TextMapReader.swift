import BugeyeCore
import Foundation
import Synchronization

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
                // A file rewritten since `info` would map boxes with a stale size (claude-review on #9).
                guard image.width == width, image.height == strip.count else { throw TextMapError.unreadable(url) }
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
    /// kept line from the strips above that it overlaps with positive area **and** is on the same line with (§4.2's
    /// `sameLine`); every other line is kept.
    static func merge(_ stripLines: [[TextLine]], strips: [Range<Int>], overlap: Int) -> [TextLine] {
        guard var kept = stripLines.first else { return [] }
        for index in stripLines.indices.dropFirst() {
            let start = Double(strips[index].lowerBound)
            let bandEnd = start + Double(overlap)
            var added: [TextLine] = []
            for line in stripLines[index] {
                if line.box.minY >= start, line.box.maxY <= bandEnd { continue }
                if line.box.minY < bandEnd {
                    // Only the same line, cut by the strip edge: a neighbour that merely touches it stays (ledger
                    // ruling, slice 2 review I2).
                    kept.removeAll {
                        $0.box.intersection(line.box) != nil && TextMapBuilder.sameLine($0.box, line.box)
                    }
                }
                added.append(line)
            }
            kept += added
        }
        return kept
    }

    /// One `TextReader` call under the strip timeout. A reader error becomes `recognitionFailed`; the timeout
    /// becomes `timedOut(strip:)`; cancellation stays `CancellationError`. The reader runs in its own task, so a
    /// recogniser that ignores cancellation can't hold the read past the timeout: it is cancelled and left to finish
    /// on its own (slice 2 review I1).
    private func recognize(_ image: PixelBuffer, strip: Int) async throws -> [OCRLine] {
        let reader = self.reader
        let sleep = self.sleep
        let timeout = stripTimeout
        let outcome = ResumeOnce<[OCRLine]>()
        let work = Task { try await reader.recognizeText(in: image) }
        let timer = Task { try await sleep(timeout) }
        Task {
            let result = await work.result
            timer.cancel()
            outcome.resume(
                result.mapError { error in
                    error is CancellationError ? error : TextMapError.recognitionFailed(String(describing: error))
                })
        }
        Task {
            guard (try? await timer.value) != nil else { return }
            work.cancel()
            outcome.resume(.failure(TextMapError.timedOut(strip: strip)))
        }
        do {
            return try await withTaskCancellationHandler {
                try await outcome.value()
            } onCancel: {
                work.cancel()
                timer.cancel()
                outcome.resume(.failure(CancellationError()))
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw error
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

/// A result delivered once, to a waiter that may arrive before or after it. Thread-safe.
final class ResumeOnce<T: Sendable>: Sendable {
    private struct State {
        var result: Result<T, any Error>?
        var waiter: CheckedContinuation<T, any Error>?
    }

    private let state = Mutex(State())

    /// The first result wins; later ones are ignored.
    func resume(_ result: Result<T, any Error>) {
        let waiter: CheckedContinuation<T, any Error>? = state.withLock { state in
            guard state.result == nil else { return nil }
            state.result = result
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume(with: result)
    }

    func value() async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let ready: Result<T, any Error>? = state.withLock { state in
                if let result = state.result { return result }
                state.waiter = continuation
                return nil
            }
            if let ready { continuation.resume(with: ready) }
        }
    }
}
