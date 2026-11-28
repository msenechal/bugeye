import BugeyeCore

/// What the text layer logs (OCR §6). The shell sends `description` to `os.Logger` (subsystem
/// `dev.msenechal.bugeye`, category `text`). Recognised text, words and file names are never in it; ids are.
public enum TextLogLine: Hashable, Sendable, CustomStringConvertible {
    public enum Priority: String, Hashable, Sendable {
        case demand, background
    }

    public enum CancelReason: String, Hashable, Sendable {
        case deleted, edited, moved
    }

    public enum DropReason: String, Hashable, Sendable {
        case gone, changed
    }

    /// A read stored its map.
    case read(
        id: CaptureID, width: Int, height: Int, pixelsPerPoint: Double, strips: Int, lines: Int, milliseconds: Int,
        priority: Priority)
    /// `timedOut`, `unreadable`, `recognitionFailed`.
    case failed(id: CaptureID, error: TextMapError)
    /// Q5, Q5b.
    case cancelled(id: CaptureID, reason: CancelReason)
    /// Q6.
    case dropped(id: CaptureID, reason: DropReason)

    public var description: String {
        switch self {
        case .read(let id, let width, let height, let ppp, let strips, let lines, let ms, let priority):
            let scale = ppp == ppp.rounded() && abs(ppp) < 1e15 ? String(Int(ppp)) : String(describing: ppp)
            return "read \(id) \(width)×\(height) @\(scale)x: \(strips) strips, \(lines) lines in \(ms) ms "
                + "(\(priority.rawValue))"
        case .failed(let id, let error):
            return "failed \(id): \(error)"
        case .cancelled(let id, let reason):
            return "cancelled \(id): \(reason.rawValue)"
        case .dropped(let id, let reason):
            return "dropped \(id): \(reason.rawValue)"
        }
    }
}
