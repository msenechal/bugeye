import Foundation

// The event timeline recorded beside every recording (Recording spec §7). Recording-owned in Wave 1; in
// BugeyeCore because MotionCore (Wave 3) and GuideCore (Wave 4) read it.
//
// Privacy (V4): typed text can't be represented. `TimelineKey`'s only initializer refuses a press that isn't a
// shortcut or a non-text key; `TimelineElement` has no text and no instance for a secure field. Decoding re-runs
// the same initializers.

public enum EventTimeline {
    public static let format = "dev.msenechal.bugeye.timeline"
    public static let version = 1
    /// The file name suffix, after the take or capture id.
    public static let fileSuffix = ".timeline.jsonl"

    /// <home>/Library/Application Support/dev.msenechal.bugeye/Timelines/<id>.timeline.jsonl (V5).
    public static func url(for id: CaptureID, home: String) -> URL {
        folder(home: home).appendingPathComponent(id.description + fileSuffix, isDirectory: false)
    }

    /// <home>/Library/Application Support/dev.msenechal.bugeye/Timelines/
    public static func folder(home: String) -> URL {
        CaptureFolders.applicationSupport(home: home).appendingPathComponent("Timelines", isDirectory: true)
    }
}

// MARK: Keys

public enum TimelineModifier: String, Hashable, Sendable, CaseIterable, Comparable {
    case ctrl, opt, shift, cmd

    public static func < (a: TimelineModifier, b: TimelineModifier) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// A key press the timeline may hold (spec §7.4): a character key with ⌘ or ⌃, a named key with any modifiers,
/// or Space with ⌘ or ⌃. ⇧- and ⌥-letters are typing and have no `TimelineKey`.
public struct TimelineKey: Hashable, Sendable {
    /// The base key: an uppercase letter, a digit, a punctuation character, or a name ("Return", "F1", "Space").
    public let key: String
    /// Sorted ctrl, opt, shift, cmd.
    public let modifiers: [TimelineModifier]

    public static let namedKeys: Set<String> = Set(
        [
            "Return", "Enter", "Tab", "Delete", "ForwardDelete", "Escape", "Left", "Right", "Up", "Down", "Home",
            "End", "PageUp", "PageDown",
        ] + (1...12).map { "F\($0)" })

    /// A–Z, 0–9 and `` ` - = [ ] \ ; ' , . / ``.
    public static let characterKeys: Set<String> = Set(
        (UnicodeScalar("A").value...UnicodeScalar("Z").value).map { String(UnicodeScalar($0)!) }
            + (0...9).map(String.init) + ["`", "-", "=", "[", "]", "\\", ";", "'", ",", ".", "/"])

    /// `key` is the base key (a lowercase letter is accepted and stored uppercase). Nil unless §7.4 holds.
    public init?(key: String, modifiers: Set<TimelineModifier>) {
        let isShortcut = modifiers.contains(.cmd) || modifiers.contains(.ctrl)
        let character = key.count == 1 && key.unicodeScalars.allSatisfy(\.isASCII) ? key.uppercased() : key
        if Self.namedKeys.contains(key) {
            self.key = key
        } else if Self.characterKeys.contains(character), isShortcut {
            self.key = character
        } else if key == "Space", isShortcut {
            self.key = key
        } else {
            return nil
        }
        self.modifiers = modifiers.sorted()
    }
}

// MARK: Elements

/// The Accessibility element under a click: role, subrole, title and frame. Never a value or static text.
public struct TimelineElement: Hashable, Sendable {
    public static let maxTitleLength = 120

    public let role: String
    public let subrole: String?
    /// At most 120 characters, ending in "…" when cut.
    public let title: String?
    /// Points, relative to the recorded area's top-left at the click.
    public let frame: Rect2D

    /// Ignores `info.text`. Nil for a secure element (written as `withheld`).
    public init?(info: AXElementInfo, origin: Point2D) {
        guard !info.isSecure else { return nil }
        let frame = Rect2D(
            x: info.frame.origin.x - origin.x, y: info.frame.origin.y - origin.y, width: info.frame.size.width,
            height: info.frame.size.height)
        self.init(role: info.role, subrole: info.subrole, title: info.title, frame: frame)
    }

