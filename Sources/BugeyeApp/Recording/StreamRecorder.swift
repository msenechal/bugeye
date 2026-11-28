import AVFoundation
import BugeyeCore
import CoreMedia
import Foundation
import RecordingCore
import ScreenCaptureKit

/// The host clock (seconds): what ScreenCaptureKit stamps samples with, and what `NSEvent.timestamp` counts
/// (both mach-based). Every recording component reads it through here (PR #22 review M9).
enum HostClock {
    static func now() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }
}

/// What one take records.
struct StreamRequest: Sendable {
    var display: CGDirectDisplayID
    /// Display-local points, top-left; already clamped (`RecordingGeometry.clampedSourceRect`).
    var sourceRect: CGRect
    /// Effective options.
    var options: RecordingOptions
    /// Window recordings: the window followed (V10).
    var window: CGWindowID?
    /// The overlay and bubble windows: the exceptions to the app's exclusion (§5.4).
    var overlayWindowIDs: [CGWindowID]
    var output: URL
}

/// The ScreenCaptureKit stream and the movie writer of one take (`design/04` §2.6). Everything touching the
/// stream's samples, the writer and the follow timer runs on `queue`; callbacks go to the main queue in order.
final class StreamRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    enum Failure: Error, LocalizedError, Equatable {
        case userDeclined
        case noDisplay
        case noWindow
        /// `cancel()` ran while `prepare` was still starting the stream.
        case cancelled
        case other(String)

