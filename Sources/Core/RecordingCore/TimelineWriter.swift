import BugeyeCore
import Foundation

/// The timeline's size limits (spec §7.3, plan P7).
public struct TimelineLimits: Hashable, Sendable {
    /// From here `move` lines stop (`trunc` `cursor`).
    public var cursorBytes: Int
    /// From here (less `reserve`) every event line stops (`trunc` `size`).
    public var totalBytes: Int
    /// Kept free so the `trunc` and `end` lines always fit.
    public var reserve: Int

    public init(cursorBytes: Int = 48 << 20, totalBytes: Int = 64 << 20, reserve: Int = 4 << 10) {
        self.cursorBytes = cursorBytes
        self.totalBytes = totalBytes
        self.reserve = reserve
    }
}

/// Appends a timeline's lines to its file, enforcing the size limits. Not thread-safe: `TimelineRecorder`
/// owns it. Lines are buffered until `flush`; `finish` writes `end`, flushes and fsyncs.
final class TimelineWriter {
    let url: URL
    private let limits: TimelineLimits
    private var handle: FileHandle?
    private var buffer = Data()
    /// Bytes in the file plus the buffer.
    private(set) var bytes = 0
    private(set) var events = 0
    private(set) var truncations: [TimelineTruncation] = []
    private(set) var error: String?

    /// Creates the file (replacing nothing: the take's name is unique) and buffers the header.
    init(url: URL, header: TimelineHeader, limits: TimelineLimits) throws {
        self.url = url
        self.limits = limits
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        handle = try FileHandle(forWritingTo: url)
        put(TimelineLineEncoder.header(header))
    }

    var isOpen: Bool { handle != nil }

    /// Appends an event line, or drops it once a limit is reached (writing the `trunc` line once).
    func append(_ line: TimelineLine) {
        guard isOpen, !truncations.contains(.size) else { return }
        let text = TimelineLineEncoder.line(line)
        let size = text.utf8.count + 1
        if case .move = line.event {
            if truncations.contains(.cursor) { return }
            if bytes + size > limits.cursorBytes {
                truncate(.cursor, t: line.t)
                return
            }
        }
        guard bytes + size <= limits.totalBytes - limits.reserve else {
            truncate(.size, t: line.t)
            return
        }
        put(text)
        events += 1
    }

    private func truncate(_ reason: TimelineTruncation, t: Int) {
        let text = TimelineLineEncoder.line(TimelineLine(t: t, event: .trunc(reason)))
        if reason == .cursor, bytes + text.utf8.count + 1 > limits.totalBytes - limits.reserve {
            truncate(.size, t: t)
            return
        }
        truncations.append(reason)
        put(text)
        events += 1
    }

    private func put(_ text: String) {
        let data = Data((text + "\n").utf8)
        buffer.append(data)
        bytes += data.count
    }

    /// Appends the buffer to the file. A write error closes the writer and is kept in `error`.
    func flush() {
        guard let handle, !buffer.isEmpty else { return }
        do {
            try handle.write(contentsOf: buffer)
            buffer.removeAll(keepingCapacity: true)
        } catch {
            fail(error)
        }
    }

    /// Writes `end` (always fits: the reserve), flushes, fsyncs and closes.
    func finish(t: Int) {
        guard isOpen else { return }
        put(TimelineLineEncoder.line(TimelineLine(t: t, event: .end(events: events))))
        flush()
        guard let handle else { return }
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            fail(error)
        }
        self.handle = nil
    }

    /// Closes and deletes the file.
    func discard() {
        try? handle?.close()
        handle = nil
        buffer.removeAll()
        try? FileManager.default.removeItem(at: url)
    }

    private func fail(_ error: any Error) {
        self.error = self.error ?? String(describing: error)
        try? handle?.close()
        handle = nil
    }
}
