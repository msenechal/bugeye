/// Disk-space rules (spec §5.3, §5.6, V8). Decimal units, as Finder shows free space.
public enum DiskGuard {
    /// Starting needs 1 GB free on the in-progress folder's volume.
    public static let startBytes: Int64 = 1_000_000_000
    /// Below 300 MB (checked every 5 s) the recording stops and keeps what was recorded.
    public static let stopBytes: Int64 = 300_000_000
    /// Conversion needs the movie's size plus 50 MB.
    public static let convertMarginBytes: Int64 = 50_000_000

    public static func canStart(freeBytes: Int64) -> Bool { freeBytes >= startBytes }

    public static func mustStop(freeBytes: Int64) -> Bool { freeBytes < stopBytes }

    public static func canConvert(movieBytes: Int64, freeBytes: Int64) -> Bool {
        freeBytes >= movieBytes + convertMarginBytes
    }

    /// Seconds: 60 plus half the duration. A missed deadline delivers the .mov (V8).
    public static func conversionDeadline(duration: Double) -> Double {
        60 + max(duration, 0) / 2
    }
}
