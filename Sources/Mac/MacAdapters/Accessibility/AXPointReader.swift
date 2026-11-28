import ApplicationServices
import BugeyeCore
import Foundation

/// The Accessibility element under a point, for the recording timeline (Recording V3). Answers point queries
/// only; `elements(inWindowOf:)` throws `unsupported` (the Wave 2 AX epic replaces this file).
///
/// Each query runs on a GCD queue, not the cooperative pool, with `AXUIElementSetMessagingTimeout`, so a hung
/// app can block one GCD thread for at most the timeout and never starves Swift concurrency (PR #4 review I1).
/// Reads AXRole, AXSubrole, AXTitle (else AXDescription), AXPosition and AXSize; never AXValue,
/// AXSelectedText or AXPlaceholderValue, and no title at all for a secure field.
public struct AXPointReader: AXReader {
    public enum Failure: Error, Hashable { case unsupported }

    /// Roles whose value is typed text.
    public static let textEntryRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    private let timeout: Float
    private let isTrusted: @Sendable () -> Bool

    /// `timeout` in seconds, per Accessibility message (0.25, the timeline's deadline).
    public init(timeout: Float = 0.25, isTrusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() }) {
        self.timeout = timeout
        self.isTrusted = isTrusted
    }

    /// `point` is in Quartz global points. Nil when nothing is there or Accessibility isn't granted.
    public func element(at point: Point2D) async throws -> AXElementInfo? {
        guard isTrusted() else { return nil }
        let timeout = timeout
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.read(at: point, timeout: timeout))
            }
        }
    }

    public func elements(inWindowOf processID: Int32) async throws -> [AXElementInfo] {
        throw Failure.unsupported
    }

    /// Builds the info from the attributes read; the rules live here so they can be tested without an app.
    public static func info(
        role: String, subrole: String?, title: String?, description: String?, frame: Rect2D
    ) -> AXElementInfo {
        let isSecure = subrole == AXElementInfo.secureSubrole
        let name = (title?.isEmpty == false ? title : nil) ?? (description?.isEmpty == false ? description : nil)
        return AXElementInfo(
            role: role, subrole: subrole, title: isSecure ? nil : name, text: nil, frame: frame,
            isTextEntry: textEntryRoles.contains(role) || isSecure, isSecure: isSecure)
    }

    private static func read(at point: Point2D, timeout: Float) -> AXElementInfo? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &found) == .success,
            let element = found
        else { return nil }
        AXUIElementSetMessagingTimeout(element, timeout)
        guard let role = string(element, "AXRole") else { return nil }
        let subrole = string(element, "AXSubrole")
        let isSecure = subrole == AXElementInfo.secureSubrole
        return info(
            role: role, subrole: subrole, title: isSecure ? nil : string(element, "AXTitle"),
            description: isSecure ? nil : string(element, "AXDescription"), frame: frame(element) ?? .zero)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func frame(_ element: AXUIElement) -> Rect2D? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXPosition" as CFString, &positionRef) == .success,
            AXUIElementCopyAttributeValue(element, "AXSize" as CFString, &sizeRef) == .success,
            let positionRef, let sizeRef, CFGetTypeID(positionRef) == AXValueGetTypeID(),
            CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        // swift-format-ignore: NeverForceUnwrap
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &position),
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }
        return Rect2D(x: position.x, y: position.y, width: size.width, height: size.height)
    }
}
