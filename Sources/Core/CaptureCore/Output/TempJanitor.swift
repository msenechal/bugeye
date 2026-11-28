import BugeyeCore
import Foundation

/// A file in the temp folder old enough to purge.
public struct TempFile: Hashable, Sendable {
    public var url: URL
    /// From the identity xattr; nil when it has none.
    public var id: CaptureID?
}

/// Purges the temp folder (C11, C28, plan P11): files older than 24 h at launch, then every hour. The hourly purge
/// skips captures the bus still knows; the caller filters `candidates` for that on the main actor. Off the main
/// actor otherwise.
public struct TempJanitor: Sendable {
    public static let maxAge: TimeInterval = 24 * 3600
    public static let interval: TimeInterval = 3600
    let metadata: any FileMetadataStore

    public init(metadata: any FileMetadataStore) {
        self.metadata = metadata
    }

    /// Regular files last modified more than 24 h before `now`.
    public func candidates(in folder: URL, now: Date) -> [TempFile] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys, options: [])
        else { return [] }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                let modified = values.contentModificationDate, now.timeIntervalSince(modified) > Self.maxAge
            else { return nil }
            let id = (try? metadata.value(CaptureFileWriter.identityAttribute, at: url))
                .flatMap { $0 }.flatMap { String(data: $0, encoding: .utf8) }.flatMap(CaptureID.init(string:))
            return TempFile(url: url, id: id)
        }
    }

    /// Deletes the files; returns how many went.
    public func remove(_ files: [TempFile]) -> Int {
        files.reduce(0) { count, file in
            (try? FileManager.default.removeItem(at: file.url)) != nil ? count + 1 : count
        }
    }
}
