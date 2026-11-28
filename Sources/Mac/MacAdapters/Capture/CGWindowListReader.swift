import BugeyeCore
import CoreGraphics
import Foundation

/// `WindowListReader` on `CGWindowListCopyWindowInfo` (design/02 §2.9). Titles are never read.
public struct CGWindowListReader: WindowListReader {
    public init() {}

    public func windows() async -> [WindowInfo] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        return Self.parse(list as? [[String: Any]] ?? [])
    }

    /// Keeps the window server's front-to-back order; entries without a number, an owner or bounds are skipped.
    public static func parse(_ list: [[String: Any]]) -> [WindowInfo] {
        list.compactMap { entry in
            guard let number = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else { return nil }
            let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            return WindowInfo(
                id: WindowID(number), ownerPID: pid,
                bounds: Rect2D(x: bounds.origin.x, y: bounds.origin.y, width: bounds.width, height: bounds.height),
                layer: layer, alpha: alpha)
        }
    }
}
