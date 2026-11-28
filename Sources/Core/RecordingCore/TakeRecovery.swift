import Foundation

/// What to do at launch with what a crash left in the in-progress folder (V15, §7.1).
public enum TakeRecovery {
    /// A file in `CaptureFolders.recordingsInProgress`.
    public struct File: Hashable, Sendable {
        public var name: String
        public var created: Date

        public init(name: String, created: Date) {
            self.name = name
            self.created = created
        }
    }

    public struct Recovery: Hashable, Sendable {
        public var take: UUID
        /// The file to deliver: the `.mov`, or an `.mp4` whose conversion finished before the crash.
        public var movie: String
        /// Its timeline, if any; recovered without an `end` line.
        public var timeline: String?
        /// Names the delivered file (`CaptureFileNamer`).
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
        /// Orphans: a timeline whose movie is gone, a partial `.mp4` beside its `.mov`.
        public var delete: [String]
    }

    public static func movieName(take: UUID) -> String { "Take-" + take.uuidString.lowercased() + ".mov" }

    public static func take(fromMovieName name: String) -> UUID? { take(name, suffix: ".mov") }

    /// Files of takes not in `liveTakes` (none at launch) are recovered or deleted; anything else is left alone.
    public static func plan(files: [File], liveTakes: Set<UUID>) -> Plan {
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
        for id in Set(movs.keys).union(mp4s.keys).union(timelines.keys) where !liveTakes.contains(id) {
            let movie: File
            if let mov = movs[id] {
                movie = mov
                if let mp4 = mp4s[id] { delete.append(mp4.name) }
            } else if let mp4 = mp4s[id] {
                movie = mp4
            } else {
                if let timeline = timelines[id] { delete.append(timeline.name) }
                continue
            }
            recover.append(
                Recovery(take: id, movie: movie.name, timeline: timelines[id]?.name, createdAt: movie.created))
        }
        recover.sort { ($0.createdAt, $0.movie) < ($1.createdAt, $1.movie) }
        return Plan(recover: recover, delete: delete.sorted())
    }

    private static func take(_ name: String, suffix: String) -> UUID? {
        guard name.hasPrefix("Take-"), name.hasSuffix(suffix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(5).dropLast(suffix.count)))
    }
}
