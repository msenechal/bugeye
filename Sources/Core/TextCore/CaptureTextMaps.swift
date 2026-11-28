import BugeyeCore
import Foundation

/// What a map describes: one capture's file as it was when read (T3).
public struct TextMapKey: Hashable, Sendable {
    public var id: CaptureID
    public var fingerprint: FileFingerprint

    public init(id: CaptureID, fingerprint: FileFingerprint) {
        self.id = id
        self.fingerprint = fingerprint
    }
}

/// A capture's map and the key it was read under. Consumers check `CaptureTextMaps.isCurrent(key)` before applying it.
public struct CaptureTextMap: Hashable, Sendable {
    public var key: TextMapKey
    public var map: TextMap

    public init(key: TextMapKey, map: TextMap) {
        self.key = key
        self.map = map
    }
}

/// The per-capture store (OCR §5.4): reads every wanted capture in the background, answers `map(for:)` from its
/// cache, by joining a read, or by reading now, one read at a time, and never keeps a map for pixels that changed.
public actor CaptureTextMaps {
    private typealias Waiter = CheckedContinuation<CaptureTextMap, any Error>

    private struct Job {
        var priority: TextLogLine.Priority
        /// Demand jobs run oldest first, background jobs newest first, by this.
        var order: UInt64
        /// Whether the job began as a background read (so it falls back to one when its last waiter leaves).
        var startedInBackground: Bool
        var waiters: [UInt64: Waiter] = [:]
        /// Q6 reruns used.
        var reruns = 0
    }

    private struct Running {
        let id: CaptureID
        let generation: UInt64
        let task: Task<Void, Never>
    }

    private struct Outcome: Sendable {
        let before: ImageFileInfo
        let after: FileFingerprint?
        let map: TextMap
        let milliseconds: Int
    }

    /// Thrown by the strip check when the capture's URL changed under a read (Q5b).
    struct Moved: Error {}

    private let reader: TextMapReader
    private let files: any ImageFileReader
    private let capacity: Int
    private let wanted: @Sendable (CaptureItem) -> Bool
    private let log: @Sendable (TextLogLine) -> Void

    private var mirror: [CaptureID: CaptureItem] = [:]
    private var cache: [CaptureID: (value: CaptureTextMap, used: UInt64)] = [:]
    private var jobs: [CaptureID: Job] = [:]
    private var running: Running?
    private var counter: UInt64 = 0

    public init(
        reader: TextMapReader, files: any ImageFileReader, capacity: Int = 200,
        wanted: @escaping @Sendable (CaptureItem) -> Bool = { $0.kind == .screenshot },
        log: @escaping @Sendable (TextLogLine) -> Void
    ) {
        self.reader = reader
        self.files = files
        self.capacity = max(capacity, 1)
        self.wanted = wanted
        self.log = log
    }

    // MARK: Events

    /// Bus events, in publication order (Q3, Q5, Q5b).
    public func handle(_ event: CaptureEvent) {
        let item = event.item
        let id = item.id
        switch event.change {
        case .created:
            mirror[id] = item
            if wanted(item) { enqueue(id, priority: .background) }
        case .edited:
            guard mirror[id] != nil else { return }
            mirror[id] = item
            cache[id] = nil
            if cancelRunning(id) { log(.cancelled(id: id, reason: .edited)) }
            if jobs[id] != nil {
                requeue(id)
                jobs[id]?.reruns = 0
            } else if wanted(item) {
                enqueue(id, priority: .background)
            }
        case .saved, .moved:
            guard mirror[id] != nil else { return }
            mirror[id] = item
            if cancelRunning(id) {
                log(.cancelled(id: id, reason: .moved))
                requeue(id)
            }
        case .deleted:
            mirror[id] = nil
            cache[id] = nil
            if cancelRunning(id) { log(.cancelled(id: id, reason: .deleted)) }
            if let job = jobs.removeValue(forKey: id) { fail(job, TextMapError.captureGone(id)) }
        default:
            return
        }
        pump()
    }

    // MARK: Queries

    /// The capture's current map: cached, joined, or read now, ahead of background reads (Q4).
    public func map(for item: CaptureItem) async throws -> CaptureTextMap {
        let id = item.id
        if mirror[id] == nil { mirror[id] = item }  // plan P7
        if jobs[id] == nil, let entry = cache[id], let url = mirror[id]?.fileURL,
            let info = try? await files.info(of: url), info.fingerprint == entry.value.key.fingerprint,
            cache[id]?.value == entry.value
        {
            touch(id)
            return entry.value
        }
        guard mirror[id] != nil else { throw TextMapError.captureGone(id) }
        counter += 1
        let token = counter
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: Waiter) in
                addWaiter(continuation, token: token, to: id)
            }
        } onCancel: {
            Task { await self.cancelWaiter(token, of: id) }
        }
    }

    /// The last stored map for the capture, without touching the file.
    public func cached(_ id: CaptureID) -> CaptureTextMap? {
        guard let entry = cache[id] else { return nil }
        touch(id)
        return entry.value
    }

    /// Whether `key` still describes the capture's file. Consumers call it before applying a result.
    public func isCurrent(_ key: TextMapKey) async -> Bool {
        guard let url = mirror[key.id]?.fileURL else { return false }
        guard let info = try? await files.info(of: url) else { return false }
        return info.fingerprint == key.fingerprint && mirror[key.id] != nil
    }

    /// For tests: how many callers wait on the capture's read.
    func waiters(_ id: CaptureID) -> Int { jobs[id]?.waiters.count ?? 0 }

    /// The strip check of a running read (Q5b): throws when the mirror's URL is no longer the one being read.
    func checkURL(_ id: CaptureID, _ url: URL) throws {
        if let current = mirror[id]?.fileURL, current != url { throw Moved() }
    }

    // MARK: Queue

    private func enqueue(_ id: CaptureID, priority: TextLogLine.Priority) {
        counter += 1
        if var job = jobs[id] {
            if priority == .demand, job.priority == .background {
                job.priority = .demand
                job.order = counter  // plan P13
                jobs[id] = job
            }
            return
        }
        jobs[id] = Job(priority: priority, order: counter, startedInBackground: priority == .background)
    }

    /// A job read again (edit, move): a background job becomes the newest; a demand job keeps its place.
    private func requeue(_ id: CaptureID) {
        guard jobs[id]?.priority == .background else { return }
        counter += 1
        jobs[id]?.order = counter
    }

    private func addWaiter(_ waiter: Waiter, token: UInt64, to id: CaptureID) {
        if Task.isCancelled {
            waiter.resume(throwing: CancellationError())
            return
        }
        guard mirror[id] != nil else {
            waiter.resume(throwing: TextMapError.captureGone(id))
            return
        }
        enqueue(id, priority: .demand)
        jobs[id]?.waiters[token] = waiter
        pump()
    }

    /// A waiter's own task was cancelled (plan P12).
    private func cancelWaiter(_ token: UInt64, of id: CaptureID) {
        guard var job = jobs[id], let waiter = job.waiters.removeValue(forKey: token) else { return }
        waiter.resume(throwing: CancellationError())
        if job.waiters.isEmpty, running?.id != id, job.priority == .demand {
            if job.startedInBackground {
                job.priority = .background
                jobs[id] = job
            } else {
                jobs[id] = nil
                return
            }
        }
        jobs[id] = job
    }

    private func fail(_ job: Job, _ error: any Error) {
        for waiter in job.waiters.values { waiter.resume(throwing: error) }
    }

    /// Cancels the capture's running read, if any; its job stays queued.
    private func cancelRunning(_ id: CaptureID) -> Bool {
        guard let current = running, current.id == id else { return false }
        current.task.cancel()
        running = nil
        return true
    }

    /// Starts the next read when none is running (Q1, Q2).
    private func pump() {
        while running == nil {
            let demand = jobs.filter { $0.value.priority == .demand }.min { $0.value.order < $1.value.order }
            let background = jobs.filter { $0.value.priority == .background }.max { $0.value.order < $1.value.order }
            guard let (id, job) = demand ?? background else { return }
            guard let item = mirror[id] else {
                jobs[id] = nil
                fail(job, TextMapError.captureGone(id))
                continue
            }
            start(item)
        }
    }

    private func start(_ item: CaptureItem) {
        counter += 1
        let generation = counter
        let id = item.id
        let url = item.fileURL
        let reader = self.reader
        let files = self.files
        let task = Task {
            let result = await Self.work(
                url: url, pixelsPerPoint: item.pixelsPerPoint, reader: reader, files: files,
                check: { try await self.checkURL(id, url) })
            self.finish(id, generation: generation, item: item, result: result)
        }
        running = Running(id: id, generation: generation, task: task)
    }

    /// One read, off the actor (T9): the fingerprint before, the map, the fingerprint after.
    @concurrent private nonisolated static func work(
        url: URL, pixelsPerPoint: Double, reader: TextMapReader, files: any ImageFileReader,
        check: @escaping @Sendable () async throws -> Void
    ) async -> Result<Outcome, any Error> {
        let start = ContinuousClock.now
        do {
            let before: ImageFileInfo
            do {
                before = try await files.info(of: url)
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                throw TextMapError.unreadable(url)
            }
            let map = try await reader.read(.file(url), pixelsPerPoint: pixelsPerPoint, beforeStrip: check)
            let after = try? await files.info(of: url)
            let elapsed = start.duration(to: .now).components
            let milliseconds = Int(elapsed.seconds) * 1000 + Int(elapsed.attoseconds / 1_000_000_000_000_000)
            return .success(Outcome(before: before, after: after?.fingerprint, map: map, milliseconds: milliseconds))
        } catch {
            return .failure(error)
        }
    }

    private func finish(_ id: CaptureID, generation: UInt64, item: CaptureItem, result: Result<Outcome, any Error>) {
        // A read cancelled by an event was already handled there: its late result changes nothing.
        guard running?.generation == generation else { return }
        running = nil
        defer { pump() }
        guard var job = jobs[id] else { return }
        switch result {
        case .success(let outcome):
            guard mirror[id] != nil else {
                jobs[id] = nil
                log(.dropped(id: id, reason: .gone))
                fail(job, TextMapError.captureGone(id))
                return
            }
            guard outcome.after == outcome.before.fingerprint else {
                log(.dropped(id: id, reason: .changed))
                if job.reruns == 0 {
                    job.reruns = 1
                    jobs[id] = job
                } else {
                    jobs[id] = nil
                    fail(job, TextMapError.changedWhileReading(id))
                }
                return
            }
            let value = CaptureTextMap(
                key: TextMapKey(id: id, fingerprint: outcome.before.fingerprint), map: outcome.map)
            jobs[id] = nil
            store(value)
            for waiter in job.waiters.values { waiter.resume(returning: value) }
            log(
                .read(
                    id: id, width: outcome.before.width, height: outcome.before.height,
                    pixelsPerPoint: item.pixelsPerPoint,
                    strips: StripPlan(pixelsPerPoint: item.pixelsPerPoint).strips(height: outcome.before.height).count,
                    lines: outcome.map.lines.count, milliseconds: outcome.milliseconds, priority: job.priority))
        case .failure(is Moved):
            log(.cancelled(id: id, reason: .moved))
            requeue(id)
        case .failure(let error as TextMapError):
            jobs[id] = nil
            log(.failed(id: id, error: error))
            fail(job, error)
        case .failure(let error):
            jobs[id] = nil
            fail(job, error)
        }
    }

    // MARK: Cache (Q8)

    private func store(_ value: CaptureTextMap) {
        counter += 1
        cache[value.key.id] = (value, counter)
        while cache.count > capacity, let oldest = cache.min(by: { $0.value.used < $1.value.used })?.key {
            cache[oldest] = nil
        }
    }

    private func touch(_ id: CaptureID) {
        counter += 1
        cache[id]?.used = counter
    }
}