    public init(role: String, subrole: String?, title: String?, frame: Rect2D) {
        self.role = role
        self.subrole = subrole
        self.title = title.map { title in
            title.count <= Self.maxTitleLength ? title : String(title.prefix(Self.maxTitleLength - 1)) + "…"
        }
        self.frame = frame
    }
}

// MARK: Lines

public enum TimelineButton: String, Hashable, Sendable {
    case left = "l"
    case right = "r"
    case other = "o"
}

public enum TimelineElementStatus: String, Hashable, Sendable {
    /// A secure field.
    case withheld
    /// Nothing there, or no Accessibility.
    case none
    /// The lookup took over 250 ms.
    case timeout
    /// A lookup was already in flight.
    case skipped
}

public enum TimelineTruncation: String, Hashable, Sendable { case cursor, size }

public enum TimelineEvent: Hashable, Sendable {
    case move(Point2D)
    case down(id: Int, button: TimelineButton, at: Point2D, clicks: Int)
    case up(id: Int, button: TimelineButton, at: Point2D)
    case element(click: Int, TimelineElement)
    case elementStatus(click: Int, TimelineElementStatus)
    /// Deltas in points.
    case scroll(at: Point2D, dx: Double, dy: Double)
    case key(TimelineKey)
    /// No window title, ever (V14).
    case focus(app: String, name: String, window: WindowID?, frame: Rect2D?)
    /// Quartz global points: a followed window moved.
    case area(Rect2D)
    case pause
    case resume
    case trunc(TimelineTruncation)
    /// `t` is the duration; `events` the number of event lines before it.
    case end(events: Int)
}

/// One event line. `t` is integer milliseconds of video time (V6).
public struct TimelineLine: Hashable, Sendable {
    public var t: Int
    public var event: TimelineEvent

    public init(t: Int, event: TimelineEvent) {
        self.t = t
        self.event = event
    }
}

/// Line 1 of a timeline.
public struct TimelineHeader: Hashable, Sendable {
    public struct Target: Hashable, Sendable {
        public enum Kind: String, Hashable, Sendable { case area, display, window }

        public var kind: Kind
        public var display: DisplayID
        public var scale: Double
        public var window: WindowID?
        /// Quartz global points.
        public var area: Rect2D

        public init(kind: Kind, display: DisplayID, scale: Double, window: WindowID?, area: Rect2D) {
            self.kind = kind
            self.display = display
            self.scale = scale
            self.window = window
            self.area = area
        }
    }

    public struct Video: Hashable, Sendable {
        public var width: Int
        public var height: Int
        public var fps: Int

        public init(width: Int, height: Int, fps: Int) {
            self.width = width
            self.height = height
            self.fps = fps
        }
    }

    public var take: UUID
    /// The first frame's wall clock; written in UTC with milliseconds.
    public var startedAt: Date
    public var target: Target
    public var video: Video
    public var cursorHz: Int
    /// False without Accessibility, so readers can tell "no shortcuts" from "not watched".
    public var hasKeys: Bool
    public var hasElements: Bool

    public init(
        take: UUID, startedAt: Date, target: Target, video: Video, cursorHz: Int, hasKeys: Bool, hasElements: Bool
    ) {
        self.take = take
        self.startedAt = startedAt
        self.target = target
        self.video = video
        self.cursorHz = cursorHz
        self.hasKeys = hasKeys
        self.hasElements = hasElements
    }
}

// MARK: Encoding

/// Encodes lines as JSON with the keys in the spec's order (§7.2), without the trailing newline.
public enum TimelineLineEncoder {
    public static func header(_ header: TimelineHeader) -> String {
        let target = header.target
        let fields: [(String, String)] = [
            ("format", string(EventTimeline.format)),
            ("version", String(EventTimeline.version)),
            ("take", string(header.take.uuidString.lowercased())),
            ("startedAt", string(iso8601(header.startedAt))),
            (
                "target",
                object([
                    ("kind", string(target.kind.rawValue)),
                    ("display", String(target.display.rawValue)),
                    ("scale", number(target.scale)),
                    ("window", target.window.map { String($0.rawValue) } ?? "null"),
                    ("area", rect(target.area)),
                ])
            ),
            (
                "video",
                object([
                    ("w", String(header.video.width)), ("h", String(header.video.height)),
                    ("fps", String(header.video.fps)),
                ])
            ),
            ("cursorHz", String(header.cursorHz)),
            ("has", object([("keys", String(header.hasKeys)), ("elements", String(header.hasElements))])),
        ]
        return object(fields)
    }

