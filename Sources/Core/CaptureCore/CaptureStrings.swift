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
