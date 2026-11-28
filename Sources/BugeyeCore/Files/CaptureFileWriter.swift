import Foundation

/// Whether a rewritten capture keeps its identity.
public enum CaptureIdentity: Hashable, Sendable {
    /// A rewrite of the same capture (editor save, downscale): every attribute comes back, the ID too.
    case keep
    /// A copy (Save As): the attributes come back, but the file gets this new ID.
    case new(CaptureID)
}

/// The only code allowed to write or rewrite a capture file (`design/README` "one choke point").
///
/// It writes a temp file next to the target, copies every `dev.msenechal.bugeye.*` attribute and
/// `com.apple.metadata:kMDItemWhereFroms` from the previous version onto it, then renames it over the
/// target. The rename is atomic and keeps the temp file's attributes, so the target never exists
/// without them. A rewrite also keeps the file's POSIX permissions. `scripts/guards.sh` fails CI if `.atomic`
/// or `replaceItemAt` appears anywhere else.
public struct CaptureFileWriter: Sendable {
    public static let attributePrefix = "dev.msenechal.bugeye."
    public static let identityAttribute = "dev.msenechal.bugeye.id"
    public static let whereFromsAttribute = "com.apple.metadata:kMDItemWhereFroms"

    /// The final rename failed. `errno` is for the log only: the description never shows it (K30, plan P14).
    public struct RenameFailed: Error, Equatable, LocalizedError {
        public let errno: Int32
        public init(errno: Int32) { self.errno = errno }
        public var errorDescription: String? { "The file couldn't be moved into place." }
    }

    /// `create` or `move` found every name from `name` to its 999th candidate taken.
    public struct NoFreeName: Error, Equatable, LocalizedError {
        public let name: String
        public init(name: String) { self.name = name }
        public var errorDescription: String? { "Too many files are already named like \u{201C}\(name)\u{201D}." }
    }

    /// `write(requireExisting: true)` found the target gone (moved or deleted meanwhile, K27).
    public struct TargetMissing: Error, Equatable, LocalizedError {
        public let url: URL
        public init(url: URL) { self.url = url }
        public var errorDescription: String? { "\u{201C}\(url.lastPathComponent)\u{201D} was moved or deleted." }
    }

    /// `copy` was asked to copy a file onto itself (the same path in another spelling, or a hard link to it).
    /// Nothing was changed. Callers treat it as "nothing to do"; it has no user-visible text (final review I3).
    public struct SameFile: Error, Equatable {
        public let url: URL
        public init(url: URL) { self.url = url }
    }

    /// How many names `create` and `move` try: `name`, then its candidates (2) … (999).
    public static let maxNameAttempts = 999

    private let metadata: any FileMetadataStore
    /// Test seam (plan P3): `move` takes its other-volume path as if the rename had failed with `EXDEV`.
    var simulateCrossVolume = false
    /// Test seams: the platform's atomic no-replace rename and exchange; nil uses the real one. Each returns 0 or
    /// an errno; `ENOTSUP` or `EINVAL` makes the writer fall back (final review I2).
    var nativeNoReplace: (@Sendable (String, String) -> Int32)?
    var nativeSwap: (@Sendable (String, String) -> Int32)?

    public init(metadata: any FileMetadataStore) {
        self.metadata = metadata
    }