        var errorDescription: String? {
            switch self {
            case .userDeclined: "Screen Recording was declined."
            case .noDisplay: "The display to record isn't available."
            case .noWindow: "The window to record isn't available."
            case .cancelled: "The recording was cancelled."
            case .other(let text): text
            }
        }
    }

    struct Callbacks: Sendable {
        var firstFrame: @MainActor @Sendable (_ host: Double, _ date: Date) -> Void = { _, _ in }
        var failed: @MainActor @Sendable (Failure) -> Void = { _ in }
        /// A followed window moved: the new display-local source rect.
        var areaMoved: @MainActor @Sendable (CGRect) -> Void = { _ in }
        var log: @MainActor @Sendable (String) -> Void = { _ in }
    }

    let queue = DispatchQueue(label: "dev.msenechal.bugeye.recording.samples", qos: .userInteractive)
    /// Host-clock seconds (`HostClock`). Injected by tests.
    let now: @Sendable () -> Double
    private let callbacks: Callbacks

    // Confined to `queue`.
    private var stream: SCStream?
    private var writer: MovieWriter?
    private var configuration: SCStreamConfiguration?
    private var followTimer: DispatchSourceTimer?
    private var followedSize: CGSize = .zero
    private var lastFollowed: CGRect?
    private var displayFrame: CGRect = .zero
    private var children: [CGWindowID] = []
    private var fallback = ChildWindowFallback()
    private var request: StreamRequest?
    private var failure: Failure?
    private var micSource: Int?
    private var systemSource: Int?
    /// Set by `stop` and `cancel`; `prepare` checks it before installing and after starting (PR #22 review C1).
    private var isCancelled = false
    /// The latest complete frame before the take starts: a still screen sends `.idle` frames only, and the take
    /// must start when the countdown ends (V11, review I2).
    private var lastComplete: CMSampleBuffer?
    /// Filter updates apply in order; a superseded one is skipped (review I5).
    private var filterGeneration = 0
    private var filterTask: Task<Void, Never>?

    init(callbacks: Callbacks, now: @escaping @Sendable () -> Double = { HostClock.now() }) {
        self.callbacks = callbacks
        self.now = now
    }

    /// Starts the stream (frames are discarded until `beginTake`, V11). Throws `.userDeclined` when Screen
    /// Recording is refused, `.noWindow` when the window to follow is gone, `.cancelled` when `cancel()` ran first.
    func prepare(_ request: StreamRequest) async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch let error as SCStreamError where error.code == .userDeclined {
            throw Failure.userDeclined
        } catch {
            throw Failure.other(error.localizedDescription)
        }
        guard let display = content.displays.first(where: { $0.displayID == request.display }) else {
            throw Failure.noDisplay
        }
        let overlays = content.windows.filter { request.overlayWindowIDs.contains($0.windowID) }
        if overlays.count < request.overlayWindowIDs.count {
            let missing = request.overlayWindowIDs.count - overlays.count
            await callbacks.log("exception window \(missing) missing from the stream")
        }
        let displayFrame = CGDisplayBounds(request.display)
        let filter: SCContentFilter
        var childIDs: [CGWindowID] = []
        if let windowID = request.window {
            // Never fall back to the display: that records whatever is in front (§5.5, review I4).
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw Failure.noWindow
            }
            let followed = WindowFollow.global(
                Self.rect2D(request.sourceRect), displayBounds: Self.rect2D(displayFrame))
            childIDs = Self.childWindows(of: windowID, followedGlobal: followed, in: Self.windowList())
            let kids = content.windows.filter { childIDs.contains($0.windowID) }
            filter = SCContentFilter(display: display, including: [window] + kids + overlays)
        } else if let app = content.applications.first(where: {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }) {
            // Excluding the application also excludes windows it opens later (`design/04` §3).
            filter = SCContentFilter(display: display, excludingApplications: [app], exceptingWindows: overlays)
        } else {
            let own = content.windows.filter {
                $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
                    && !request.overlayWindowIDs.contains($0.windowID)
            }
            filter = SCContentFilter(display: display, excludingWindows: own)
        }
        let scale = Double(filter.pointPixelScale)
        let size = RecordingGeometry.outputSize(
            points: Size2D(width: request.sourceRect.width, height: request.sourceRect.height), scale: scale,
            codec: request.options.codec)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = request.sourceRect
        configuration.width = size.width
        configuration.height = size.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(request.options.fps))
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        configuration.showsCursor = true
        configuration.queueDepth = 6
        configuration.capturesAudio = request.options.systemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        if request.options.mic {
            configuration.captureMicrophone = true
            if !request.options.micDevice.isEmpty {
                configuration.microphoneCaptureDeviceID = request.options.micDevice
            }
        }
        let system = request.options.systemAudio ? 0 : nil
        let mic = request.options.mic ? (system == nil ? 0 : 1) : nil
        let writer: MovieWriter
        do {
            writer = try MovieWriter(
                url: request.output, size: size, fps: request.options.fps, codec: request.options.codec,
                quality: request.options.quality, audioSources: (system == nil ? 0 : 1) + (mic == nil ? 0 : 1))
        } catch {
            throw Failure.other(error.localizedDescription)
        }
        let callbacks = callbacks
        writer.onFirstFrame = { host in
            let date = Date()
            Self.onMain { callbacks.firstFrame(host, date) }
        }
        writer.onFailure = { [weak self] text in self?.report(.other(text)) }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            if system != nil { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
            if mic != nil { try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }
        } catch {
            writer.cancel()
            throw Failure.other(error.localizedDescription)
        }
        let installed = installIfLive {
            self.stream = stream
            self.writer = writer
            self.configuration = configuration
            self.request = request
            self.systemSource = system
            self.micSource = mic
            self.followedSize = request.sourceRect.size
            self.displayFrame = displayFrame
            self.children = childIDs
        }
        guard installed else {
            writer.cancel()
            throw Failure.cancelled
        }
        do {
            try await stream.startCapture()
        } catch let error as SCStreamError where error.code == .userDeclined {
            cancelWriter()
            throw Failure.userDeclined
        } catch {
            cancelWriter()
            throw Failure.other(error.localizedDescription)
        }
        // A cancel during `startCapture` raced it: stop what it started (the cancel already took the writer).
        if queue.sync(execute: { isCancelled }) {
            try? await stream.stopCapture()
            writer.cancel()
            throw Failure.cancelled
        }
        if request.window != nil { queue.async { self.startFollowing() } }
        await callbacks.log(
            "stream \(size.width)x\(size.height) \(request.options.fps) fps \(request.options.codec.rawValue) mic=\(mic != nil) system=\(system != nil)"
        )
    }

    /// The take begins at the next complete frame (or at once on a still screen, with the last complete one).
    func beginTake() { queue.async { self.writer?.arm() } }

    /// Stamped on the sample queue, so every frame already handled was captured before it (`design/04` §3).
    func pause(_ stamped: @escaping @Sendable (Double) -> Void = { _ in }) {
        queue.async {
            let host = self.now()
            self.writer?.pause(at: host)
            stamped(host)
        }
    }

    func resume(_ stamped: @escaping @Sendable (Double) -> Void = { _ in }) {
        queue.async {
            let host = self.now()
            self.writer?.resume(at: host)
            stamped(host)
        }
    }

    /// Stops the stream, then finishes the movie at the moment Stop was handled (not after the stream's stop,
    /// review M1). A late sample finds no writer and is dropped.
    func stop() async throws -> MovieWriter.Result {
        let (stream, writer, host) = detach()
        try? await stream?.stopCapture()
        guard let writer else { return .noFrames }
        return try await writer.finish(at: host)
    }

    /// Stops and deletes the movie. Safe to call more than once, and while `prepare` is running: `prepare` then
    /// stops what it started and throws `.cancelled`.
    func cancel() async {
        let (stream, writer, _) = detach()
        try? await stream?.stopCapture()
        writer?.cancel()
    }

    /// The first failure, if any (a failure before the take reached `recording`, `design/04` §3).
    var currentFailure: Failure? { queue.sync { failure } }

    // MARK: SCStreamOutput, SCStreamDelegate (on `queue`)

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        process(sample, of: type)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let failure: Failure =
            (error as? SCStreamError)?.code == .userDeclined ? .userDeclined : .other(error.localizedDescription)
        queue.async { self.report(failure) }
    }

    // MARK: Private (on `queue` unless noted)

    /// One sample, as the stream delivers it; the delegate and the tests both come through here.
    private func process(_ sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let writer, sample.isValid else { return }
        let host = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        switch type {
        case .screen:
            guard let status = Self.frameStatus(sample) else { return }
            switch status {
            case .complete:
                fallback.frameDelivered()
                writer.appendVideo(sample, host: host)
                lastComplete = writer.hasStarted ? nil : sample
            case .idle:
                // Nothing changed on screen: not a dropped frame (V23). On a still screen the take starts here,
                // with the last complete frame (V11, review I2).
                fallback.frameDelivered()
                if writer.isArmed, !writer.hasStarted, let cached = lastComplete {
                    writer.appendVideo(cached, host: host)
                    if writer.hasStarted { lastComplete = nil }
                }
            case .started, .stopped:
                break
            case .blank, .suspended:
                fallback.frameDropped()
                if fallback.useWindowAlone, !children.isEmpty { dropChildren() }
            @unknown default:
                break
            }
        case .audio:
            if let source = systemSource { writer.appendAudio(sample, source: source, host: host) }
        case .microphone:
            if let source = micSource { writer.appendAudio(sample, source: source, host: host) }
        @unknown default:
            break
        }
    }

    private func report(_ failure: Failure) {
        guard self.failure == nil else { return }
        self.failure = failure
        let callbacks = callbacks
        Self.onMain { callbacks.failed(failure) }
    }

    /// Callbacks reach the main actor in the order they were sent (review M2).
    private static func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
    }

    /// Runs `install` on the queue unless `cancel()` or `stop()` already ran; false then.
    func installIfLive(_ install: () -> Void) -> Bool {
        queue.sync {
            guard !isCancelled else { return false }
            install()
            return true
        }
    }

    /// Takes the stream and writer off the queue in one step, marks the recorder cancelled, cancels the follow
    /// timer and any filter update, and stamps the host time.
    private func detach() -> (SCStream?, MovieWriter?, Double) {
        queue.sync {
            isCancelled = true
            followTimer?.cancel()
            followTimer = nil
            filterGeneration += 1
            filterTask?.cancel()
            filterTask = nil
            lastComplete = nil
            defer {
                stream = nil
                writer = nil
            }
            return (stream, writer, now())
        }
    }

    private func cancelWriter() {
        let writer = queue.sync {
            defer { self.writer = nil }
            return self.writer
        }
        writer?.cancel()
    }

    private func startFollowing() {
        guard !isCancelled else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in self?.follow() }
        followTimer = timer
        timer.resume()
    }

    /// 10 times a second: the window's frame, its child windows, and the source rect (§5.5, V10). One window
    /// list per tick (review M4).
    private func follow() {
        guard let request, let windowID = request.window, let stream, let configuration else { return }
        let list = Self.windowList()
        guard let bounds = Self.bounds(of: windowID, in: list) else { return }
        let display = Self.rect2D(displayFrame)
        let followed = WindowFollow.followedRect(
            windowBounds: Self.rect2D(bounds), size: Size2D(width: followedSize.width, height: followedSize.height),
            displayBounds: display)
        let rect = CGRect(x: followed.origin.x, y: followed.origin.y, width: followed.width, height: followed.height)
        if rect != lastFollowed {
            lastFollowed = rect
            configuration.sourceRect = rect
            stream.updateConfiguration(configuration) { _ in }
            let callbacks = callbacks
            Self.onMain { callbacks.areaMoved(rect) }
        }
        guard !fallback.useWindowAlone else { return }
        let kids = Self.childWindows(
            of: windowID, followedGlobal: WindowFollow.global(followed, displayBounds: display), in: list)
        if kids != children {
            children = kids
            updateFilter(windowID: windowID, children: kids)
        }
    }

    private func dropChildren() {
        guard let windowID = request?.window else { return }
        children = []
        updateFilter(windowID: windowID, children: [])
        let callbacks = callbacks
        Self.onMain { callbacks.log("child windows dropped: frames lost after a filter update") }
    }

    /// Each update waits for the one before it and is skipped once a newer one exists, so filters apply in order
    /// and the window-alone filter isn't undone by a late child update. The fallback starts counting dropped
    /// frames only once the filter has applied (review I5).
    private func updateFilter(windowID: CGWindowID, children: [CGWindowID]) {
        guard let request, let stream else { return }
        filterGeneration += 1
        let generation = filterGeneration
        let ids = [windowID] + children + request.overlayWindowIDs
        let display = request.display
        let box = UncheckedBox(stream)
        let previous = filterTask
        filterTask = Task { [weak self] in
            await previous?.value
            guard let self, self.isLatest(generation),
                let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                let scDisplay = content.displays.first(where: { $0.displayID == display }),
                self.isLatest(generation)
            else { return }
            let windows = content.windows.filter { ids.contains($0.windowID) }
            do {
                try await box.value.updateContentFilter(SCContentFilter(display: scDisplay, including: windows))
            } catch {
                return
            }
            self.queue.async {
                if generation == self.filterGeneration { self.fallback.filterUpdated() }
            }
        }
    }

    /// Off the queue.
    private func isLatest(_ generation: Int) -> Bool {
        queue.sync { generation == filterGeneration && !isCancelled }
    }

    static func frameStatus(_ sample: CMSampleBuffer) -> SCFrameStatus? {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[.status] as? Int
        else { return nil }
        return SCFrameStatus(rawValue: raw)
    }

    static func rect2D(_ rect: CGRect) -> Rect2D {
        Rect2D(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    /// The on-screen windows, front to back.
    static func windowList() -> [[String: Any]] {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    }

    /// Quartz global bounds of a window in `list`; nil when it is gone.
    static func bounds(of id: CGWindowID, in list: [[String: Any]]) -> CGRect? {
        guard
            let entry = list.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id }),
            let dict = entry[kCGWindowBounds as String] as? NSDictionary
        else { return nil }
        return CGRect(dictionaryRepresentation: dict as CFDictionary)
    }

    /// The window's child windows (V10) in `list`. `followedGlobal` is the recorded rect in global points.
    static func childWindows(of id: CGWindowID, followedGlobal: Rect2D, in list: [[String: Any]]) -> [CGWindowID] {
        let snapshots = list.compactMap { entry -> WindowSnapshot? in
            guard let number = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue,
                let dict = entry[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: dict as CFDictionary)
            else { return nil }
            return WindowSnapshot(id: WindowID(number), processID: pid, layer: layer, frame: rect2D(frame))
        }
        return ChildWindowFilter.children(of: WindowID(id), in: snapshots, followedGlobal: followedGlobal)
            .map(\.rawValue)
    }
}

extension StreamRecorder {
    /// Test entry: feeds a sample as the stream would, on the queue.
    func feed(_ sample: CMSampleBuffer, of type: SCStreamOutputType) {
        queue.sync { process(sample, of: type) }
    }

    /// Test entry: attaches a writer without a stream.
    func attach(_ writer: MovieWriter, systemAudio: Bool = false, mic: Bool = false) {
        writer.onFailure = { [weak self] text in self?.report(.other(text)) }
        queue.sync {
            self.writer = writer
            self.systemSource = systemAudio ? 0 : nil
            self.micSource = mic ? (systemAudio ? 1 : 0) : nil
        }
    }

    /// Test entry: reports a failure as the stream would.
    func simulateFailure(_ failure: Failure) {
        queue.sync { report(failure) }
    }
}

/// Carries a non-Sendable framework object into a task; the object is thread-safe for the use made of it
/// (SCStream's async API).
struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
