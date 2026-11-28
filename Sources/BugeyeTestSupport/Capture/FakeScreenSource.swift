import BugeyeCore
import Foundation
import Synchronization

/// Displays given by the test. A freeze answers a filled `PixelBuffer` per display at `frame × scale` pixels and
/// counts as one content fetch; window captures answer scripted images in order. After `hold()`, freezes and window
/// captures wait until `release()`, so a test can cancel while one is in flight.
public final class FakeScreenSource: ScreenSource {
    public struct WindowCapture: Hashable, Sendable {
        public var id: WindowID
        public var pixelSize: Size2D
        public init(id: WindowID, pixelSize: Size2D) {
            self.id = id
            self.pixelSize = pixelSize
        }
    }

    private struct State {
        var displays: [DisplayInfo]
        var time: Date
        var freezeCount = 0
        var freezeFailure: ScreenSourceError?
        var windowImages: [WindowID: [PixelBuffer]] = [:]
        var windowFailure: ScreenSourceError?
        var windowCaptures: [WindowCapture] = []
        var held = false
        var waiting: [CheckedContinuation<Void, Never>] = []
    }
    private let state: Mutex<State>

    public init(displays: [DisplayInfo] = [], time: Date = Date(timeIntervalSince1970: 1_795_784_592)) {
        state = Mutex(State(displays: displays, time: time))
    }

    public var displayList: [DisplayInfo] {
        get { state.withLock { $0.displays } }
        set { state.withLock { $0.displays = newValue } }
    }

    /// The time every freeze reports.
    public var time: Date {
        get { state.withLock { $0.time } }
        set { state.withLock { $0.time = newValue } }
    }

    /// How many freezes ran (one shareable-content fetch each).
    public var freezeCount: Int { state.withLock { $0.freezeCount } }
    public var windowCaptures: [WindowCapture] { state.withLock { $0.windowCaptures } }

    /// Images each window capture answers, in order; the last one repeats.
    public var windowImages: [WindowID: [PixelBuffer]] {
        get { state.withLock { $0.windowImages } }
        set { state.withLock { $0.windowImages = newValue } }
    }

    public func failNextFreeze(_ error: ScreenSourceError) { state.withLock { $0.freezeFailure = error } }
    public func failNextWindowCapture(_ error: ScreenSourceError) { state.withLock { $0.windowFailure = error } }

    /// Makes later freezes and window captures wait for `release()`.
    public func hold() { state.withLock { $0.held = true } }

    /// Lets every waiting call go on; later calls don't wait.
    public func release() {
        let waiting = state.withLock { state in
            state.held = false
            defer { state.waiting = [] }
            return state.waiting
        }
        for continuation in waiting { continuation.resume() }
    }

    /// Calls waiting for `release()`.
    public var waitingCount: Int { state.withLock { $0.waiting.count } }

    private func gate() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = state.withLock { state -> Bool in
                guard state.held else { return true }
                state.waiting.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    public func displays() async throws -> [DisplayInfo] {
        state.withLock { $0.displays }
    }

    public func freeze(displays wanted: [DisplayID]?) async throws -> [FrozenDisplay] {
        await gate()
        let (displays, time) = try state.withLock { state -> ([DisplayInfo], Date) in
            state.freezeCount += 1
            if let failure = state.freezeFailure {
                state.freezeFailure = nil
                throw failure
            }
            return (state.displays, state.time)
        }
        if let wanted, wanted.contains(where: { id in !displays.contains { $0.id == id } }) {
            throw ScreenSourceError.displayNotFound
        }
        return try displays.filter { wanted?.contains($0.id) ?? true }.map { display in
            let width = Int((display.frame.width * display.scale).rounded())
            let height = Int((display.frame.height * display.scale).rounded())
            let fill = RGBA8(red: UInt8(truncatingIfNeeded: display.id.rawValue), green: 0, blue: 0)
            let buffer = try PixelBuffer(width: width, height: height, fill: fill)
            return FrozenDisplay(display: display, image: CapturedImage(pixelBuffer: buffer), time: time)
        }
    }

    public func captureWindow(_ id: WindowID, pixelSize: Size2D) async throws -> CapturedImage {
        await gate()
        return try state.withLock { state in
            state.windowCaptures.append(WindowCapture(id: id, pixelSize: pixelSize))
            if let failure = state.windowFailure {
                state.windowFailure = nil
                throw failure
            }
            guard var images = state.windowImages[id], let image = images.first else {
                throw ScreenSourceError.windowNotFound
            }
            if images.count > 1 {
                images.removeFirst()
                state.windowImages[id] = images
            }
            return CapturedImage(pixelBuffer: image)
        }
    }
}
