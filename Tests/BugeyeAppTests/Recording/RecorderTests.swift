import AVFoundation
import AppKit
import BugeyeCore
import BugeyeTestSupport
import CoreMedia
import Foundation
import RecordingCore
import ScreenCaptureKit
import Synchronization
import Testing

@testable import BugeyeApp

/// Synthetic samples for the writer and converter (spec §9 item 2, macOS CI).
enum Samples {
    static func video(host: Double, size: Int = 64) -> CMSampleBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            nil, size, size, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil, imageBuffer: buffer!, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(seconds: host, preferredTimescale: 1_000_000_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: buffer!, formatDescription: format!, sampleTiming: &timing,
            sampleBufferOut: &sample)
        return sample!
    }

    /// 16-bit stereo silence at 48 kHz.
    static func audio(host: Double, frames: Int = 1024) -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked, mBytesPerPacket: 4,
            mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &format)
        let size = frames * 4
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: size, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: size, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0, dataLength: size)
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block!, formatDescription: format!, sampleCount: frames,
            presentationTimeStamp: CMTime(seconds: host, preferredTimescale: 48_000), packetDescriptions: nil,
            sampleBufferOut: &sample)
        return sample!
    }

    /// A frame carrying the status ScreenCaptureKit attaches.
    static func frame(host: Double, _ status: SCFrameStatus) -> CMSampleBuffer {
        let sample = video(host: host)
        let array = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true)!
        let dict = Unmanaged<NSMutableDictionary>.fromOpaque(CFArrayGetValueAtIndex(array, 0)!).takeUnretainedValue()
        dict[SCStreamFrameInfo.status.rawValue] = NSNumber(value: status.rawValue)
        return sample
    }

    static func writer(_ url: URL, audioSources: Int = 0) throws -> MovieWriter {
        let writer = try MovieWriter(
            url: url, size: PixelSize(width: 64, height: 64), fps: 30, codec: .h264, quality: .standard,
            audioSources: audioSources)
        writer.waitsForEncoder = true
        return writer
    }

    /// Writes `seconds` of frames (and audio on every source) from host `start`.
    static func feed(_ writer: MovieWriter, from start: Double, seconds: Double, audioSources: Int = 0) {
        var t = start
        while t < start + seconds - 1e-9 {
            writer.appendVideo(video(host: t), host: t)
            t += 1.0 / 30
        }
        var a = start
        while a < start + seconds - 1e-9 {
            for source in 0..<audioSources { writer.appendAudio(audio(host: a), source: source, host: a) }
            a += 1024.0 / 48_000
        }
    }

    /// A finished `.mov` of `seconds`, with `audioSources` audio tracks.
    static func movie(in dir: TempDirectory, seconds: Double = 1, audioSources: Int = 2) async throws -> URL {
        let url = dir.file("Take-\(UUID().uuidString.lowercased()).mov")
        let writer = try writer(url, audioSources: audioSources)
        writer.arm()
        feed(writer, from: 100, seconds: seconds, audioSources: audioSources)
        _ = try await writer.finish(at: 100 + seconds)
        return url
    }
}