    public static func line(_ line: TimelineLine) -> String {
        var fields: [(String, String)] = [("t", String(line.t))]
        func kind(_ k: String) { fields.append(("k", string(k))) }
        func point(_ p: Point2D) { fields += [("x", number(p.x)), ("y", number(p.y))] }
        switch line.event {
        case .move(let p):
            kind("move")
            point(p)
        case .down(let id, let button, let p, let clicks):
            kind("down")
            fields += [("id", String(id)), ("b", string(button.rawValue))]
            point(p)
            fields.append(("n", String(clicks)))
        case .up(let id, let button, let p):
            kind("up")
            fields += [("id", String(id)), ("b", string(button.rawValue))]
            point(p)
        case .element(let click, let element):
            kind("element")
            fields += [
                ("click", String(click)), ("role", string(element.role)),
                ("subrole", element.subrole.map(string) ?? "null"), ("title", element.title.map(string) ?? "null"),
                ("frame", rect(element.frame)),
            ]
        case .elementStatus(let click, let status):
            kind("element")
            fields += [("click", String(click)), ("status", string(status.rawValue))]
        case .scroll(let p, let dx, let dy):
            kind("scroll")
            point(p)
            fields += [("dx", number(dx)), ("dy", number(dy))]
        case .key(let key):
            kind("key")
            fields += [
                ("key", string(key.key)),
                ("mods", "[" + key.modifiers.map { string($0.rawValue) }.joined(separator: ",") + "]"),
            ]
        case .focus(let app, let name, let window, let frame):
            kind("focus")
            fields += [
                ("app", string(app)), ("name", string(name)),
                ("window", window.map { String($0.rawValue) } ?? "null"), ("frame", frame.map(rect) ?? "null"),
            ]
        case .area(let r):
            kind("area")
            fields += rectFields(r)
        case .pause: kind("pause")
        case .resume: kind("resume")
        case .trunc(let reason):
            kind("trunc")
            fields.append(("reason", string(reason.rawValue)))
        case .end(let events):
            kind("end")
            fields.append(("events", String(events)))
        }
        return object(fields)
    }

    /// One decimal, no trailing ".0", no "-0"; anything not finite is 0.
    static func number(_ value: Double) -> String {
        guard value.isFinite, abs(value) < 1e15 else { return "0" }
        let tenths = Int((value * 10).rounded())
        if tenths == 0 { return "0" }
        let sign = tenths < 0 ? "-" : ""
        let whole = abs(tenths) / 10
        let fraction = abs(tenths) % 10
        return fraction == 0 ? "\(sign)\(whole)" : "\(sign)\(whole).\(fraction)"
    }

    static func string(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case let s where s.value < 0x20:
                let hex = String(s.value, radix: 16)
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    private static func rectFields(_ r: Rect2D) -> [(String, String)] {
        [
            ("x", number(r.origin.x)), ("y", number(r.origin.y)), ("w", number(r.size.width)),
            ("h", number(r.size.height)),
        ]
    }

    private static func rect(_ r: Rect2D) -> String { object(rectFields(r)) }

    private static func object(_ fields: [(String, String)]) -> String {
        "{" + fields.map { string($0.0) + ":" + $0.1 }.joined(separator: ",") + "}"
    }

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    static func date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}

// MARK: Decoding

public enum TimelineReadError: Error, Hashable, Sendable {
    /// Line 1 isn't a timeline header.
    case notATimeline
    case unsupportedVersion(Int)
}

public struct TimelineFile: Hashable, Sendable {
    public var header: TimelineHeader
    public var lines: [TimelineLine]
}

/// Reads a timeline: skips unknown kinds, unknown keys and lines it can't parse, refuses a version it doesn't
/// know, drops a partial last line (a crash mid-append), and re-runs the type initializers, so a hand-written
/// typed-text key line is dropped.
public enum TimelineReader {
    public static func read(_ data: Data) throws -> TimelineFile {
        var chunks = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        // The last chunk is empty after a final newline, else a partial line: either way it isn't a line.
        if !chunks.isEmpty { chunks.removeLast() }
        guard let first = chunks.first, let header = try parseHeader(Data(first)) else {
            throw TimelineReadError.notATimeline
        }
        let lines = chunks.dropFirst().compactMap { chunk -> TimelineLine? in
            guard let object = json(Data(chunk)) else { return nil }
            return parseLine(object)
        }
        return TimelineFile(header: header, lines: lines)
    }

