import BugeyeCore
import BugeyeTestSupport
import Foundation
import RecordingCore
import Testing

/// Spec §7.4 and V4: typed text never reaches the timeline, through the whole recorder and the file's bytes.
@Suite struct TimelinePrivacyTests {
    typealias T = TimelineTesting

    /// US key codes and unmodified characters for what the test types.
    static let keys: [Character: (code: UInt16, base: String, shifted: Bool)] = [
        "a": (0, "a", false), "b": (11, "b", false), "c": (8, "c", false), "e": (14, "e", false),
        "h": (4, "h", false), "n": (45, "n", false), "o": (31, "o", false), "r": (15, "r", false),
        "s": (1, "s", false), "t": (17, "t", false), "u": (32, "u", false), "y": (16, "y", false),
        "2": (19, "2", false), " ": (49, " ", false), "!": (18, "1", true),
        "C": (8, "c", true), "H": (4, "h", true), "B": (11, "b", true),
    ]

    static let passwordField = AXElementInfo(
        role: "AXTextField", subrole: "AXSecureTextField", title: "Password", text: "hunter2",
        frame: Rect2D(x: 200, y: 100, width: 200, height: 24), isTextEntry: true, isSecure: true)
    static let notesField = AXElementInfo(
        role: "AXTextField", title: "Notes", text: "Correct Horse Battery!",
        frame: Rect2D(x: 200, y: 300, width: 400, height: 24), isTextEntry: true)

    /// Types `text` with its own shift state plus `extra` modifiers, one press per character.
    private func type(
        _ text: String, extra: Set<TimelineModifier> = [], into recorder: TimelineRecorder, from ms: Int
    ) async -> Int {
        var t = ms
        for character in text {
            let key = Self.keys[character]!
            let modifiers = extra.union(key.shifted ? [.shift] : [])
            await recorder.record(
                .key(KeyPress(keyCode: key.code, characters: key.base, modifiers: modifiers)), at: T.at(t))
            t += 50
        }
        return t
    }

    @Test func typedTextNeverReachesTheTimeline() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let reader = FakeAXReader(elementsByProcess: [1: [Self.passwordField, Self.notesField]])
        // "Show all keystrokes" is on for the badge; the timeline has no such switch (its API takes none), so
        // the same presses go through the same recorder whatever the setting is.
        let (recorder, url) = try T.recorder(in: dir, reader: reader)

        // Click the secure field and type the password.
        await recorder.record(.down(.left, Point2D(x: 250, y: 110), clicks: 1), at: T.at(0))
        await recorder.record(.up(.left, Point2D(x: 250, y: 110)), at: T.at(40))
        await recorder.waitForLookup()
        var t = await type("hunter2", into: recorder, from: 100)

        // Click the text field and type the sentence plainly, with ⇧ and with ⌥.
        await recorder.record(.down(.left, Point2D(x: 250, y: 310), clicks: 1), at: T.at(t))
        await recorder.record(.up(.left, Point2D(x: 250, y: 310)), at: T.at(t + 40))
        await recorder.waitForLookup()
        t = await type("Correct Horse Battery!", into: recorder, from: t + 100)
        t = await type("Correct Horse Battery!", extra: [.shift], into: recorder, from: t)
        t = await type("Correct Horse Battery!", extra: [.opt], into: recorder, from: t)
        t = await type("Correct Horse Battery!", extra: [.shift, .opt], into: recorder, from: t)

        // Shortcuts and named keys.
        let shortcuts: [(UInt16, String, Set<TimelineModifier>)] = [
            (1, "s", [.cmd]), (8, "c", [.ctrl]), (20, "3", [.shift, .cmd]), (36, "\r", []), (123, "", []),
        ]
        for (code, characters, modifiers) in shortcuts {
            await recorder.record(
                .key(KeyPress(keyCode: code, characters: characters, modifiers: modifiers)), at: T.at(t))
            t += 50
        }
        _ = await recorder.finish(at: T.at(t + 100))

        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        for secret in ["hunter2", "hunter", "Correct", "Horse", "Battery", "orrect", "Password"] {
            #expect(!text.localizedCaseInsensitiveContains(secret), "found \(secret)")
        }
        let keyLines = text.split(separator: "\n").filter { $0.contains(#""k":"key""#) }
        #expect(
            keyLines == [
                #"{"t":\#(t - 250),"k":"key","key":"S","mods":["cmd"]}"#,
                #"{"t":\#(t - 200),"k":"key","key":"C","mods":["ctrl"]}"#,
                #"{"t":\#(t - 150),"k":"key","key":"3","mods":["shift","cmd"]}"#,
                #"{"t":\#(t - 100),"k":"key","key":"Return","mods":[]}"#,
                #"{"t":\#(t - 50),"k":"key","key":"Left","mods":[]}"#,
            ])
        let secureLine = try #require(text.split(separator: "\n").first { $0.contains(#""click":1"#) })
        #expect(secureLine == #"{"t":0,"k":"element","click":1,"status":"withheld"}"#)
        #expect(!secureLine.contains("title"))

        // A hand-written typed-text key line is dropped on reading.
        let tampered = data + Data(#"{"t":1,"k":"key","key":"h","mods":[]}"#.utf8) + Data("\n".utf8)
        let read = try TimelineReader.read(tampered)
        #expect(
            read.lines.compactMap { if case .key(let k) = $0.event { k.key } else { nil } } == [
                "S", "C", "3", "Return", "Left",
            ])
    }

    /// Every written key line obeys §7.4, checked against an oracle written independently of `TimelineKey`.
    @Test func randomPressesOnlyWriteShortcutsAndNamedKeys() async throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let (recorder, url) = try T.recorder(in: dir)
        var random = SplitMix64(seed: 0x5EED)
        let characters = Array("abcdefghijklmnopqrstuvwxyz0123456789`-=[]\\;',./ éüßфы&!@\r\t")
        let named: Set<String> = [
            "Return", "Enter", "Tab", "Delete", "ForwardDelete", "Escape", "Left", "Right", "Up", "Down", "Home",
            "End", "PageUp", "PageDown", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
        ]
        var expected: [String] = []
        for n in 0..<3000 {
            let code = UInt16(random.next() % 130)
            let character = characters[Int(random.next() % UInt64(characters.count))]
            var modifiers: Set<TimelineModifier> = []
            for modifier in TimelineModifier.allCases where random.next() % 3 == 0 { modifiers.insert(modifier) }
            let isRepeat = random.next() % 10 == 0
            let press = KeyPress(
                keyCode: code, characters: String(character), modifiers: modifiers, isRepeat: isRepeat)
            await recorder.record(.key(press), at: T.at(n))
            // Oracle.
            guard !isRepeat, let base = KeystrokeFormatter.baseKey(keyCode: code, characters: String(character))
            else { continue }
            let shortcut = modifiers.contains(.cmd) || modifiers.contains(.ctrl)
            let isCharacterKey =
                base.count == 1
                && "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789`-=[]\\;',./".contains(base)
            if named.contains(base) || (shortcut && (isCharacterKey || base == "Space")) {
                expected.append(base)
            }
        }
        _ = await recorder.finish(at: T.at(5000))
        let written = try T.lines(url).compactMap { line -> TimelineKey? in
            if case .key(let key) = line.event { key } else { nil }
        }
        #expect(written.map(\.key) == expected)
        #expect(!expected.isEmpty)
        for key in written where !named.contains(key.key) {
            #expect(key.modifiers.contains(.cmd) || key.modifiers.contains(.ctrl))
        }
    }
}

/// A small seeded generator, so the property test is the same on every run.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
