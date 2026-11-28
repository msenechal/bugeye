import AVFoundation
import AppKit
import BugeyeCore
import BugeyeTestSupport
import CoreMedia
import Foundation
import RecordingCore
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
        let asset = AVURLAsset(url: url)
        #expect(abs(try await asset.load(.duration).seconds - 1.0) < 0.1)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_H264)
        let primaries = CMFormatDescriptionGetExtension(
            format, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries)
        #expect((primaries as? String) == (kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String))
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

    @Test func finishingAFailedWriterThrowsInsteadOfRaising() async throws {
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

    @Test func aMissedDeadlineKeepsTheMovie() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let mov = try await Samples.movie(in: dir)
        let mp4 = dir.file("late.mp4")
        let outcome = await MovieConverter.convert(mov, to: mp4, deadline: .zero)
        #expect(outcome == .keptMovie(reason: "timed out"))
        #expect(FileManager.default.fileExists(atPath: mov.path))
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

@Suite struct StreamRecorderTests {
    @Test func samplesThroughTheQueueAndTheFailureLatch() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let recorder = StreamRecorder(callbacks: StreamRecorder.Callbacks())
        let writer = try Samples.writer(dir.file("s.mov"), audioSources: 1)
        recorder.attach(writer, systemAudio: true)
        recorder.beginTake()
        for n in 0..<15 {
            let host = 100 + Double(n) / 30
            recorder.handle(Samples.video(host: host), of: .screen)
            recorder.handle(Samples.audio(host: host), of: .audio)
        }
        recorder.simulateFailure(.other("first"))
        recorder.simulateFailure(.other("second"))
        #expect(recorder.currentFailure == .other("first"))
        recorder.now = { 100.5 }
        guard case .movie(_, let duration) = try await recorder.stop() else {
            Issue.record("no movie")
            return
        }
        #expect(abs(duration - 0.5) < 0.05)
        // After stop, a late sample finds no writer.
        recorder.handle(Samples.video(host: 101), of: .screen)
    }

    @Test func cancelDeletesTheMovie() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let url = dir.file("c.mov")
        let recorder = StreamRecorder(callbacks: StreamRecorder.Callbacks())
        recorder.attach(try Samples.writer(url))
        recorder.beginTake()
        recorder.handle(Samples.video(host: 100), of: .screen)
        await recorder.cancel()
        await recorder.cancel()
        #expect(!FileManager.default.fileExists(atPath: url.path))
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
