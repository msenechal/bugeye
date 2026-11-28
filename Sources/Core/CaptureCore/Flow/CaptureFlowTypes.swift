import BugeyeCore
import Foundation

/// One capture's identity, from a request leaving `idle` until it is back there. Every overlay window and view event
/// carries the session that created it (Capture §6).
public struct SessionID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
    public var description: String { "\(rawValue)" }
}

/// Which `select` call an answer belongs to (plan P6).
public struct SelectionTicket: Hashable, Sendable {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
}

/// What a screenshot request asks for (Capture §5.1).
public enum CaptureRequestKind: String, Hashable, Sendable, CaseIterable {
    case fullscreen, allDisplays, area, window
}

public enum OverlayMode: Hashable, Sendable { case area, window }

/// What the flow knows of one frozen frame: geometry, never pixels (Capture C7).
public struct FrameInfo: Hashable, Sendable {
    public var display: DisplayInfo
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var time: Date

    public init(display: DisplayInfo, pixelWidth: Int, pixelHeight: Int, time: Date) {
        self.display = display
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.time = time
    }

    /// Image pixel width ÷ display point width, from the captured image (design/02 §2.3).
    public var scale: Double { display.frame.width > 0 ? Double(pixelWidth) / display.frame.width : 1 }
}

public enum FreezeTarget: Hashable, Sendable {
    case all
    /// The display under this Cocoa point, else the first display.
    case underPointer(CocoaPoint)
}

public enum DeliverySource: Hashable, Sendable {
    /// A frozen display's frame, cropped to `crop` (pixels), or whole when nil.
    case frame(DisplayID, crop: PixelRect?)
    /// The live window capture the session holds.
    case window
}

/// One image to save, copy and announce.
public struct Delivery: Hashable, Sendable {
    public var source: DeliverySource
    /// The image's pixels per point before any downscale.
    public var scale: Double
    /// When its pixels were taken: names the file and is its `createdAt` (Capture C10).
    public var time: Date
    public init(source: DeliverySource, scale: Double, time: Date) {
        self.source = source
        self.scale = scale
        self.time = time
    }
}

public struct Notice: Hashable, Sendable {
    public var title: String
    public var body: String
    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public enum SelectionOutcome: String, Hashable, Sendable { case area, window, display, cancelled }

/// The `os.Logger` categories (Capture §8).
public enum LogCategory: String, Hashable, Sendable { case selection, capture, hotkeys }

public struct Modifiers: Hashable, Sendable {
    public var shift: Bool
    public var option: Bool
    public init(shift: Bool = false, option: Bool = false) {
        self.shift = shift
        self.option = option
    }
}

public enum KeyPress: Hashable, Sendable { case escape, space, `return` }

/// What the shell feeds the flow.
public enum FlowEvent: Hashable, Sendable {
    /// A screenshot request. `permitted`: Screen Recording preflight; `activityAllows`: `ScreenActivity.allows(.screenshot)`;
    /// `lastArea`: `capture.lastArea`, read fresh (C9).
    case request(CaptureRequestKind, permitted: Bool, activityAllows: Bool, pointer: CocoaPoint, lastArea: StoredArea?)
    /// `AreaSelector.select` for another purpose (§6.1).
    case select(SelectionTicket, SelectionRequest)
    /// `AreaSelector.cancel`.
    case externalCancel(SelectionPurpose)
    case frozen(SessionID, [FrameInfo], windows: [WindowInfo], pointer: CocoaPoint)
    case freezeFailed(SessionID, ScreenSourceError)
    // From the overlay views; points are view-local (plan P5).
    case pointerMoved(SessionID, DisplayID, ViewPoint)
    case pointerEntered(SessionID, DisplayID, buttonDown: Bool)
    case mouseDown(SessionID, DisplayID, ViewPoint, Modifiers)
    /// The display and point are those of the view where the drag started (AppKit sends every drag event there);
    /// the flow uses the drag's own display.
    case mouseDragged(SessionID, DisplayID, ViewPoint, Modifiers)
    case mouseUp(SessionID, DisplayID, ViewPoint)
    case rightMouseDown(SessionID)
    case key(SessionID, KeyPress)
    /// The temporary global Esc hotkey.
    case globalEscape
    /// A display was plugged, unplugged or rearranged (C16).
    case displaysChanged
    case windowCaptured(SessionID, time: Date)
    case windowCaptureFailed(SessionID, ScreenSourceError)
    case delivered(SessionID, notices: [Notice])
}

/// What the flow asks the shell to do. Only `showOverlays` and `makeKey` can show or key a window.
public enum FlowEffect: Hashable, Sendable {
    case readWindowList(SessionID)
    case freeze(SessionID, FreezeTarget)
    case showOverlays(SessionID, displays: [DisplayID], mode: OverlayMode)
    /// Close (not hide) every overlay of the session, then sweep leftovers.
    case closeOverlays(SessionID)
    /// Close every overlay window whose session isn't the live selecting one.
    case sweepLeftovers
    case makeKey(SessionID, DisplayID)
    /// `damage` in display-local points; nil redraws the whole overlay.
    case redraw(SessionID, DisplayID, damage: DisplayRect?)
    case registerEscape(SessionID)
    case unregisterEscape(SessionID)
    case activateBugeye
    case reactivatePreviousApp
    case beep
    case captureWindow(SessionID, WindowID, windowSize: Size2D, scale: Double)
    case deliver(SessionID, [Delivery])
    case storeLastArea(StoredArea)
    case showPermissionAlert
    case notify(title: String, body: String)
    case log(LogCategory, String)
    /// `begin <purpose> overlays [<window numbers>]`: the shell adds the numbers.
    case logSelectionBegin(SessionID, SelectionPurpose)
    /// `finish <outcome> overlays [<window numbers>]`.
    case logSelectionFinish(SessionID, SelectionOutcome)
    case answer(SelectionTicket, SelectionResult)
}

/// What one overlay view draws, all in its display's local points.
public struct OverlayRender: Hashable, Sendable {
    public var mode: OverlayMode
    /// Area mode: the current selection on this display.
    public var selection: DisplayRect?
    /// Window mode: the hovered window, in this display's space (the view clips it).
    public var hovered: DisplayRect?
    public var hint: String?
    public init(mode: OverlayMode, selection: DisplayRect?, hovered: DisplayRect?, hint: String?) {
        self.mode = mode
        self.selection = selection
        self.hovered = hovered
        self.hint = hint
    }
}
