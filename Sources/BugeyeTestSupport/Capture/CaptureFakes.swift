import BugeyeCore
import Foundation
import Synchronization

/// A window list given by the test, counting reads.
public final class FakeWindowListReader: WindowListReader {
    private let state: Mutex<(windows: [WindowInfo], reads: Int)>

    public init(windows: [WindowInfo] = []) {
        state = Mutex((windows, 0))
    }

    public var windowList: [WindowInfo] {
        get { state.withLock { $0.windows } }
        set { state.withLock { $0.windows = newValue } }
    }

    public var readCount: Int { state.withLock { $0.reads } }

    public func windows() async -> [WindowInfo] {
        state.withLock {
            $0.reads += 1
            return $0.windows
        }
    }
}

/// Image work on `PixelBuffer` storage, recording what was asked.
public final class FakeImagePipeline: ImagePipeline {
    private struct State {
        var failEncoding = false
        var downscaleFactors: [Double] = []
        var crops: [Rect2D] = []
        var encoded: [(width: Int, height: Int)] = []
    }
    private let state = Mutex(State())

    public init() {}

    public var failEncoding: Bool {
        get { state.withLock { $0.failEncoding } }
        set { state.withLock { $0.failEncoding = newValue } }
    }
    public var downscaleFactors: [Double] { state.withLock { $0.downscaleFactors } }
    public var crops: [Rect2D] { state.withLock { $0.crops } }
    /// Sizes of the images encoded, in order.
    public var encodedSizes: [Size2D] {
        state.withLock { $0.encoded.map { Size2D(width: Double($0.width), height: Double($0.height)) } }
    }

    /// What `pngData` answers for an image of this size.
    public static func png(width: Int, height: Int) -> Data {
        Data("PNG \(width)x\(height)".utf8)
    }

    public func crop(_ image: CapturedImage, to rect: Rect2D) -> CapturedImage? {
        state.withLock { $0.crops.append(rect) }
        let bounds = Rect2D(x: 0, y: 0, width: Double(image.pixelWidth), height: Double(image.pixelHeight))
        guard let clipped = rect.intersection(bounds) else { return nil }
        let x0 = Int(clipped.minX)
        let y0 = Int(clipped.minY)
        let width = Int(clipped.width)
        let height = Int(clipped.height)
        guard let source = image.storage as? PixelBuffer else {
            return CapturedImage(pixelWidth: width, pixelHeight: height, storage: image.storage)
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(width * height * 4)
        for y in y0..<(y0 + height) {
            let start = y * source.bytesPerRow + x0 * 4
            bytes += source.bytes[start..<(start + width * 4)]
        }
        guard let buffer = try? PixelBuffer(width: width, height: height, bytesPerRow: width * 4, bytes: bytes) else {
            return nil
        }
        return CapturedImage(pixelBuffer: buffer)
    }

    public func downscale(_ image: CapturedImage, by factor: Double) -> CapturedImage? {
        state.withLock { $0.downscaleFactors.append(factor) }
        let width = max(1, Int((Double(image.pixelWidth) * factor).rounded()))
        let height = max(1, Int((Double(image.pixelHeight) * factor).rounded()))
        guard let buffer = try? PixelBuffer(width: width, height: height, fill: RGBA8(red: 0, green: 0, blue: 0)) else {
            return nil
        }
        return CapturedImage(pixelBuffer: buffer)
    }

    public func pngData(_ image: CapturedImage) -> Data? {
        state.withLock { state -> Data? in
            guard !state.failEncoding else { return nil }
            state.encoded.append((image.pixelWidth, image.pixelHeight))
            return Self.png(width: image.pixelWidth, height: image.pixelHeight)
        }
    }

    public func pixelBuffer(_ image: CapturedImage) -> PixelBuffer? {
        image.storage as? PixelBuffer
    }

    public func preview(_ image: CapturedImage) -> PixelBuffer? {
        image.storage as? PixelBuffer
    }
}

/// Registrations in memory. Keys in `taken` are held by "another app", and a key another id holds is refused too,
/// as Carbon refuses an in-process duplicate; `press(id)` runs a registration's handler.
@MainActor
public final class FakeHotkeyRegistrar: HotkeyRegistrar {
    public var taken: Set<GlobalKey> = []
    public private(set) var registered: [String: GlobalKey] = [:]
    /// Every register call in order, with its outcome.
    public private(set) var attempts: [(id: String, key: GlobalKey, ok: Bool)] = []
    private var handlers: [String: @MainActor () -> Void] = [:]

    public init() {}

    public func register(_ id: String, key: GlobalKey, onPress: @escaping @MainActor () -> Void) -> Bool {
        unregister(id)
        let ok = !taken.contains(key) && !registered.values.contains(key)
        attempts.append((id, key, ok))
        guard ok else { return false }
        registered[id] = key
        handlers[id] = onPress
        return true
    }

    public func unregister(_ id: String) {
        registered[id] = nil
        handlers[id] = nil
    }

    /// Runs `id`'s handler; false when `id` holds no key.
    @discardableResult
    public func press(_ id: String) -> Bool {
        guard let handler = handlers[id] else { return false }
        handler()
        return true
    }
}

/// Symbolic hotkeys and a model string given by the test.
public struct FakeSystemShortcutReader: SystemShortcutReader {
    public var hotkeys: [Int: SymbolicHotkey]?
    public var model: String

    public init(hotkeys: [Int: SymbolicHotkey]? = [:], model: String = "Mac15,3") {
        self.hotkeys = hotkeys
        self.model = model
    }

    public func symbolicHotkeys() -> [Int: SymbolicHotkey]? { hotkeys }
    public func hardwareModel() -> String { model }
}
