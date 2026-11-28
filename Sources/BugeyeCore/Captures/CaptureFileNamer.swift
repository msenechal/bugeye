import Foundation

public enum CaptureFileNamer {
    /// "<namePrefix> YYYY-MM-DD at HH.MM.SS.<ext>", local time zone, en_US_POSIX, `ext` = `kind.fileExtension`
    /// unless given. "Screenshot 2026-11-27 at 14.03.12.png".
    public static func name(
        kind: CaptureKind, date: Date, fileExtension: String? = nil, timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(kind.namePrefix) \(formatter.string(from: date)).\(fileExtension ?? kind.fileExtension)"
    }

    /// Attempt 1: `name`. Attempt n ≥ 2: "<stem> (n).<ext>", stem = `name` without its last extension, as is.
    /// A name with no extension (or only a leading dot) gets the suffix at its end.
    public static func candidate(_ name: String, attempt: Int) -> String {
        guard attempt >= 2 else { return name }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "\(name) (\(attempt))" }
        return "\(name[..<dot]) (\(attempt))\(name[dot...])"
    }
}
