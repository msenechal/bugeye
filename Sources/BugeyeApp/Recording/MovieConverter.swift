@preconcurrency import AVFoundation
import BugeyeCore
import CoreMedia
import Foundation
import MacAdapters
import RecordingCore
import Synchronization

/// `.mov` → `.mp4` (V8, `design/04` §2.9): the video passed through untouched, every audio track mixed into one
/// AAC 48 kHz stereo 160 kbit/s track. Both pumps run concurrently (pumping one after the other deadlocks the
/// interleaving writer). A deadline, a failure or a refused start keeps the `.mov` and deletes the partial
/// `.mp4`. Runs off the main actor.
///
/// The deadline is a hard limit: `convert` returns when it passes even if the job is stuck in AVFoundation
/// (PR #22 review I6). The job is aborted and deletes its own `.mp4` whenever it actually ends.
enum MovieConverter {
    enum Outcome: Equatable, Sendable {
        /// The `.mov` is deleted.
        case converted(URL)
        case keptMovie(reason: String)
    }

    static func convert(
        _ movie: URL, to output: URL, deadline: Duration, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async -> Outcome {
        let job = Job(movie: movie, output: output, progress: progress)
        let first = FirstResult()
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
            first.set(continuation)
            let timer = Task {
                try? await Task.sleep(for: deadline)
                guard !Task.isCancelled, first.resume(.keptMovie(reason: "timed out")) else { return }
                job.abort()
            }
            Task {
                let outcome = await job.run()
                timer.cancel()
                if !first.resume(outcome) {
                    // The deadline won: whatever the job made is not delivered.
                    try? FileManager.default.removeItem(at: output)
                }
            }
        }
        switch outcome {
        case .converted: try? FileManager.default.removeItem(at: movie)
        case .keptMovie: try? FileManager.default.removeItem(at: output)
        }
        return outcome
    }

    /// Resumes the continuation once: the first of the job and the deadline wins.
    private final class FirstResult: Sendable {
        private let state = Mutex<(continuation: CheckedContinuation<Outcome, Never>?, done: Bool)>((nil, false))

        func set(_ continuation: CheckedContinuation<Outcome, Never>) {
            state.withLock { $0.continuation = continuation }
        }

        /// True when this call resumed it.
        func resume(_ outcome: Outcome) -> Bool {
            let continuation = state.withLock { state -> CheckedContinuation<Outcome, Never>? in
                guard !state.done else { return nil }
                state.done = true
                defer { state.continuation = nil }
                return state.continuation
            }
            continuation?.resume(returning: outcome)
            return continuation != nil
        }
    }

    /// One conversion. Its AVFoundation objects are used from its own queues only; `abort()` cancels them once
    /// they are running.
    private final class Job: @unchecked Sendable {
        let movie: URL
        let output: URL
        let progress: @Sendable (Double) -> Void
        private struct State {
            var reader: UncheckedBox<AVAssetReader>?
            var writer: UncheckedBox<AVAssetWriter>?
            var aborted = false
        }
        private let state = Mutex(State())

        init(movie: URL, output: URL, progress: @escaping @Sendable (Double) -> Void) {
            self.movie = movie
            self.output = output
            self.progress = progress
        }

        func abort() {
            let (reader, writer) = state.withLock { state in
                state.aborted = true
                return (state.reader, state.writer)
            }
            reader?.value.cancelReading()
            writer?.value.cancelWriting()
        }

        func run() async -> MovieConverter.Outcome {
            do {
                return try await convert()
            } catch {
                return .keptMovie(reason: error.localizedDescription)
            }
        }

        private func convert() async throws -> MovieConverter.Outcome {
            let asset = AVURLAsset(url: movie)
            let duration = try await asset.load(.duration).seconds
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                return .keptMovie(reason: "no video track")
            }
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let formatHint = try await videoTrack.load(.formatDescriptions).first
            let transform = try await videoTrack.load(.preferredTransform)
            if isAborted { return .keptMovie(reason: "timed out") }

            try? FileManager.default.removeItem(at: output)
            let reader = try AVAssetReader(asset: asset)
            let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)