@Suite struct MovieWriterTests {
    @Test func pausedTimeIsCutAndTheMovieIsTaggedBT709() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let url = dir.file("a.mov")
        let writer = try Samples.writer(url)
        writer.arm()
        Samples.feed(writer, from: 100, seconds: 0.5)
        writer.pause(at: 100.5)
        // Captured in the pause: dropped, even if handled after the resume.
        Samples.feed(writer, from: 100.6, seconds: 1)
        writer.resume(at: 102)
        Samples.feed(writer, from: 102, seconds: 0.5)
        let result = try await writer.finish(at: 102.5)
        guard case .movie(let out, let duration) = result else {
            Issue.record("no movie")
            return
        }
        #expect(out == url)
        #expect(abs(duration - 1.0) < 0.05)
        // The 30 frames captured in the pause were dropped, not written (review I7).
        #expect(writer.droppedSamples == 30)
        let asset = AVURLAsset(url: url)
        #expect(abs(try await asset.load(.duration).seconds - 1.0) < 0.1)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let times = try Self.presentationTimes(of: track, in: asset)
        #expect(times.count == 30)
        #expect(Set(times).count == 30)
        let last = times.max() ?? 0
        #expect(last < 1.0)
        let format = try #require(try await track.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_H264)
        let primaries = CMFormatDescriptionGetExtension(
            format, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries)
        #expect((primaries as? String) == (kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String))
    }

    /// The video samples' presentation times, in seconds.
    static func presentationTimes(of track: AVAssetTrack, in asset: AVAsset) throws -> [Double] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var times: [Double] = []
        while let sample = output.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(sample) > 0 {
                times.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
            }
        }
        return times
    }

    /// One LPCM buffer is 1024 samples of 1/48000 s: retiming keeps that, so a 1 s take has 1 s of audio
    /// (review I3).
    @Test func audioKeepsItsTiming() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let mov = try await Samples.movie(in: dir, seconds: 1, audioSources: 1)
        let asset = AVURLAsset(url: mov)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let range = try await track.load(.timeRange)
        #expect(abs(range.duration.seconds - 1.0) < 0.05)
        #expect(range.start.seconds < 0.05)
    }

    @Test func aFailureIsReportedOnce() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let writer = try Samples.writer(dir.file("f.mov"))
        let reports = ProgressBox()
        writer.onFailure = { _ in reports.add(1) }
        writer.reportFailure("disk full")
        writer.reportFailure("again")
        #expect(reports.values.count == 1)
        writer.cancel()
    }

    @Test func framesBeforeTheTakeAreDiscardedAndNoFramesDeletesTheFile() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let url = dir.file("b.mov")
        let writer = try Samples.writer(url)
        Samples.feed(writer, from: 100, seconds: 0.5)
        #expect(try await writer.finish(at: 101) == .noFrames)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func framesThatDoNotAdvanceAreDropped() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let writer = try Samples.writer(dir.file("c.mov"))
        writer.arm()
        writer.appendVideo(Samples.video(host: 100), host: 100)
        writer.appendVideo(Samples.video(host: 100.1), host: 100.1)
        writer.appendVideo(Samples.video(host: 100.05), host: 100.05)
        #expect(writer.droppedSamples == 1)
        writer.cancel()
    }

    @Test func finishingAWriterThatStoppedThrowsInsteadOfRaising() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let writer = try Samples.writer(dir.file("d.mov"))
        writer.arm()
        writer.appendVideo(Samples.video(host: 100), host: 100)
        writer.cancel()
        await #expect(throws: MovieWriter.Failure.self) { try await writer.finish(at: 101) }
    }

    @Test func aPauseBeforeTheFirstFrameStartsTheTakePaused() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let writer = try Samples.writer(dir.file("e.mov"))
        writer.arm()
        writer.pause(at: 99)
        Samples.feed(writer, from: 100, seconds: 1)
        writer.resume(at: 101)
        Samples.feed(writer, from: 101, seconds: 0.5)
        guard case .movie(_, let duration) = try await writer.finish(at: 101.5) else {
            Issue.record("no movie")
            return
        }
        #expect(abs(duration - 0.5) < 0.05)
    }
}

@Suite struct MovieConverterTests {
    @Test func twoAudioTracksBecomeOneAndTheVideoIsUntouched() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let mov = try await Samples.movie(in: dir)
        #expect(try await AVURLAsset(url: mov).loadTracks(withMediaType: .audio).count == 2)
        let mp4 = dir.file("out.mp4")
        let progress = ProgressBox()
        let outcome = await MovieConverter.convert(mov, to: mp4, deadline: .seconds(60)) { progress.add($0) }
        #expect(outcome == .converted(mp4))
        #expect(!FileManager.default.fileExists(atPath: mov.path))
        let asset = AVURLAsset(url: mp4)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        let audioTrack = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let audioFormat = try #require(try await audioTrack.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(audioFormat) == kAudioFormatMPEG4AAC)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let format = try #require(try await video.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_H264)
        let primaries = CMFormatDescriptionGetExtension(
            format, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries)
        #expect((primaries as? String) == (kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String))
        #expect(progress.values.last.map { $0 > 0.5 } == true)
    }

    /// A pump stuck in AVFoundation can't hold the deadline up: `convert` returns when it passes, keeps the
    /// `.mov`, and the partial `.mp4` is gone once the job ends (review I6, I7).
    @Test func aMissedDeadlineKeepsTheMovie() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let mov = try await Samples.movie(in: dir)
        let mp4 = dir.file("late.mp4")
        let blocked = ProgressBox()
        let release = DispatchSemaphore(value: 0)
        let started = ContinuousClock.now
        // The deadline leaves room for loading the movie on a busy runner, so the pump is reached and then stuck
        // until the test releases it (macos run 46127213310 reached the deadline before the first sample).
        let outcome = await MovieConverter.convert(mov, to: mp4, deadline: .seconds(1)) { value in
            guard blocked.values.isEmpty else { return }
            blocked.add(value)
            _ = release.wait(timeout: .now() + 10)
        }
        let elapsed = ContinuousClock.now - started
        release.signal()
        #expect(elapsed < .seconds(5))
        #expect(outcome == .keptMovie(reason: "timed out"))
        #expect(!blocked.values.isEmpty)
        #expect(FileManager.default.fileExists(atPath: mov.path))
        for _ in 0..<100 where FileManager.default.fileExists(atPath: mp4.path) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!FileManager.default.fileExists(atPath: mp4.path))
    }

    @Test func theFirstFrameIsAPreviewAtMost480Wide() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let mov = try await Samples.movie(in: dir, audioSources: 0)
        let preview = try #require(await FirstFrame.preview(of: mov))
        #expect(preview.width <= 480)
        #expect(preview.width > 0)
    }
}

