import Foundation

// Capture-owned ports (contracts §4.1.9, K3; Capture C8). Reshaped by the Capture epic; each change is a ruling in
// docs/ledgers/wave-1-capture.md.

/// A native image the shell holds (a `CGImage` on macOS, in its display's colour space), which the core only
/// measures and hands back to `ImagePipeline` (Capture C7, plan P3). Fakes store a `PixelBuffer`.
public struct CapturedImage: Sendable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// The platform image. Only the adapter that made it reads it.
    public var storage: any Sendable

    public init(pixelWidth: Int, pixelHeight: Int, storage: any Sendable) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.storage = storage
    }

    /// An image whose storage is the buffer itself (fakes and tests).
    public init(pixelBuffer: PixelBuffer) {
        self.init(pixelWidth: pixelBuffer.width, pixelHeight: pixelBuffer.height, storage: pixelBuffer)
    }
}

/// One display's frozen frame.
public struct FrozenDisplay: Sendable {
    public var display: DisplayInfo
    public var image: CapturedImage
    /// When the pixels were taken (Capture C10).
    public var time: Date

    public init(display: DisplayInfo, image: CapturedImage, time: Date) {
        self.display = display
        self.image = image
        self.time = time
    }
}

/// Why a screen capture failed. `permissionDenied` shows the Screen Recording alert; the rest post `Capture failed`.
public enum ScreenSourceError: Error, Equatable, Sendable {
    /// Screen Recording is missing, or ScreenCaptureKit answered `userDeclined`.
    case permissionDenied
    /// A display disappeared between the request and the capture.
    case displayNotFound
    /// The window closed before its capture.
    case windowNotFound
    /// Any other ScreenCaptureKit error, with its `localizedDescription`.
    case failed(String)
}

/// Screen pixels (ScreenCaptureKit on macOS).
public protocol ScreenSource: Sendable {
    /// The connected displays, in the source's order.
    func displays() async throws -> [DisplayInfo]
    /// Freezes `displays` (nil: every display) from **one** shareable-content fetch, all displays concurrently, with
    /// Bugeye's own windows excluded by process id. Results are in the source's display order. A missing display
    /// throws `displayNotFound`.
    func freeze(displays: [DisplayID]?) async throws -> [FrozenDisplay]
    /// A live capture of one window with its shadow on a transparent background, fitted into `pixelSize`.
    func captureWindow(_ id: WindowID, pixelSize: Size2D) async throws -> CapturedImage
}

/// One on-screen window, as `CGWindowListCopyWindowInfo` reports it. Titles are never read (Capture §8).
public struct WindowInfo: Hashable, Sendable {
    public var id: WindowID
    public var ownerPID: Int32
    /// Quartz global points: origin at the top-left of the primary display, y down.
    public var bounds: Rect2D
    public var layer: Int
    public var alpha: Double

    public init(id: WindowID, ownerPID: Int32, bounds: Rect2D, layer: Int, alpha: Double) {
        self.id = id
        self.ownerPID = ownerPID
        self.bounds = bounds
        self.layer = layer
        self.alpha = alpha
    }
}

/// The window server's on-screen window list (CGWindowList on macOS).
public protocol WindowListReader: Sendable {
    /// Front to back, desktop elements excluded.
    func windows() async -> [WindowInfo]
}

/// Image work on native frozen frames (ImageIO on macOS). It never decodes a file (contracts K9).
public protocol ImagePipeline: Sendable {
    /// `rect` in the image's pixels, top-left origin. Nil when it misses the image.
    func crop(_ image: CapturedImage, to rect: Rect2D) -> CapturedImage?
    /// Scales by `factor` with high-quality interpolation in the image's own colour space.
    func downscale(_ image: CapturedImage, by factor: Double) -> CapturedImage?
    /// PNG data at the image's size; nil when encoding fails.
    func pngData(_ image: CapturedImage) -> Data?
    /// The pixels as RGBA8 premultiplied (window-shadow measurement reads the alpha channel).
    func pixelBuffer(_ image: CapturedImage) -> PixelBuffer?
    /// At most `CaptureEvent.previewMaxWidth` wide, sRGB, for the `created` event.
    func preview(_ image: CapturedImage) -> PixelBuffer?
}

/// A global key as the registrar takes it (plan P4: ports can't see `BugeyeFeatures.KeyCombo`).
public struct GlobalKey: Hashable, Sendable {
    /// One lowercase character, or "\u{1B}" for Escape.
    public var key: String
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool

    public init(_ key: String, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false)
    {
        self.key = key
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }

    /// Bare Esc, the temporary hotkey while an overlay is up (Capture §5.6).
    public static let escape = GlobalKey("\u{1B}")
}

/// Global hotkeys (Carbon `RegisterEventHotKey` on macOS, signature 'BgEy').
@MainActor
public protocol HotkeyRegistrar: AnyObject {
    /// Registers `key` under `id`, first releasing any key `id` held. False when another app holds the key.
    func register(_ id: String, key: GlobalKey, onPress: @escaping @MainActor () -> Void) -> Bool
    /// Releases `id`'s key; a no-op when it holds none.
    func unregister(_ id: String)
}

/// One `AppleSymbolicHotKeys` entry of `com.apple.symbolichotkeys`.
public struct SymbolicHotkey: Hashable, Sendable {
    public var enabled: Bool
    /// `value.parameters`: ASCII code (65535 for none), virtual key code, modifier flags.
    public var parameters: [Int]

    public init(enabled: Bool, parameters: [Int]) {
        self.enabled = enabled
        self.parameters = parameters
    }
}

/// macOS's own screenshot shortcuts and the Mac model (Capture C13).
public protocol SystemShortcutReader: Sendable {
    /// The parsed entries by number, or nil when the domain can't be read.
    func symbolicHotkeys() -> [Int: SymbolicHotkey]?
    /// `sysctl hw.model`, e.g. "MacBookPro18,3".
    func hardwareModel() -> String
}
