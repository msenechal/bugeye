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
/// without them. `scripts/guards.sh` fails CI if `.atomic` or `replaceItemAt` appears anywhere else.
public struct CaptureFileWriter: Sendable {
    public static let attributePrefix = "dev.msenechal.bugeye."
    public static let identityAttribute = "dev.msenechal.bugeye.id"
    public static let whereFromsAttribute = "com.apple.metadata:kMDItemWhereFroms"

    public struct RenameFailed: Error, Equatable {
        public let errno: Int32
    }

    private let metadata: any FileMetadataStore

    public init(metadata: any FileMetadataStore) {
        self.metadata = metadata
    }

    /// Writes `data` to `url`.
    /// - Parameters:
    ///   - source: the previous version whose attributes are kept; defaults to `url` itself. A source that
    ///     doesn't exist (a first save) contributes nothing.
    ///   - identity: `.new(id)` replaces the ID attribute with `id`.
    public func write(_ data: Data, to url: URL, attributesFrom source: URL? = nil, identity: CaptureIdentity = .keep)
        throws
    {
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
            guard rename(temp.path, url.path) == 0 else { throw RenameFailed(errno: errno) }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    /// The attributes that survive a rewrite. Other attributes (quarantine, Finder tags) are not copied.
    public static func isPreserved(_ name: String) -> Bool {
        name.hasPrefix(attributePrefix) || name == whereFromsAttribute
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