final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Double] = []
    var values: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
    func add(_ value: Double) {
        lock.lock()
        stored.append(value)
        lock.unlock()
    }
}

/// A host clock the test sets.
final class TestHostClock: Sendable {
    private let value: Mutex<Double>
    init(_ start: Double) { value = Mutex(start) }
    var now: Double { value.withLock { $0 } }
    func set(_ new: Double) { value.withLock { $0 = new } }
}

@Suite struct StreamRecorderTests {
    /// Complete frames at 30 fps from `start` for `seconds`.
    private func frames(_ recorder: StreamRecorder, from start: Double, seconds: Double) {
        var t = start
        while t < start + seconds - 1e-9 {
            recorder.feed(Samples.frame(host: t, .complete), of: .screen)
            t += 1.0 / 30
        }
    }

    private func hasStarted(_ recorder: StreamRecorder, _ writer: MovieWriter) -> Bool {
        recorder.queue.sync { writer.hasStarted }
    }

    @Test func samplesThroughTheQueueAndTheFailureLatch() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let recorder = StreamRecorder(callbacks: StreamRecorder.Callbacks(), now: { 100.5 })
        let writer = try Samples.writer(dir.file("s.mov"), audioSources: 1)
        recorder.attach(writer, systemAudio: true)
        recorder.beginTake()
        for n in 0..<15 {
            let host = 100 + Double(n) / 30
            recorder.feed(Samples.frame(host: host, .complete), of: .screen)
            recorder.feed(Samples.audio(host: host), of: .audio)
        }
        recorder.simulateFailure(.other("first"))
        recorder.simulateFailure(.other("second"))
        #expect(recorder.currentFailure == .other("first"))
        guard case .movie(_, let duration) = try await recorder.stop() else {
            Issue.record("no movie")
            return
        }
        #expect(abs(duration - 0.5) < 0.05)
        // After stop, a late sample finds no writer.
        recorder.feed(Samples.frame(host: 101, .complete), of: .screen)
    }

    /// Blank and status-less frames never start the take; idle ones start it with the last complete frame, so a
    /// still screen starts recording when the countdown ends (review I2, I7).
    @Test func onlyRealPicturesStartTheTake() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let recorder = StreamRecorder(callbacks: StreamRecorder.Callbacks(), now: { 100.5 })
        let writer = try Samples.writer(dir.file("i.mov"))
        recorder.attach(writer)
        // A countdown frame: cached, not written (the take isn't armed).
        recorder.feed(Samples.frame(host: 99.9, .complete), of: .screen)
        recorder.beginTake()
        recorder.feed(Samples.frame(host: 99.95, .blank), of: .screen)
        recorder.feed(Samples.video(host: 99.97), of: .screen)
        recorder.feed(Samples.frame(host: 99.98, .started), of: .screen)
        #expect(!hasStarted(recorder, writer))
        recorder.feed(Samples.frame(host: 100, .idle), of: .screen)
        #expect(hasStarted(recorder, writer))
        frames(recorder, from: 100 + 1.0 / 30, seconds: 0.4)
        guard case .movie(_, let duration) = try await recorder.stop() else {
            Issue.record("no movie")
            return
        }
        #expect(abs(duration - 0.5) < 0.05)
    }

    @Test func blankFramesOnlyMakeNoMovie() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let url = dir.file("b.mov")
        let recorder = StreamRecorder(callbacks: StreamRecorder.Callbacks(), now: { 101 })
        recorder.attach(try Samples.writer(url))
        recorder.beginTake()
        recorder.feed(Samples.frame(host: 100, .blank), of: .screen)
        recorder.feed(Samples.frame(host: 100.1, .idle), of: .screen)
        #expect(try await recorder.stop() == .noFrames)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func pauseAndResumeAreStampedOnTheQueue() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let clock = TestHostClock(100)
        let recorder = StreamRecorder(callbacks: StreamRecorder.Callbacks(), now: { clock.now })
        recorder.attach(try Samples.writer(dir.file("p.mov")))
        recorder.beginTake()
        let stamps = ProgressBox()
        frames(recorder, from: 100, seconds: 0.5)
        clock.set(100.5)
        recorder.pause { stamps.add($0) }
        frames(recorder, from: 100.5, seconds: 0.5)
        clock.set(101)
        recorder.resume { stamps.add($0) }
        frames(recorder, from: 101, seconds: 0.5)
        clock.set(101.5)
        guard case .movie(_, let duration) = try await recorder.stop() else {
            Issue.record("no movie")
            return
        }
        #expect(stamps.values == [100.5, 101])
        #expect(abs(duration - 1.0) < 0.05)
    }

    @Test func aWriterFailureIsReported() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let recorder = StreamRecorder(callbacks: StreamRecorder.Callbacks())
        let writer = try Samples.writer(dir.file("w.mov"))
        recorder.attach(writer)
        recorder.queue.sync { writer.reportFailure("disk full") }
        #expect(recorder.currentFailure == .other("disk full"))
        writer.cancel()
    }

    @Test func cancelDeletesTheMovie() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let url = dir.file("c.mov")
        let recorder = StreamRecorder(callbacks: StreamRecorder.Callbacks())
        recorder.attach(try Samples.writer(url))
        recorder.beginTake()
        recorder.feed(Samples.frame(host: 100, .complete), of: .screen)
        await recorder.cancel()
        await recorder.cancel()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// A cancel while `prepare` is loading the content: the stream is never installed (review C1).
    @Test func aCancelBeforeInstallingWins() async {
        let fresh = StreamRecorder(callbacks: StreamRecorder.Callbacks())
        #expect(fresh.installIfLive {})
        let cancelled = StreamRecorder(callbacks: StreamRecorder.Callbacks())
        await cancelled.cancel()
        var ran = false
        #expect(!cancelled.installIfLive { ran = true })
        #expect(!ran)
    }
}

