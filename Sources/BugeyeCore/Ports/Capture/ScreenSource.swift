// Capture-owned from Wave 1 (contracts §4.1.9): moved here unchanged; Capture reshapes it (C8).

/// Screen pixels (ScreenCaptureKit on macOS).
public protocol ScreenSource: Sendable {
    func displays() async throws -> [DisplayInfo]
    /// Captures `rect` (in the display's points; nil for the whole display) at the display's full scale.
    func capture(display: DisplayID, rect: Rect2D?) async throws -> PixelBuffer
}