            let videoOut = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
            videoOut.alwaysCopiesSampleData = false
            reader.add(videoOut)
            let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formatHint)
            videoIn.transform = transform
            writer.add(videoIn)

            var audioPair: (AVAssetReaderAudioMixOutput, AVAssetWriterInput)?
            if !audioTracks.isEmpty {
                let mix = AVAssetReaderAudioMixOutput(
                    audioTracks: audioTracks,
                    audioSettings: [
                        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
                        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsNonInterleaved: false,
                    ])
                reader.add(mix)
                var layout = AudioChannelLayout()
                layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
                let audioIn = AVAssetWriterInput(
                    mediaType: .audio,
                    outputSettings: [
                        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
                        AVEncoderBitRateKey: 160_000,
                        AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size),
                    ])
                writer.add(audioIn)
                audioPair = (mix, audioIn)
            }

            guard reader.startReading() else {
                return .keptMovie(reason: reader.error?.localizedDescription ?? "couldn't read the movie")
            }
            guard writer.startWriting() else {
                reader.cancelReading()
                return .keptMovie(reason: writer.error?.localizedDescription ?? "couldn't write the MP4")
            }
            writer.startSession(atSourceTime: .zero)
            // Registered only now: cancelling a writer before `add` or `startWriting` raises an Objective-C
            // exception (review I6). An abort that came first cancels both here.
            let readerBox = UncheckedBox(reader)
            let writerBox = UncheckedBox(writer)
            let abortedEarly = state.withLock { state -> Bool in
                guard !state.aborted else { return true }
                state.reader = readerBox
                state.writer = writerBox
                return false
            }
            if abortedEarly {
                reader.cancelReading()
                writer.cancelWriting()
                return .keptMovie(reason: "timed out")
            }

            let percent = Mutex(-1)
            let progress = progress
            // Whole percents only: a fast conversion has thousands of samples a second (review M5).
            let onTime: @Sendable (Double) -> Void = { time in
                // A sample without a valid time (NaN) would trap in `Int(_:)` (macos run 46126649599).
                guard duration > 0, duration.isFinite, time.isFinite else { return }
                let value = Int((min(time / duration, 1) * 100).rounded(.down))
                let changed = percent.withLock { last -> Bool in
                    guard value > last else { return false }
                    last = value
                    return true
                }
                if changed { progress(Double(value) / 100) }
            }
            async let videoDone: Void = Self.pump(videoOut, into: videoIn, label: "video", onTime: onTime)
            if let (mix, audioIn) = audioPair {
                async let audioDone: Void = Self.pump(mix, into: audioIn, label: "audio", onTime: { _ in })
                _ = await (videoDone, audioDone)
            } else {
                await videoDone
            }

            if reader.status == .failed || writer.status == .failed || isAborted {
                if writer.status == .writing { writer.cancelWriting() }
                return .keptMovie(
                    reason: (reader.error ?? writer.error)?.localizedDescription ?? "the conversion stopped")
            }
            await writer.finishWriting()
            guard writer.status == .completed else {
                return .keptMovie(reason: writer.error?.localizedDescription ?? "the MP4 wasn't finished")
            }
            return .converted(output)
        }

        private var isAborted: Bool { state.withLock { $0.aborted } }

        /// Copies samples until the output runs dry or the input refuses one; always marks the input finished,
        /// so the other pump can't wait forever.
        private static func pump(
            _ output: AVAssetReaderOutput, into input: AVAssetWriterInput, label: String,
            onTime: @escaping @Sendable (Double) -> Void
        ) async {
            let queue = DispatchQueue(label: "dev.msenechal.bugeye.convert.\(label)")
            let output = UncheckedBox(output)
            let input = UncheckedBox(input)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                // Only touched on `queue`; a lock keeps the compiler (and a stray callback) honest.
                let done = Mutex(false)
                input.value.requestMediaDataWhenReady(on: queue) {
                    guard !done.withLock({ $0 }) else { return }
                    func finish() {
                        done.withLock { $0 = true }
                        input.value.markAsFinished()
                        continuation.resume()
                    }
                    while input.value.isReadyForMoreMediaData {
                        guard let sample = output.value.copyNextSampleBuffer() else { return finish() }
                        onTime(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
                        if !input.value.append(sample) { return finish() }
                    }
                }
            }
        }
    }
}

/// The first frame as the thumbnail's preview (§3: at most `CaptureEvent.previewMaxWidth` px wide), or nil.
enum FirstFrame {
    static func preview(of movie: URL) async -> PixelBuffer? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        guard let image = try? await generator.image(at: .zero).image else { return nil }
        return PixelBufferImages.preview(image)
    }
}

/// Microphones and cameras by unique id (§5.2).
enum CaptureDevices {
    struct Device: Hashable, Sendable {
        var id: String
        var name: String
    }

    static func microphones() -> [Device] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
        )
        .devices.map { Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    static func cameras() -> [Device] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video,
            position: .unspecified
        ).devices.map { Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    static func list() -> CaptureDeviceList {
        CaptureDeviceList(microphones: microphones().map(\.id), cameras: cameras().map(\.id))
    }
}

/// Free space for the disk guard (§5.3), on the volume holding `url` (or its nearest existing parent).
enum DiskSpace {
    static func freeBytes(at url: URL) -> Int64? {
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path), probe.path != "/" {
            probe.deleteLastPathComponent()
        }
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
