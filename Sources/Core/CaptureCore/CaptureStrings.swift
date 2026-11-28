/// Every user-visible string of the Capture epic, exactly as the spec settles them (Capture §5, C15).
public enum CaptureStrings {
    // §5.4 failures, title `Capture failed`.
    public static let captureFailedTitle = "Capture failed"
    public static let encodeFailed = "Could not encode PNG."
    public static let writeFailedCopied = "Couldn't write the file. The image is on the clipboard."
    public static let writeFailed = "Couldn't write the file."
    public static let windowClosed = "The window closed before it could be captured."
    public static let displayDisconnected = "The display was disconnected."
}

extension CaptureStrings {
    // §5.5 the Screen Recording alert.
    public static let permissionTitle = "Screen Recording permission needed"
    public static let permissionText =
        "Enable Bugeye under Privacy & Security \u{2192} Screen & System Audio Recording, then relaunch the app."
    public static let openSystemSettings = "Open System Settings"
    public static let relaunch = "Relaunch"
    public static let cancel = "Cancel"
    public static let screenRecordingSettingsURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

    // §5.7 the Capture pane.
    public static let paneTitle = "Capture"
    public static let afterCapture = "After capture"
    public static let copyToClipboard = "Copy to clipboard"
    public static let saveToFolder = "Save to folder"
    public static let downscale = "Downscale Retina captures to 1\u{00D7}"

    // §5.1 menu items and §5.6 Shortcuts rows.
    public static let captureArea = "Capture Area"
    public static let captureWindow = "Capture Window"
    public static let captureFullscreen = "Capture Fullscreen"
    public static let captureAllDisplays = "Capture All Displays"
}