    /// Writes `data` to `url`.
    /// - Parameters:
    ///   - source: the previous version whose attributes are kept; defaults to `url` itself. A source that
    ///     doesn't exist (a first save) contributes nothing.
    ///   - identity: `.new(id)` replaces the ID attribute with `id`.
    ///   - requireExisting: with true, the final step replaces `url` only if it still exists: an exchange
    ///     (`renameatx_np(RENAME_SWAP)` on macOS; a check-then-rename on Linux, plan P2), then the swapped-out old
    ///     file is removed. If `url` is gone it throws `TargetMissing` and removes its temp file, so a capture moved
    ///     or deleted meanwhile is never recreated at its old path (K27). False is Wave 0's behaviour.
    public func write(
        _ data: Data, to url: URL, attributesFrom source: URL? = nil, identity: CaptureIdentity = .keep,
        requireExisting: Bool = false
    ) throws {
        var kept = try preservedAttributes(of: source ?? url)
        if case .new(let id) = identity {
            kept[Self.identityAttribute] = Data(id.description.utf8)
        }

        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp", isDirectory: false)
        do {
            try data.write(to: temp, options: .withoutOverwriting)
            for (name, value) in kept.sorted(by: { $0.key < $1.key }) {
                try metadata.setValue(value, name, at: temp)
            }
            // A rewrite keeps the file's permissions: the temp file starts at the umask's default.
            if let mode = try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] {
                try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: temp.path)
            }
            if requireExisting {
                let code = replaceExisting(temp.path, with: url.path)
                if code == ENOENT { throw TargetMissing(url: url) }
                guard code == 0 else { throw RenameFailed(errno: code) }
            } else {
                guard rename(temp.path, url.path) == 0 else { throw RenameFailed(errno: errno) }
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    /// Copies `source` to `destination` without reading it into memory (K28): a copy to a temp name beside
    /// `destination`, the preserved attributes (P11) and `identity` set on it, then a rename over `destination`.
    /// Replacing is allowed (the save panel already asked), except the source itself: that throws `SameFile`. The
    /// source is never changed; on failure no temp file remains.
    public func copy(_ source: URL, to destination: URL, identity: CaptureIdentity) throws {
        if Self.isSameFile(source, destination) { throw SameFile(url: destination) }
        var kept = try preservedAttributes(of: source)
        if case .new(let id) = identity {
            kept[Self.identityAttribute] = Data(id.description.utf8)
        }
        let temp = Self.tempURL(in: destination.deletingLastPathComponent())
        do {
            try copyCarrying(kept, from: source, to: temp)
            guard rename(temp.path, destination.path) == 0 else { throw RenameFailed(errno: errno) }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    /// Writes a new capture file into `folder`, trying `name`, then `CaptureFileNamer.candidate(name, attempt: 2…999)`,
    /// never replacing a file. The identity attribute is set before the file appears under its final name.
    /// Returns the final URL. Throws `NoFreeName` after 999 attempts; on any failure no file or temp file remains.
    public func create(_ data: Data, named name: String, in folder: URL, identity: CaptureID) throws -> URL {
        let temp = Self.tempURL(in: folder)
        do {
            try data.write(to: temp, options: .withoutOverwriting)
            try metadata.setValue(Data(identity.description.utf8), Self.identityAttribute, at: temp)
            return try placeWithoutReplacing(temp, in: folder, named: name)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    /// Moves an existing file into `folder` under `name` (default: its own file name), with the same clash rule.
    /// `.keep` keeps every attribute; `.new(id)` writes `id` as the identity (onto the source first).
    /// Same volume: a no-replace rename, so every attribute follows. Another volume (`EXDEV`): a copy carrying the
    /// preserved attributes (P11) to a temp name in `folder`, a no-replace rename, then the source is removed.
    /// Returns the final URL. On failure the source is still there and no partial file remains in `folder`.
    public func move(_ source: URL, into folder: URL, named name: String? = nil, identity: CaptureIdentity = .keep)
        throws -> URL
    {
        let name = name ?? source.lastPathComponent
        if case .new(let id) = identity {
            try metadata.setValue(Data(id.description.utf8), Self.identityAttribute, at: source)
        }
        if !simulateCrossVolume {
            switch try renameWithoutReplacing(source, in: folder, named: name) {
            case .placed(let url): return url
            case .otherVolume: break
            }
        }

        let temp = Self.tempURL(in: folder)
        let placed: URL
        do {
            try copyCarrying(try preservedAttributes(of: source), from: source, to: temp)
            placed = try placeWithoutReplacing(temp, in: folder, named: name)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
        do {
            try FileManager.default.removeItem(at: source)
        } catch {
            // Never leave two copies of one capture: undo the placement, keep the source.
            try? FileManager.default.removeItem(at: placed)
            throw error
        }
        return placed
    }

    /// The attributes that survive a rewrite. Other attributes (quarantine, Finder tags) are not copied.
    public static func isPreserved(_ name: String) -> Bool {
        name.hasPrefix(attributePrefix) || name == whereFromsAttribute
    }

    /// The same path once standardized and symlinks resolved, or the same device and inode.
    static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        if a.standardizedFileURL.resolvingSymlinksInPath().path == b.standardizedFileURL.resolvingSymlinksInPath().path
        {
            return true
        }
        let manager = FileManager.default
        guard let x = try? manager.attributesOfItem(atPath: a.path),
            let y = try? manager.attributesOfItem(atPath: b.path),
            let xDevice = x[.systemNumber] as? NSNumber, let yDevice = y[.systemNumber] as? NSNumber,
            let xInode = x[.systemFileNumber] as? NSNumber, let yInode = y[.systemFileNumber] as? NSNumber
        else { return false }
        return xDevice == yDevice && xInode == yInode
    }

    /// A hidden temp name in `folder`, short so long capture names still fit (backlog M3).
    private static func tempURL(in folder: URL) -> URL {
        folder.appendingPathComponent(".bugeye-\(UUID().uuidString).tmp", isDirectory: false)
    }

    /// Copies `source` to `temp` (streamed, never read into memory) and leaves exactly `kept` as its preserved
    /// attributes: `FileManager` copies every xattr on macOS and none on Linux, so anything not preserved is
    /// removed and `kept` is set (plan P4).
    private func copyCarrying(_ kept: [String: Data], from source: URL, to temp: URL) throws {
        try FileManager.default.copyItem(at: source, to: temp)
        for name in try metadata.names(at: temp) where !Self.isPreserved(name) || kept[name] == nil {
            try metadata.removeValue(name, at: temp)
        }
        for (name, value) in kept.sorted(by: { $0.key < $1.key }) {
            try metadata.setValue(value, name, at: temp)
        }
    }

    /// Renames `temp` to the first free candidate of `name` in `folder`, never replacing a file.
    private func placeWithoutReplacing(_ temp: URL, in folder: URL, named name: String) throws -> URL {
        switch try renameWithoutReplacing(temp, in: folder, named: name) {
        case .placed(let url): return url
        case .otherVolume: throw RenameFailed(errno: EXDEV)
        }
    }

    private enum Placement {
        case placed(URL)
        case otherVolume
    }

    private func renameWithoutReplacing(_ file: URL, in folder: URL, named name: String) throws -> Placement {
        for attempt in 1...Self.maxNameAttempts {
            let target = folder.appendingPathComponent(CaptureFileNamer.candidate(name, attempt: attempt))
            let code = renameNoReplace(file.path, target.path)
            switch code {
            case 0: return .placed(target)
            case EEXIST: continue
            case EXDEV: return .otherVolume
            default: throw RenameFailed(errno: code)
            }
        }
        throw NoFreeName(name: name)
    }

    /// Renames `from` to `to` only if nothing is at `to`. Returns 0 or the errno (`EEXIST` on a clash).
    /// macOS: `renameatx_np(RENAME_EXCL)`; Linux: `link(2)` then `unlink(2)` (plan P2). A volume without the
    /// primitive (exFAT, SMB, NFS answer `ENOTSUP` or `EINVAL`) falls back to a check-then-rename, which can race
    /// with another writer in the instant between the two calls (final review I2).
    private func renameNoReplace(_ from: String, _ to: String) -> Int32 {
        let code = (nativeNoReplace ?? Self.platformNoReplace)(from, to)
        guard code == ENOTSUP || code == EINVAL else { return code }
        if access(to, F_OK) == 0 { return EEXIST }
        return rename(from, to) == 0 ? 0 : errno
    }

    /// Replaces `target` with `temp` only if `target` exists. Returns 0, `ENOENT` when it's gone, or the errno.
    /// macOS: `renameatx_np(RENAME_SWAP)`, then the swapped-out old file (now at `temp`) is removed. Without the
    /// primitive (Linux, or a volume answering `ENOTSUP` / `EINVAL`): a check-then-rename.
    private func replaceExisting(_ temp: String, with target: String) -> Int32 {
        let code = (nativeSwap ?? Self.platformSwap)(temp, target)
        if code == 0 {
            // `temp` now names the old file. Never leave it behind silently (final review M2).
            if unlink(temp) != 0 { try? FileManager.default.removeItem(atPath: temp) }
            return 0
        }
        guard code == ENOTSUP || code == EINVAL else { return code }
        guard access(target, F_OK) == 0 else { return ENOENT }
        return rename(temp, target) == 0 ? 0 : errno
    }

    private static let platformNoReplace: @Sendable (String, String) -> Int32 = { from, to in
        #if canImport(Darwin)
            return renameatx_np(AT_FDCWD, from, AT_FDCWD, to, UInt32(RENAME_EXCL)) == 0 ? 0 : errno
        #else
            guard link(from, to) == 0 else { return errno }
            guard unlink(from) == 0 else {
                let code = errno
                unlink(to)
                return code
            }
            return 0
        #endif
    }

    private static let platformSwap: @Sendable (String, String) -> Int32 = { temp, target in
        #if canImport(Darwin)
            return renameatx_np(AT_FDCWD, temp, AT_FDCWD, target, UInt32(RENAME_SWAP)) == 0 ? 0 : errno
        #else
            return ENOTSUP
        #endif
    }

    private func preservedAttributes(of url: URL) throws -> [String: Data] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        var kept: [String: Data] = [:]
        for name in try metadata.names(at: url) where Self.isPreserved(name) {
            if let value = try metadata.value(name, at: url) { kept[name] = value }
        }
        return kept
    }
}
