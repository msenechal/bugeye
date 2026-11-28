import AVFoundation
import CoreMedia
import Foundation
import RecordingCore

/// Writes one take's QuickTime movie (`design/04` §2.7): H.264 or HEVC tagged BT.709, one AAC track per audio
/// source, 2 s fragments so a crash leaves a playable file. Samples carry host-clock times; the take's
/// `RecordingClock` maps them onto the output with paused spans removed.
///
/// Confined to one serial queue (the stream's sample queue); tests call it from one task.
final class MovieWriter: @unchecked Sendable {
    enum Failure: Error, Equatable {
        case cannotStart(String)
        /// The writer failed earlier; what was written up to its last fragment stays on disk.
        case notWriting(String)
    }

    enum Result: Equatable {
        case movie(URL, duration: Double)
        case noFrames
    }

    let url: URL
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let audio: [AVAssetWriterInput]
    private(set) var clock = RecordingClock()
    /// Frames before `arm()` (the countdown, V11) are discarded.
    private(set) var isArmed = false
    private(set) var hasStarted = false
    private var lastVideoTime = -Double.infinity
    /// Tests wait for the encoder instead of dropping a sample whose input isn't ready.
    var waitsForEncoder = false
    /// Called once, on the writer's queue, with the first frame's host time.
    var onFirstFrame: ((Double) -> Void)?
    private(set) var droppedSamples = 0
    /// A pause asked for before the first frame: the take starts paused at that frame (PR #13 review C1).
    private var pausedBeforeStart = false

    init(
        url: URL, size: PixelSize, fps: Int, codec: VideoCodec, quality: RecordingQuality, audioSources: Int
    ) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: RecordingGeometry.bitrate(size, fps: fps, quality: quality),
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
            ],
        ]
        video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { throw Failure.cannotStart("video input refused") }
        writer.add(video)
        var audio: [AVAssetWriterInput] = []
        for _ in 0..<audioSources {
            var layout = AudioChannelLayout()
            layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128_000,
                    AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size),
                ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw Failure.cannotStart("audio input refused") }
            writer.add(input)
            audio.append(input)
        }
        self.audio = audio
        guard writer.startWriting() else {
            throw Failure.cannotStart(writer.error?.localizedDescription ?? "the writer didn't start")
        }
    }

    var status: AVAssetWriter.Status { writer.status }

    /// The take begins at the next frame (`beginTake`).
    func arm() { isArmed = true }

    func appendVideo(_ sample: CMSampleBuffer, host: Double) {
        guard isArmed, writer.status == .writing else { return }
        if !hasStarted {
            clock.begin(at: host)
            writer.startSession(atSourceTime: .zero)
            hasStarted = true
            onFirstFrame?(host)
            if pausedBeforeStart {
                // The first frame is written at 0, then nothing until the resume.
                pausedBeforeStart = false
                if let copy = retimed(sample, to: 0), append(copy, to: video) { lastVideoTime = 0 }
                clock.pause(at: host)
                return
            }
        }
        // Frames captured in a pause, or that don't advance time, are dropped.
        guard let time = clock.outputTime(for: host), time > lastVideoTime else {
            droppedSamples += 1
            return
        }
        guard let copy = retimed(sample, to: time) else { return }
        if append(copy, to: video) { lastVideoTime = time }
    }

    /// Audio before the first frame, or captured in a pause, is dropped.
    func appendAudio(_ sample: CMSampleBuffer, source: Int, host: Double) {
        guard hasStarted, source < audio.count, writer.status == .writing,
            let time = clock.outputTime(for: host), let copy = retimed(sample, to: time)
        else { return }
        _ = append(copy, to: audio[source])
    }

    func pause(at host: Double) {
        if hasStarted { clock.pause(at: host) } else { pausedBeforeStart = true }
    }

    func resume(at host: Double) {
        if hasStarted { clock.resume(at: host) } else { pausedBeforeStart = false }
    }

    /// No frame: cancels and deletes, `.noFrames`. A failed writer throws (calling `endSession` on it would
    /// raise an Objective-C exception, `design/04` §3) and leaves its fragments on disk.
    func finish(at host: Double) async throws -> Result {
        guard hasStarted else {
            cancel()
            return .noFrames
        }
        guard writer.status == .writing else {
            throw Failure.notWriting(writer.error?.localizedDescription ?? "the writer stopped")
        }
        let end = max(clock.elapsed(at: host), lastVideoTime)
        video.markAsFinished()
        for input in audio { input.markAsFinished() }
        writer.endSession(atSourceTime: CMTime(seconds: end, preferredTimescale: 1_000_000_000))
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw Failure.notWriting(writer.error?.localizedDescription ?? "the movie wasn't finished")
        }
        return .movie(url, duration: end)
    }

    /// Stops and deletes the file.
    func cancel() {
        if writer.status == .writing { writer.cancelWriting() }
        try? FileManager.default.removeItem(at: url)
    }

    private func append(_ sample: CMSampleBuffer, to input: AVAssetWriterInput) -> Bool {
        if waitsForEncoder {
            while !input.isReadyForMoreMediaData, writer.status == .writing { usleep(1000) }
        }
        guard input.isReadyForMoreMediaData else {
            droppedSamples += 1
            return false
        }
        return input.append(sample)
    }

    private func retimed(_ sample: CMSampleBuffer, to seconds: Double) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sample),
            presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 1_000_000_000),
            decodeTimeStamp: .invalid)
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: sample, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleBufferOut: &copy)
        return status == noErr ? copy : nil
    }
}
