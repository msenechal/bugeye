@preconcurrency import AVFoundation
import BugeyeCore
import CoreMedia
import Foundation
import MacAdapters
import RecordingCore

/// `.mov` → `.mp4` (V8, `design/04` §2.9): the video passed through untouched, every audio track mixed into one
/// AAC 48 kHz stereo 160 kbit/s track. Both pumps run concurrently (pumping one after the other deadlocks the
/// interleaving writer). A deadline, a failure or a refused start keeps the `.mov` and deletes the partial
/// `.mp4`. Runs off the main actor.
enum MovieConverter {
    enum Outcome: Equatable {
        /// The `.mov` is deleted.
        case converted(URL)
        case keptMovie(reason: String)
    }

    static func convert(
        _ movie: URL, to output: URL, deadline: Duration, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async -> Outcome {
        let job = Job(movie: movie, output: output, progress: progress)
        let outcome = await withTaskGroup(of: Outcome?.self) { group in
            group.addTask { await job.run() }
            group.addTask {
                try? await Task.sleep(for: deadline)
                return Task.isCancelled ? nil : .keptMovie(reason: "timed out")
            }
            var first: Outcome?
            while first == nil, let next = await group.next() { first = next }
            group.cancelAll()
            if case .keptMovie = first { job.abort() }
            return first ?? .keptMovie(reason: "no result")
        }
        switch outcome {
        case .converted: try? FileManager.default.removeItem(at: movie)
        case .keptMovie: try? FileManager.default.removeItem(at: output)
        }
        return outcome
    }

    /// One conversion. Its AVFoundation objects are used from its own queues only.
    private final class Job: @unchecked Sendable {
        let movie: URL
        let output: URL
        let progress: @Sendable (Double) -> Void
        private let lock = NSLock()
        private var reader: AVAssetReader?
        private var writer: AVAssetWriter?
        private var aborted = false

        init(movie: URL, output: URL, progress: @escaping @Sendable (Double) -> Void) {
            self.movie = movie
            self.output = output
            self.progress = progress
        }

        func abort() {
            lock.lock()
            aborted = true
            let reader = reader
            let writer = writer
            lock.unlock()
            reader?.cancelReading()
            writer?.cancelWriting()
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

            try? FileManager.default.removeItem(at: output)
            let reader = try AVAssetReader(asset: asset)
            let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
            lock.lock()
            if aborted {
                lock.unlock()
                return .keptMovie(reason: "timed out")
            }
            self.reader = reader
            self.writer = writer
            lock.unlock()

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

            let progress = progress
            async let videoDone: Void = Self.pump(
                videoOut, into: videoIn, label: "video",
                onTime: { time in if duration > 0 { progress(min(time / duration, 1)) } })
            if let (mix, audioIn) = audioPair {
                async let audioDone: Void = Self.pump(mix, into: audioIn, label: "audio", onTime: { _ in })
                _ = await (videoDone, audioDone)
            } else {
                await videoDone
            }

            if reader.status == .failed || writer.status == .failed || isAborted {
                writer.cancelWriting()
                return .keptMovie(
                    reason: (reader.error ?? writer.error)?.localizedDescription ?? "the conversion stopped")
            }
            await writer.finishWriting()
            guard writer.status == .completed else {
                return .keptMovie(reason: writer.error?.localizedDescription ?? "the MP4 wasn't finished")
            }
            return .converted(output)
        }

        private var isAborted: Bool {
            lock.lock()
            defer { lock.unlock() }
            return aborted
        }

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
                var done = false
                input.value.requestMediaDataWhenReady(on: queue) {
                    guard !done else { return }
                    while input.value.isReadyForMoreMediaData {
                        guard let sample = output.value.copyNextSampleBuffer() else {
                            done = true
                            input.value.markAsFinished()
                            continuation.resume()
                            return
                        }
                        onTime(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
                        if !input.value.append(sample) {
                            done = true
                            input.value.markAsFinished()
                            continuation.resume()
                            return
                        }
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
