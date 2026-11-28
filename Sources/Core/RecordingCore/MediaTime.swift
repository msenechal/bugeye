/// One formatter for the ● timer and the ▶ badge (spec §3.1).
public enum MediaTime {
    /// "00:07", "12:34", "1:02:03" (h:mm:ss from one hour). Truncates to whole seconds; anything that isn't a
    /// finite, non-negative number reads "00:00".
    public static func text(seconds: Double) -> String {
        // Capped at 10⁹ s (31 years), so a huge value can't trap the conversion.
        let whole = seconds.isFinite && seconds > 0 ? Int(min(seconds, 1e9).rounded(.down)) : 0
        let hours = whole / 3600
        let minutes = whole % 3600 / 60
        let secs = whole % 60
        if hours > 0 { return "\(hours):\(two(minutes)):\(two(secs))" }
        return "\(two(minutes)):\(two(secs))"
    }

    private static func two(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
