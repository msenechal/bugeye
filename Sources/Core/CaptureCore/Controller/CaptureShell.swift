import BugeyeCore
import Foundation

/// What the controller needs from the macOS shell: overlay windows, focus, sound, the alert and logging. The shell
/// renders `CaptureController.overlay(for:)` and sends view events back with `CaptureController.send(_:)`.
@MainActor
public protocol CaptureShell: AnyObject {
    /// `NSEvent.mouseLocation`.
    func pointerLocation() -> CocoaPoint
    /// One borderless overlay window per frame, tagged with `session` (Capture §5.2).
    func showOverlays(_ session: SessionID, frames: [FrozenDisplay], mode: OverlayMode)
    /// Closes (not hides) the session's overlays.
    func closeOverlays(_ session: SessionID)
    /// Closes every overlay window whose session isn't `keeping`, logging an error for each one it closes.
    func sweepLeftovers(keeping: SessionID?)
    func makeKey(_ session: SessionID, display: DisplayID)
    /// `damage` in display-local points; nil for the whole overlay.
    func redraw(_ session: SessionID, display: DisplayID, damage: DisplayRect?)
    /// Remembers the frontmost app, then activates Bugeye.
    func activateBugeye()
    /// Gives focus back to the app `activateBugeye` remembered.
    func reactivatePreviousApp()
    func beep()
    /// `AppContext.screenRecordingAlert.show()`.
    func showPermissionAlert()
    /// The window numbers of the session's overlays, for the begin/finish log lines.
    func overlayWindowNumbers(_ session: SessionID) -> [Int]
    /// `os.Logger`, subsystem `dev.msenechal.bugeye`, `category`.
    func log(_ category: LogCategory, _ message: String)
}

/// Everything the controller works with besides the shell, the bus, the activity gate and the registrar.
public struct CaptureEnvironment: Sendable {
    public var screenSource: any ScreenSource
    public var windowList: any WindowListReader
    public var pipeline: any ImagePipeline
    public var permission: any ScreenCapturePermission
    public var settings: any SettingsStore
    public var writer: CaptureFileWriter
    public var clipboard: any ClipboardWriter
    public var notifier: any Notifier
    public var metadata: any FileMetadataStore
    public var home: String
    public var ownPID: Int32
    /// The save folder and how the General pane shows it, read at each delivery.
    public var saveFolder: @MainActor @Sendable () -> (url: URL, displayed: String)
    public var now: @Sendable () -> Date
    public var timeZone: TimeZone

    public init(
        screenSource: any ScreenSource, windowList: any WindowListReader, pipeline: any ImagePipeline,
        permission: any ScreenCapturePermission, settings: any SettingsStore, writer: CaptureFileWriter,
        clipboard: any ClipboardWriter, notifier: any Notifier, metadata: any FileMetadataStore, home: String,
        ownPID: Int32, saveFolder: @escaping @MainActor @Sendable () -> (url: URL, displayed: String),
        now: @escaping @Sendable () -> Date = { Date() }, timeZone: TimeZone = .current
    ) {
        self.screenSource = screenSource
        self.windowList = windowList
        self.pipeline = pipeline
        self.permission = permission
        self.settings = settings
        self.writer = writer
        self.clipboard = clipboard
        self.notifier = notifier
        self.metadata = metadata
        self.home = home
        self.ownPID = ownPID
        self.saveFolder = saveFolder
        self.now = now
        self.timeZone = timeZone
    }
}
