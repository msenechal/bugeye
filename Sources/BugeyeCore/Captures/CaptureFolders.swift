import Foundation

/// None of these creates a folder; callers use `SaveFolder.ensureExists`.
public enum CaptureFolders {
    /// Also the os.Logger subsystem.
    public static let bundleID = "dev.msenechal.bugeye"

    /// <home>/Library/Caches/dev.msenechal.bugeye/Captures/: unsaved captures; Capture's janitor purges it (C11).
    public static func temp(home: String) -> URL {
        caches(home).appendingPathComponent("Captures", isDirectory: true)
    }

    /// <home>/Library/Caches/dev.msenechal.bugeye/Recordings/: takes in progress; never purged.
    public static func recordingsInProgress(home: String) -> URL {
        caches(home).appendingPathComponent("Recordings", isDirectory: true)
    }

    /// <home>/Library/Application Support/dev.msenechal.bugeye/
    public static func applicationSupport(home: String) -> URL {
        URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
    }

    private static func caches(_ home: String) -> URL {
        URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Caches", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
    }
}
