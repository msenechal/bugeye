public enum SelectionPurpose: String, Hashable, Sendable { case screenshot, recording, scrolling, text }

/// An area remembered for Return: display-local, top-left origin, points. Capture C9's `capture.lastArea` JSON
/// and Recording's `recording.lastArea` both use it.
public struct StoredArea: Hashable, Codable, Sendable {
    public var display: DisplayID
    public var rect: Rect2D
    public var displaySize: Size2D

    public init(display: DisplayID, rect: Rect2D, displaySize: Size2D) {
        self.display = display
        self.rect = rect
        self.displaySize = displaySize
    }
}

public struct SelectionRequest: Hashable, Sendable {
    public var purpose: SelectionPurpose
    public var startInWindowMode: Bool
    /// Drawn at the top of each display; nil for none.
    public var hint: String?
    /// A click without a drag, or a selection under 4 × 4 pt, selects the display under it.
    public var clickSelectsDisplay: Bool
    /// In window mode, a window whose centre is on no display beeps and the overlay stays.
    public var windowNeedsDisplayCentre: Bool
    /// What Return / keypad Enter returns; beeps when nil, its display is gone or changed size.
    public var lastArea: StoredArea?

    public init(
        purpose: SelectionPurpose, startInWindowMode: Bool = false, hint: String? = nil,
        clickSelectsDisplay: Bool = false, windowNeedsDisplayCentre: Bool = false, lastArea: StoredArea? = nil
    ) {
        self.purpose = purpose
        self.startInWindowMode = startInWindowMode
        self.hint = hint
        self.clickSelectsDisplay = clickSelectsDisplay
        self.windowNeedsDisplayCentre = windowNeedsDisplayCentre
        self.lastArea = lastArea
    }
}

public enum SelectionResult: Hashable, Sendable {
    /// Display-local, top-left, points, with the display's size at selection time (K29).
    case area(StoredArea)
    case display(DisplayID)
    /// `frame` in Cocoa global points.
    case window(WindowID, display: DisplayID, frame: Rect2D)
    case cancelled
    /// Another selection or capture is in progress.
    case busy
}

/// The selection overlay. Capture implements it (K15); Recording calls it.
@MainActor
public protocol AreaSelector: AnyObject {
    /// Opens the overlay for `request` and returns once it closes. Purposes other than `.screenshot` never
    /// deliver, store a last area, or capture a window: they only return the result.
    func select(_ request: SelectionRequest) async -> SelectionResult
    /// Cancels a selection opened with this purpose (no-op otherwise); `select` returns `.cancelled`.
    func cancel(_ purpose: SelectionPurpose)
}

/// What the shell hands out before Capture's selector exists. Capture's wiring sets `target` once.
@MainActor
public final class AreaSelectorRelay: AreaSelector {
    public var target: (any AreaSelector)?

    public init() {}

    /// Forwards to `target`; `.cancelled` while it is nil.
    public func select(_ request: SelectionRequest) async -> SelectionResult {
        guard let target else { return .cancelled }
        return await target.select(request)
    }

    public func cancel(_ purpose: SelectionPurpose) {
        target?.cancel(purpose)
    }
}
