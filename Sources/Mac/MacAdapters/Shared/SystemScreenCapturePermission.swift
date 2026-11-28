import BugeyeCore
import CoreGraphics

/// Screen Recording permission through CoreGraphics (contracts §4.4).
public struct SystemScreenCapturePermission: ScreenCapturePermission {
    public init() {}

    /// Never prompts.
    public func preflight() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Adds Bugeye to System Settings' list, prompting at most once.
    public func requestAccess() {
        _ = CGRequestScreenCaptureAccess()
    }
}
