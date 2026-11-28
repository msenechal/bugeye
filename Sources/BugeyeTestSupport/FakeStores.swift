import BugeyeCore
import Foundation
import Synchronization

/// Settings in memory.
public final class InMemorySettingsStore: SettingsStore {
    private let values: Mutex<[String: SettingValue]>

    public init(_ values: [String: SettingValue] = [:]) {
        self.values = Mutex(values)
    }

    public var all: [String: SettingValue] { values.withLock { $0 } }

    public func value(forKey key: String) -> SettingValue? {
        values.withLock { $0[key] }
    }

    public func setValue(_ value: SettingValue?, forKey key: String) {
        values.withLock { $0[key] = value }
    }
}

/// Secrets in memory. `failNextWrite` makes the next set or remove throw, like a locked Keychain.
public final class FakeSecretStore: SecretStore {
    public struct WriteFailed: Error {
        public init() {}
    }

    private struct State {
        var secrets: [SecretKey: String] = [:]
        var failNextWrite = false
    }
    private let state = Mutex(State())

    public init(_ secrets: [SecretKey: String] = [:]) {
        state.withLock { $0.secrets = secrets }
    }

    public func failNextWrite() {
        state.withLock { $0.failNextWrite = true }
    }

    public func secret(for key: SecretKey) throws -> String? {
        state.withLock { $0.secrets[key] }
    }

    public func setSecret(_ value: String, for key: SecretKey) throws {
        try state.withLock {
            if $0.failNextWrite {
                $0.failNextWrite = false
                throw WriteFailed()
            }
            $0.secrets[key] = value
        }
    }

    public func removeSecret(for key: SecretKey) throws {
        try state.withLock {
            if $0.failNextWrite {
                $0.failNextWrite = false
                throw WriteFailed()
            }
            $0.secrets[key] = nil
        }
    }
}

/// Extended attributes kept in memory and keyed by the file's inode, like real xattrs: they follow a
/// rename, and they are lost when another file replaces the path (an `.atomic` write does that).
/// Every call throws for a missing file, as `getxattr` does.
public final class FakeFileMetadataStore: FileMetadataStore {
    public struct InjectedFailure: Error, Equatable {
        public let name: String
        public init(name: String) { self.name = name }
    }

    private struct FileKey: Hashable {
        let device: UInt64
        let inode: UInt64
    }

    /// A file's attributes and the path it was last seen at.
    private struct Entry {
        var path: String
        var values: [String: Data] = [:]
    }

    private struct State {
        var entries: [FileKey: Entry] = [:]
        var failingSetNames: Set<String> = []

        /// The live entry for the file at `path`. File systems reuse a freed inode for the next new file at
        /// once, and real attributes never carry over to it: if the path an entry was last seen at now holds a
        /// different inode, that file was replaced and its inode freed, so the entry is stale and dropped. A
        /// rename leaves the old path empty, so the entry follows the file.
        mutating func entry(_ key: FileKey, at path: String, key lookup: (String) -> FileKey?) -> Entry {
            if let found = entries[key] {
                let there = found.path == path ? key : lookup(found.path)
                if there == nil || there == key {
                    entries[key]?.path = path
                    return entries[key]!
                }
                entries[key] = nil
            }
            return Entry(path: path)
        }
    }
    private let state = Mutex(State())

    public init() {}

    /// Makes every later `setValue` for `name` throw.
    public func failSetting(_ name: String) {
        state.withLock { _ = $0.failingSetNames.insert(name) }
    }

    public func names(at url: URL) throws -> [String] {
        let key = try Self.fileKey(url)
        return state.withLock { $0.entry(key, at: url.path, key: Self.liveKey).values.keys.sorted() }
    }

    public func value(_ name: String, at url: URL) throws -> Data? {
        let key = try Self.fileKey(url)
        return state.withLock { $0.entry(key, at: url.path, key: Self.liveKey).values[name] }
    }

    public func setValue(_ value: Data, _ name: String, at url: URL) throws {
        let key = try Self.fileKey(url)
        try state.withLock {
            if $0.failingSetNames.contains(name) { throw InjectedFailure(name: name) }
            var entry = $0.entry(key, at: url.path, key: Self.liveKey)
            entry.values[name] = value
            $0.entries[key] = entry
        }
    }

    public func removeValue(_ name: String, at url: URL) throws {
        let key = try Self.fileKey(url)
        state.withLock {
            var entry = $0.entry(key, at: url.path, key: Self.liveKey)
            entry.values[name] = nil
            $0.entries[key] = entry
        }
    }

    /// The key of whatever is at `path` now, or nil if nothing is.
    private static func liveKey(_ path: String) -> FileKey? {
        try? fileKey(URL(fileURLWithPath: path))
    }

    private static func fileKey(_ url: URL) throws -> FileKey {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
            let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        else { throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path]) }
        return FileKey(device: device, inode: inode)
    }
}