    private static func json(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func parseHeader(_ data: Data) throws -> TimelineHeader? {
        guard let object = json(data), object["format"] as? String == EventTimeline.format,
            let version = int(object["version"])
        else { return nil }
        guard version == EventTimeline.version else { throw TimelineReadError.unsupportedVersion(version) }
        guard let take = (object["take"] as? String).flatMap(UUID.init(uuidString:)),
            let startedAt = (object["startedAt"] as? String).flatMap(TimelineLineEncoder.date),
            let target = object["target"] as? [String: Any],
            let kind = (target["kind"] as? String).flatMap(TimelineHeader.Target.Kind.init(rawValue:)),
            let display = int(target["display"]), let scale = double(target["scale"]),
            let area = rect(target["area"]),
            let video = object["video"] as? [String: Any], let width = int(video["w"]),
            let height = int(video["h"]), let fps = int(video["fps"]),
            let cursorHz = int(object["cursorHz"]),
            let has = object["has"] as? [String: Any], let keys = bool(has["keys"]),
            let elements = bool(has["elements"])
        else { return nil }
        let window = int(target["window"]).map { WindowID(UInt32(truncatingIfNeeded: $0)) }
        return TimelineHeader(
            take: take, startedAt: startedAt,
            target: TimelineHeader.Target(
                kind: kind, display: DisplayID(UInt32(truncatingIfNeeded: display)), scale: scale, window: window,
                area: area),
            video: TimelineHeader.Video(width: width, height: height, fps: fps), cursorHz: cursorHz,
            hasKeys: keys, hasElements: elements)
    }

    private static func parseLine(_ o: [String: Any]) -> TimelineLine? {
        guard let t = int(o["t"]), let k = o["k"] as? String else { return nil }
        let event: TimelineEvent?
        let p = point(o)
        switch k {
        case "move": event = p.map { .move($0) }
        case "down":
            event = zip4(int(o["id"]), button(o["b"]), p, int(o["n"])).map {
                .down(id: $0.0, button: $0.1, at: $0.2, clicks: $0.3)
            }
        case "up":
            if let id = int(o["id"]), let b = button(o["b"]), let p {
                event = .up(id: id, button: b, at: p)
            } else {
                event = nil
            }
        case "element":
            guard let click = int(o["click"]) else { return nil }
            if let status = o["status"] as? String {
                event = TimelineElementStatus(rawValue: status).map { .elementStatus(click: click, $0) }
            } else if let role = o["role"] as? String, let frame = rect(o["frame"]) {
                let element = TimelineElement(
                    role: role, subrole: o["subrole"] as? String, title: o["title"] as? String, frame: frame)
                event = .element(click: click, element)
            } else {
                event = nil
            }
        case "scroll":
            if let p, let dx = double(o["dx"]), let dy = double(o["dy"]) {
                event = .scroll(at: p, dx: dx, dy: dy)
            } else {
                event = nil
            }
        case "key":
            guard let key = o["key"] as? String, let mods = o["mods"] as? [String] else { return nil }
            let modifiers = mods.compactMap(TimelineModifier.init(rawValue:))
            guard modifiers.count == mods.count else { return nil }
            event = TimelineKey(key: key, modifiers: Set(modifiers)).map { .key($0) }
        case "focus":
            guard let app = o["app"] as? String, let name = o["name"] as? String else { return nil }
            event = .focus(
                app: app, name: name, window: int(o["window"]).map { WindowID(UInt32(truncatingIfNeeded: $0)) },
                frame: rect(o["frame"]))
        case "area": event = rect(o).map { .area($0) }
        case "pause": event = .pause
        case "resume": event = .resume
        case "trunc": event = (o["reason"] as? String).flatMap(TimelineTruncation.init(rawValue:)).map { .trunc($0) }
        case "end": event = int(o["events"]).map { .end(events: $0) }
        default: event = nil
        }
        return event.map { TimelineLine(t: t, event: $0) }
    }

    private static func zip4<A, B, C, D>(_ a: A?, _ b: B?, _ c: C?, _ d: D?) -> (A, B, C, D)? {
        guard let a, let b, let c, let d else { return nil }
        return (a, b, c, d)
    }

    private static func button(_ value: Any?) -> TimelineButton? {
        (value as? String).flatMap(TimelineButton.init(rawValue:))
    }

    private static func point(_ o: [String: Any]) -> Point2D? {
        guard let x = double(o["x"]), let y = double(o["y"]) else { return nil }
        return Point2D(x: x, y: y)
    }

    private static func rect(_ value: Any?) -> Rect2D? {
        guard let o = value as? [String: Any], let x = double(o["x"]), let y = double(o["y"]),
            let w = double(o["w"]), let h = double(o["h"])
        else { return nil }
        return Rect2D(x: x, y: y, width: w, height: h)
    }

    private static func double(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, !isBoolean(number) else { return nil }
        return number.doubleValue
    }

    private static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, isBoolean(number) else { return nil }
        return number.boolValue
    }

    /// JSON `true` / `false` (a `char` NSNumber on both platforms; `is Bool` also matches 0 and 1 on Linux).
    private static func isBoolean(_ number: NSNumber) -> Bool {
        String(cString: number.objCType) == "c"
    }

    private static func int(_ value: Any?) -> Int? {
        guard let number = double(value), number.rounded() == number, abs(number) < 1e15 else { return nil }
        return Int(number)
    }
}
