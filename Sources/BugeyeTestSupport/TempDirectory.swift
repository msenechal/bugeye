import Foundation

/// A fresh, uniquely named folder for one test. Tests run in parallel: never share a folder.
public struct TempDirectory: Sendable {
    public let url: URL

    public init(_ label: String = "test") throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bugeye-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func file(_ name: String) -> URL {
        url.appendingPathComponent(name, isDirectory: false)
    }

    /// The names in the folder, sorted, hidden files included.
    public func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
