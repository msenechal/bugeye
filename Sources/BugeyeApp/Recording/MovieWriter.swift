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
    enum Failure: Error, LocalizedError, Equatable {
        case cannotStart(String)
        /// The writer failed earlier; what was written up to its last fragment stays on disk.
        case notWriting(String)

        var errorDescription: String? {
            switch self {
            case .cannotStart(let text), .notWriting(let text): text
            }
        }
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
    /// Called once, on the writer's queue, when the writer fails mid-take (disk full, encoder error): the
    /// recorder reports it so the take ends with "Recording stopped" (`design/04` §2.6, PR #22 review I1).
    var onFailure: ((String) -> Void)?
    private var failureReported = false
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
        guard isArmed, isWriting else { return }
        if !hasStarted {
            // The session starts only with a frame the input can take, so the movie never opens on a gap
            // (review M11).
            guard waitsForEncoder || video.isReadyForMoreMediaData else {
                droppedSamples += 1
                return
            }
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
        guard hasStarted, source < audio.count, isWriting,
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

    /// Writing; a writer that has failed reports it once.
    private var isWriting: Bool {
        switch writer.status {
        case .writing: return true
        case .failed:
            reportFailure(writer.error?.localizedDescription ?? "the writer stopped")
            return false
        default: return false
        }
    }

    /// Reports a failure once (`onFailure`). Internal so tests can stand in for a full disk.
    func reportFailure(_ text: String) {
        guard !failureReported else { return }
        failureReported = true
        onFailure?(text)
    }

    private func append(_ sample: CMSampleBuffer, to input: AVAssetWriterInput) -> Bool {
        if waitsForEncoder {
            while !input.isReadyForMoreMediaData, writer.status == .writing { usleep(1000) }
        }
        guard input.isReadyForMoreMediaData else {
            droppedSamples += 1
            return false
        }
        if input.append(sample) { return true }
        _ = isWriting
        return false
    }

    /// A copy whose first sample is at `seconds`. Every timing entry shifts by the same amount and keeps its own
    /// duration: one LPCM buffer holds 1024 samples of 1/48000 s each, not 1024 samples of the buffer's length
    /// (review I3).
    private func retimed(_ sample: CMSampleBuffer, to seconds: Double) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: max(count, 1))
        if count > 0 {
            CMSampleBufferGetSampleTimingInfoArray(
                sample, entryCount: count, arrayToFill: &timings, entriesNeededOut: &count)
        } else {
            timings[0] = CMSampleTimingInfo(
                duration: CMSampleBufferGetDuration(sample),
                presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sample), decodeTimeStamp: .invalid)
        }
        let target = CMTime(seconds: seconds, preferredTimescale: 1_000_000_000)
        let first = timings[0].presentationTimeStamp
        for index in timings.indices {
            let pts = timings[index].presentationTimeStamp
            timings[index].presentationTimeStamp = first.isValid && pts.isValid ? target + (pts - first) : target
            timings[index].decodeTimeStamp = .invalid
        }
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: sample, sampleTimingEntryCount: timings.count,
            sampleTimingArray: &timings, sampleBufferOut: &copy)
        return status == noErr ? copy : nil
    }
}
