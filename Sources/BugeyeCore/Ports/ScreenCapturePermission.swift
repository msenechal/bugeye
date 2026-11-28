/// Screen Recording permission (CoreGraphics on macOS). Capture, Recording.
public protocol ScreenCapturePermission: Sendable {
    /// CGPreflightScreenCaptureAccess: never prompts.
    func preflight() -> Bool
    /// CGRequestScreenCaptureAccess: adds Bugeye to System Settings' list, prompting at most once.
    func requestAccess()
}
