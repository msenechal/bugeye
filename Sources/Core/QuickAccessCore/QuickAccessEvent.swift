import BugeyeCore
import BugeyeFeatures
import Foundation

/// A window the controller can make key again: an `NSWindow.windowNumber`.
public struct WindowToken: Hashable, Sendable {
    public var rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
}

/// Where Save moves a capture: `AppSettings.saveFolder` read fresh, and how General shows it (plan P5).
public struct QuickAccessSaveTarget: Hashable, Sendable {
    public var folder: URL
    public var displayPath: String
    public init(folder: URL, displayPath: String) {
        self.folder = folder
        self.displayPath = displayPath
    }
}

/// Why a thumbnail went away; logged as `dismiss <id> <reason>` (spec §7).
public enum DismissReason: String, Hashable, Sendable {
    case close, escape, expired, evicted, deleted
}

/// Everything the controller feeds the model (spec §6). The clock is `handle(_:at:)`'s `now`.
public enum QuickAccessEvent: Hashable, Sendable {
    /// `anchor` (the visible frame of the display under the pointer) and fresh `settings` come with `created` only.
    case bus(CaptureEvent, anchor: Rect2D?, settings: QuickAccessSettings?)
    /// Every 0.5 s while the ticker runs.
    case tick
    /// `bugeyeKeyWindow`: Bugeye's key window when Bugeye is active and that window isn't a thumbnail.
    case hoverBegan(CaptureID, bugeyeKeyWindow: WindowToken?)
    case hoverEnded(CaptureID, bugeyeIsActive: Bool)
    /// Bugeye became active or inactive (plan P8).
    case appActiveChanged(Bool)
    case imageClicked(CaptureID, shift: Bool)
    case imageDoubleClicked(CaptureID)
    /// Esc on the key thumbnail (`keyDown` 53 or `cancelOperation`).
    case escape(CaptureID)
    case closeTapped(CaptureID)
    case stripTapped(CaptureID, StripSlot)
    case menuChosen(CaptureID, actionID: String, subitemID: String?)
    case decorationTapped(CaptureID, actionID: String)
    case selectionActionTapped
    case decorationsChanged(CaptureID)
    /// A `runFileAction`, `trash` or `remove` finished.
    case fileActionFinished(CaptureID, QuickAccessFileResult)
    /// The save panel closed: nil for Cancel.
    case saveAsChosen(CaptureID, URL?)
    case fadeOutFinished(CaptureID)
}

/// What the model asks the controller to do (spec §6), in order.
public enum QuickAccessEffect: Hashable, Sendable {
    case showPanel(CaptureID, frame: Rect2D)
    case fadeIn(CaptureID)
    case fadeOut(CaptureID)
    case closePanel(CaptureID)
    case layout([CaptureID: Rect2D], animated: Bool)
    case render(CaptureID, ThumbnailState)
    case makeKey(CaptureID)
    case restoreKey(WindowToken)
    case activateFrontmostApp
    case startTicker
    case stopTicker
    case copy(ClipboardPayload)
    case runFileAction(CaptureID, QuickAccessFileAction)
    /// Delete of a saved file; the result returns as `fileActionFinished(id, .deleted | .deleteFailed)`.
    case trash(CaptureID, URL)
    /// Delete of a temp file; same result.
    case remove(CaptureID, URL)
    case reveal(URL)
    case showSavePanel(CaptureID, name: String, directory: URL)
    case perform(QuickAccessActionContext)
    case recordActivity(PerformedQuickAccessAction)
    case publish(CaptureEvent)
    case notify(title: String, body: String)
    case log(String)
}
