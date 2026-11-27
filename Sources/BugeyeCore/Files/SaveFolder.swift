import Foundation

/// The capture folder on disk.
public enum SaveFolder {
    /// Creates the folder (and its parents) if it's missing. Returns true when it had to create it.
    /// Throws if the path exists but is a file, or the folder can't be created.
    @discardableResult
    public static func ensureExists(at url: URL, fileManager: FileManager = .default) throws -> Bool {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: url.path])
            }
            return false
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return true
    }
}
