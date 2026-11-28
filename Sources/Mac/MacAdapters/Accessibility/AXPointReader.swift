import ApplicationServices
import BugeyeCore
import Foundation

/// The Accessibility element under a point, for the recording timeline (Recording V3). Answers point queries
/// only; `elements(inWindowOf:)` throws `unsupported` (the Wave 2 AX epic replaces this file).
///
/// Each query runs on a GCD queue, not the cooperative pool, within one deadline for the whole lookup (250 ms):
/// every Accessibility message gets the time that is left (`AXUIElementSetMessagingTimeout`), and the lookup
/// stops once it is spent, so a hung app blocks one GCD thread for at most the deadline (PR #4 review I1,
/// PR #17 review I2). Setting the timeout on the system-wide element affects every AX call of the process; the
/// Wave 2 AX epic sets its own before its calls.
///
/// Reads AXRole, AXSubrole, AXPosition and AXSize in one message, then AXTitle (else AXDescription) only for an
/// element that is neither secure nor text entry: a text field's title can be its typed value in some apps
/// (CLAUDE.md "Never store typed text"). Never AXValue, AXSelectedText or AXPlaceholderValue.
public struct AXPointReader: AXReader {
    public enum Failure: Error, Hashable { case unsupported }

    /// Roles whose value is typed text. (Search fields are text fields with the AXSearchField subrole.)
    public static let textEntryRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]

    private let deadline: Double
    private let isTrusted: @Sendable () -> Bool

    /// `deadline` in seconds, for the whole lookup (0.25, the timeline's).
    public init(deadline: Double = 0.25, isTrusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() }) {
        self.deadline = deadline
        self.isTrusted = isTrusted
    }

    /// `point` is in Quartz global points. Nil when nothing is there, Accessibility isn't granted, or the
    /// deadline passed.
    public func element(at point: Point2D) async throws -> AXElementInfo? {
        guard isTrusted() else { return nil }
        let deadline = deadline
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.read(at: point, deadline: deadline))
            }
        }
    }

    public func elements(inWindowOf processID: Int32) async throws -> [AXElementInfo] {
        throw Failure.unsupported
    }

    /// Whether the role or subrole is one whose title must not be read.
    public static func isTextEntry(role: String, subrole: String?) -> Bool {
        textEntryRoles.contains(role) || subrole == "AXSearchField"
    }

    /// Builds the info from the attributes read; the rules live here so they can be tested without an app.
    /// Secure and text-entry elements keep no title.
    public static func info(
        role: String, subrole: String?, title: String?, description: String?, frame: Rect2D
    ) -> AXElementInfo {
        let isSecure = subrole == AXElementInfo.secureSubrole
        let isTextEntry = isTextEntry(role: role, subrole: subrole) || isSecure
        let name = (title?.isEmpty == false ? title : nil) ?? (description?.isEmpty == false ? description : nil)
        return AXElementInfo(
            role: role, subrole: subrole, title: isTextEntry ? nil : name, text: nil, frame: frame,
            isTextEntry: isTextEntry, isSecure: isSecure)
    }

    private static func read(at point: Point2D, deadline: Double) -> AXElementInfo? {
        let end = Date().addingTimeInterval(deadline)
        /// The time left for the next message; nil once spent.
        func budget() -> Float? {
            let left = end.timeIntervalSinceNow
            return left > 0.001 ? Float(left) : nil
        }
        let system = AXUIElementCreateSystemWide()
        guard let first = budget() else { return nil }
        AXUIElementSetMessagingTimeout(system, first)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &found) == .success,
            let element = found, let second = budget()
        else { return nil }
        AXUIElementSetMessagingTimeout(element, second)
        let names = ["AXRole", "AXSubrole", "AXPosition", "AXSize"] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names, [], &values) == .success,
            let list = values as? [AnyObject], list.count == 4, let role = list[0] as? String
        else { return nil }
        let subrole = list[1] as? String
        let frame = Self.frame(position: list[2], size: list[3]) ?? .zero
        let isSecure = subrole == AXElementInfo.secureSubrole
        guard !isSecure, !isTextEntry(role: role, subrole: subrole), let third = budget() else {
            return info(role: role, subrole: subrole, title: nil, description: nil, frame: frame)
        }
        AXUIElementSetMessagingTimeout(element, third)
        var titles: CFArray?
        var title: String?
        var description: String?
        if AXUIElementCopyMultipleAttributeValues(
            element, ["AXTitle", "AXDescription"] as CFArray, [], &titles) == .success,
            let pair = titles as? [AnyObject], pair.count == 2
        {
            title = pair[0] as? String
            description = pair[1] as? String
        }
        return info(role: role, subrole: subrole, title: title, description: description, frame: frame)
    }

    private static func frame(position: AnyObject, size: AnyObject) -> Rect2D? {
        let positionRef = position as CFTypeRef
        let sizeRef = size as CFTypeRef
        guard CFGetTypeID(positionRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
            return nil
        }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        // swift-format-ignore: NeverForceUnwrap
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &origin),
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &extent)
        else { return nil }
        return Rect2D(x: origin.x, y: origin.y, width: extent.width, height: extent.height)
    }
}