@MainActor @Suite struct InputTranslationTests {
    @Test func modifiersAndCoordinates() {
        #expect(InputTranslation.modifiers([.command, .shift]) == [.cmd, .shift])
        #expect(InputTranslation.modifiers([.control, .option, .capsLock]) == [.ctrl, .opt])
        #expect(InputTranslation.quartz(CGPoint(x: 10, y: 900), primaryHeight: 982) == Point2D(x: 10, y: 82))
    }

    @Test func clicksBecomeDownAndUpInQuartzPoints() throws {
        let down = try #require(
            NSEvent.mouseEvent(
                with: .rightMouseDown, location: CGPoint(x: 100, y: 800), modifierFlags: [], timestamp: 5,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 2, pressure: 1))
        #expect(
            InputTranslation.input(for: down, primaryHeight: 982) == .down(.right, Point2D(x: 100, y: 182), clicks: 2))
        let up = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseUp, location: CGPoint(x: 1, y: 2), modifierFlags: [], timestamp: 5, windowNumber: 0,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
        #expect(InputTranslation.input(for: up, primaryHeight: 982) == .up(.left, Point2D(x: 1, y: 980)))
    }

    @Test func keysCarryTheirUnmodifiedCharacterAndRepeats() throws {
        let key = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 1, windowNumber: 0,
                context: nil, characters: "#", charactersIgnoringModifiers: "3", isARepeat: true, keyCode: 20))
        let press = try #require(InputTranslation.keyPress(for: key))
        #expect(press.keyCode == 20)
        #expect(press.modifiers == [.cmd, .shift])
        #expect(press.isRepeat)
        // The label path takes the number row's digit whatever the characters say.
        #expect(
            KeystrokeFormatter.label(
                keyCode: press.keyCode, characters: press.characters, modifiers: press.modifiers, showAllKeys: false)
                == "⇧ ⌘ 3")
    }
}

@Suite struct RecordingSystemTests {
    @Test func diskSpaceWalksUpToAnExistingFolder() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let free = try #require(DiskSpace.freeBytes(at: dir.url.appendingPathComponent("not/yet/there")))
        #expect(free > 0)
    }

    @Test func devicesListWithoutCrashing() {
        let list = CaptureDevices.list()
        #expect(list.microphones.allSatisfy { !$0.isEmpty })
    }
}
