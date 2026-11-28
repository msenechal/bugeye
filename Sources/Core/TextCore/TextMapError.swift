import BugeyeCore
import Foundation

/// Why a read produced no map (OCR §5.3, §5.4). There are no partial maps.
public enum TextMapError: Error, Hashable, Sendable, CustomStringConvertible {
    /// A strip took longer than the strip timeout (T9); `strip` counts from 0.
    case timedOut(strip: Int)
    /// The image file couldn't be found or decoded.
    case unreadable(URL)
    /// The recogniser failed; the reader error's description.
    case recognitionFailed(String)
    /// The capture was deleted (or never known) before its read finished.
    case captureGone(CaptureID)
    /// The file kept changing under the read (Q6).
    case changedWhileReading(CaptureID)

    /// For logs (OCR §6, plan P9): never a URL, a file name or recognised text.
    public var description: String {
        switch self {
        case .timedOut(let strip): "timed out on strip \(strip)"
        case .unreadable: "unreadable"
        case .recognitionFailed(let message): "recognition failed: \(message)"
        case .captureGone: "capture gone"
        case .changedWhileReading: "changed while reading"
        }
    }
}
