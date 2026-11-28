import BugeyeCore
import Foundation

/// One thumbnail as the `quickAccess.stack` debug command reports it (contracts K23). File names only, never paths.
public struct QuickAccessStackRow: Hashable, Codable, Sendable {
    public var id: String
    public var file: String
    public var kind: String
    public var saved: Bool
    public var hovered: Bool
    public var selected: Bool
    public var editing: Bool
}

extension QuickAccessModel {
    /// The stack, oldest first.
    public func stackSnapshot() -> [QuickAccessStackRow] {
        entries.map { entry in
            QuickAccessStackRow(
                id: entry.id.description, file: entry.item.fileURL.lastPathComponent, kind: entry.item.kind.rawValue,
                saved: entry.item.isSaved, hovered: hovered == entry.id, selected: selection.contains(entry.id),
                editing: entry.isEditing)
        }
    }

    /// `stackSnapshot()` as one line of JSON, keys sorted.
    public func stackSnapshotJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(stackSnapshot()) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}
