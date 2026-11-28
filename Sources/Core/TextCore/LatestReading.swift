import BugeyeCore

/// Newest-wins reads of in-memory images (OCR §5.5), for the editor's flattened render in Wave 2: each call cancels
/// the previous call's read, and a call returns nil if a newer one started before it finished. It never caches.
public actor LatestReading {
    private let reader: TextMapReader
    private var generation: UInt64 = 0
    private var current: Task<TextMap, any Error>?

    public init(reader: TextMapReader) {
        self.reader = reader
    }

    /// The image's map, or nil when the read failed or a newer call superseded it.
    public func read(_ buffer: PixelBuffer, pixelsPerPoint: Double) async -> TextMap? {
        generation += 1
        let mine = generation
        current?.cancel()
        let reader = self.reader
        let task = Task { try await Self.run(reader, buffer, pixelsPerPoint) }
        current = task
        let result = try? await task.value
        guard generation == mine else { return nil }
        current = nil
        return result
    }

    @concurrent private nonisolated static func run(
        _ reader: TextMapReader, _ buffer: PixelBuffer, _ pixelsPerPoint: Double
    ) async throws -> TextMap {
        try await reader.read(.buffer(buffer), pixelsPerPoint: pixelsPerPoint)
    }
}
