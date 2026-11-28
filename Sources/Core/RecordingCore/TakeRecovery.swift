import Foundation

/// What to do at launch with what a crash left in the in-progress folder (V15, §7.1).
public enum TakeRecovery {
    /// Below this, a movie holds no complete 2 s fragment (a crash in the countdown or the first seconds).
    public static let minimumMovieBytes: Int64 = 64 * 1024
    /// Files changed this recently may belong to another running instance (a debug build beside the
    /// installed app shares the folder): left alone.
    public static let quietSeconds: TimeInterval = 10

    /// A file in `CaptureFolders.recordingsInProgress`.
    public struct File: Hashable, Sendable {
        public var name: String
        public var created: Date
        public var modified: Date
        public var size: Int64

        public init(name: String, created: Date, modified: Date? = nil, size: Int64 = .max) {
            self.name = name
            self.created = created
            self.modified = modified ?? created
            self.size = size
        }
    }

    public struct Recovery: Hashable, Sendable {
        public var take: UUID
        /// The file to deliver: the `.mov`, or an `.mp4` whose conversion finished before the crash.
        public var movie: String
        /// Its timeline, if any; recovered without an `end` line.
        public var timeline: String?
        /// Names the delivered file (`CaptureFileNamer`): the timeline's creation (the take's start) when there
        /// is one, else the movie's.
        public var createdAt: Date

        public init(take: UUID, movie: String, timeline: String?, createdAt: Date) {
            self.take = take
            self.movie = movie
            self.timeline = timeline
            self.createdAt = createdAt
        }
    }

    public struct Plan: Hashable, Sendable {
        /// Oldest first.
        public var recover: [Recovery]
        /// A partial `.mp4` beside its `.mov`; a movie too small to play, with its timeline.
        public var delete: [String]
    }

    public static func movieName(take: UUID) -> String { "Take-" + take.uuidString.lowercased() + ".mov" }
    public static func convertedName(take: UUID) -> String { "Take-" + take.uuidString.lowercased() + ".mp4" }
    public static func timelineName(take: UUID) -> String {
        "Take-" + take.uuidString.lowercased() + ".timeline.jsonl"
    }

    public static func take(fromMovieName name: String) -> UUID? { take(name, suffix: ".mov") }

    /// Takes not in `liveTakes` and quiet for `quietSeconds` before `now` are recovered or deleted. A timeline
    /// with no movie is left alone: its recording may have been delivered just before a crash (the Wave 2 index
    /// can sweep orphans).
    public static func plan(files: [File], liveTakes: Set<UUID>, now: Date = .distantFuture) -> Plan {
        var movs: [UUID: File] = [:]
        var mp4s: [UUID: File] = [:]
        var timelines: [UUID: File] = [:]
        for file in files {
            if let id = take(file.name, suffix: ".mov") {
                movs[id] = file
            } else if let id = take(file.name, suffix: ".mp4") {
                mp4s[id] = file
            } else if let id = take(file.name, suffix: ".timeline.jsonl") {
                timelines[id] = file
            }
        }
        var recover: [Recovery] = []
        var delete: [String] = []
        for id in Set(movs.keys).union(mp4s.keys) where !liveTakes.contains(id) {
            let all = [movs[id], mp4s[id], timelines[id]].compactMap { $0 }
            guard all.allSatisfy({ now.timeIntervalSince($0.modified) >= quietSeconds }) else { continue }
            let movie: File
            if let mov = movs[id] {
                if let mp4 = mp4s[id] { delete.append(mp4.name) }
                movie = mov
            } else {
                // swift-format-ignore: NeverForceUnwrap
                movie = mp4s[id]!
            }
            guard movie.size >= minimumMovieBytes else {
                delete.append(movie.name)
                if let timeline = timelines[id] { delete.append(timeline.name) }
                continue
            }
            recover.append(
                Recovery(
                    take: id, movie: movie.name, timeline: timelines[id]?.name,
                    createdAt: timelines[id]?.created ?? movie.created))
        }
        recover.sort { ($0.createdAt, $0.movie) < ($1.createdAt, $1.movie) }
        return Plan(recover: recover, delete: delete.sorted())
    }

    private static func take(_ name: String, suffix: String) -> UUID? {
        guard name.hasPrefix("Take-"), name.hasSuffix(suffix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(5).dropLast(suffix.count)))
    }
}
