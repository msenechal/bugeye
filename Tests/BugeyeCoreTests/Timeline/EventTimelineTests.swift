import BugeyeCore
import Foundation
import Testing

@Suite struct TimelineKeyTests {
    @Test(arguments: [
        ("S", [TimelineModifier.cmd], "S"), ("s", [.cmd], "S"), ("C", [.ctrl], "C"), ("3", [.shift, .cmd], "3"),
        ("Return", [], "Return"), ("Left", [], "Left"), ("Space", [.cmd], "Space"), ("F12", [], "F12"),
        ("/", [.cmd], "/"), ("Escape", [.shift], "Escape"), ("A", [.opt, .cmd], "A"),
    ])
    func accepts(key: String, modifiers: [TimelineModifier], stored: String) throws {
        let timelineKey = try #require(TimelineKey(key: key, modifiers: Set(modifiers)))
        #expect(timelineKey.key == stored)
    }

    @Test(arguments: [
        ("A", [TimelineModifier]()), ("a", [.shift]), ("A", [.opt]), ("A", [.shift, .opt]), ("Space", []),
        ("Space", [.shift]), ("3", [.shift]), ("é", [.cmd]), ("SS", [.cmd]), ("", [.cmd]), ("F13", []),
        ("Enterprise", []), ("h", []),
    ])
    func refuses(key: String, modifiers: [TimelineModifier]) {
        #expect(TimelineKey(key: key, modifiers: Set(modifiers)) == nil)
    }

    @Test func modifiersAreInCtrlOptShiftCmdOrder() throws {
        let key = try #require(TimelineKey(key: "Z", modifiers: [.cmd, .shift, .opt, .ctrl]))
        #expect(key.modifiers == [.ctrl, .opt, .shift, .cmd])
    }
}

@Suite struct TimelineElementTests {
    @Test func aSecureElementHasNoTimelineElement() {
        let info = AXElementInfo(
            role: "AXTextField", subrole: "AXSecureTextField", title: "pw", text: nil, frame: .zero,
            isTextEntry: true, isSecure: true)
        #expect(TimelineElement(info: info, origin: .zero) == nil)
    }

    @Test func keepsRoleSubroleTitleAndARelativeFrameButNeverText() throws {
        let info = AXElementInfo(
            role: "AXStaticText", title: "Total", text: "secret static text",
            frame: Rect2D(x: 730, y: 110, width: 60, height: 24), isTextEntry: false)
        let element = try #require(TimelineElement(info: info, origin: Point2D(x: 120, y: 80)))
        #expect(element.role == "AXStaticText")
        #expect(element.title == "Total")
        #expect(element.frame == Rect2D(x: 610, y: 30, width: 60, height: 24))
        let line = TimelineLineEncoder.line(TimelineLine(t: 5, event: .element(click: 1, element)))
        #expect(!line.contains("secret"))
    }

    /// claude-review #4: a text field's title can be its typed value in some apps: never kept.
    @Test func aTextEntryElementKeepsNoTitle() throws {
        let info = AXElementInfo(
            role: "AXTextField", title: "Correct Horse", text: nil, frame: .zero, isTextEntry: true)
        let element = try #require(TimelineElement(info: info, origin: .zero))
        #expect(element.title == nil)
        #expect(element.role == "AXTextField")
    }

    @Test func titlesAreCutTo120CharactersWithAnEllipsis() {
        let long = String(repeating: "é", count: 200)
        let element = TimelineElement(role: "AXButton", subrole: nil, title: long, frame: .zero)!
        #expect(element.title?.count == 120)
        #expect(element.title?.hasSuffix("…") == true)
        let exact = String(repeating: "x", count: 120)
        #expect(TimelineElement(role: "AXButton", subrole: nil, title: exact, frame: .zero)!.title == exact)
    }
}

@Suite struct TimelineEncodingTests {
    private func line(_ t: Int, _ event: TimelineEvent) -> String {
        TimelineLineEncoder.line(TimelineLine(t: t, event: event))
    }

    @Test func everyKindMatchesTheSpec() throws {
        #expect(line(0, .move(Point2D(x: 402.5, y: 311))) == #"{"t":0,"k":"move","x":402.5,"y":311}"#)
        #expect(
            line(1450, .down(id: 1, button: .left, at: Point2D(x: 640, y: 42), clicks: 1))
                == #"{"t":1450,"k":"down","id":1,"b":"l","x":640,"y":42,"n":1}"#)
        #expect(
            line(1532, .up(id: 1, button: .left, at: Point2D(x: 640, y: 42)))
                == #"{"t":1532,"k":"up","id":1,"b":"l","x":640,"y":42}"#)
        let save = TimelineElement(
            role: "AXButton", subrole: nil, title: "Save", frame: Rect2D(x: 610, y: 30, width: 60, height: 24))!
        #expect(
            line(1450, .element(click: 1, save))
                == #"{"t":1450,"k":"element","click":1,"role":"AXButton","subrole":null,"title":"Save","frame":{"x":610,"y":30,"w":60,"h":24}}"#
        )
        #expect(
            line(2210, .elementStatus(click: 2, .withheld))
                == #"{"t":2210,"k":"element","click":2,"status":"withheld"}"#)
        #expect(
            line(3020, .scroll(at: Point2D(x: 700, y: 400), dx: 0, dy: -84))
                == #"{"t":3020,"k":"scroll","x":700,"y":400,"dx":0,"dy":-84}"#)
        let key = try #require(TimelineKey(key: "S", modifiers: [.cmd]))
        #expect(line(4100, .key(key)) == #"{"t":4100,"k":"key","key":"S","mods":["cmd"]}"#)
        #expect(
            line(
                5003,
                .focus(
                    app: "com.apple.Safari", name: "Safari", window: WindowID(4211),
                    frame: Rect2D(x: 0, y: -25, width: 1280, height: 800)))
                == #"{"t":5003,"k":"focus","app":"com.apple.Safari","name":"Safari","window":4211,"frame":{"x":0,"y":-25,"w":1280,"h":800}}"#
        )
        #expect(
            line(6000, .area(Rect2D(x: 140, y: 80, width: 1280, height: 720)))
                == #"{"t":6000,"k":"area","x":140,"y":80,"w":1280,"h":720}"#)
        #expect(line(7311, .pause) == #"{"t":7311,"k":"pause"}"#)
        #expect(line(7311, .resume) == #"{"t":7311,"k":"resume"}"#)
        #expect(line(9020, .trunc(.cursor)) == #"{"t":9020,"k":"trunc","reason":"cursor"}"#)
        #expect(line(12840, .end(events: 412)) == #"{"t":12840,"k":"end","events":412}"#)
    }

    @Test func coordinatesHaveOneDecimal() {
        #expect(line(0, .move(Point2D(x: 1.04, y: -2.36))) == #"{"t":0,"k":"move","x":1,"y":-2.4}"#)
        #expect(line(0, .move(Point2D(x: -0.04, y: .nan))) == #"{"t":0,"k":"move","x":0,"y":0}"#)
    }

    @Test func stringsAreEscaped() {
        let element = TimelineElement(role: "AXButton", subrole: nil, title: "a\"b\\c\nd\u{1}", frame: .zero)!
        #expect(line(0, .element(click: 1, element)).contains(#""title":"a\"b\\c\nd\u0001""#))
    }

    @Test func theHeaderMatchesTheSpec() throws {
        let header = TimelineHeader(
            take: try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")),
            startedAt: Date(timeIntervalSince1970: 1_795_788_192.481),
            target: TimelineHeader.Target(
                kind: .area, display: DisplayID(69_734_272), scale: 2, window: nil,
                area: Rect2D(x: 120, y: 80, width: 1280, height: 720)),
            video: TimelineHeader.Video(width: 2560, height: 1440, fps: 30), cursorHz: 30, hasKeys: true,
            hasElements: true)
        #expect(
            TimelineLineEncoder.header(header)
                == #"{"format":"dev.msenechal.bugeye.timeline","version":1,"take":"6f9619ff-8b86-d011-b42d-00c04fc964ff","startedAt":"2026-11-27T14:03:12.481Z","target":{"kind":"area","display":69734272,"scale":2,"window":null,"area":{"x":120,"y":80,"w":1280,"h":720}},"video":{"w":2560,"h":1440,"fps":30},"cursorHz":30,"has":{"keys":true,"elements":true}}"#
        )
    }
}

@Suite struct TimelineReaderTests {
    static let header = TimelineHeader(
        take: UUID(), startedAt: Date(timeIntervalSince1970: 1_795_788_192.481),
        target: TimelineHeader.Target(
            kind: .window, display: DisplayID(1), scale: 1, window: WindowID(9),
            area: Rect2D(x: 0, y: 25, width: 800, height: 600)),
        video: TimelineHeader.Video(width: 800, height: 600, fps: 60), cursorHz: 30, hasKeys: false,
        hasElements: true)

    private func file(_ lines: [String], trailingNewline: Bool = true) -> Data {
        Data(
            ([TimelineLineEncoder.header(Self.header)] + lines).joined(separator: "\n")
                .appending(trailingNewline ? "\n" : "").utf8)
    }

    @Test func everyKindRoundTrips() throws {
        let key = try #require(TimelineKey(key: "Z", modifiers: [.shift, .cmd]))
        let lines: [TimelineLine] = [
            TimelineLine(t: 0, event: .move(Point2D(x: 1.5, y: 2))),
            TimelineLine(t: 1, event: .down(id: 1, button: .right, at: Point2D(x: 3, y: 4), clicks: 2)),
            TimelineLine(t: 2, event: .up(id: 1, button: .right, at: Point2D(x: 3, y: 4))),
            TimelineLine(
                t: 1,
                event: .element(
                    click: 1,
                    TimelineElement(
                        role: "AXButton", subrole: "AXCloseButton", title: nil,
                        frame: Rect2D(x: 1, y: 2, width: 3, height: 4))!)),
            TimelineLine(t: 3, event: .elementStatus(click: 2, .timeout)),
            TimelineLine(t: 4, event: .scroll(at: Point2D(x: 5, y: 6), dx: 1.5, dy: -2)),
            TimelineLine(t: 5, event: .key(key)),
            TimelineLine(t: 6, event: .focus(app: "a.b", name: "B", window: nil, frame: nil)),
            TimelineLine(t: 7, event: .area(Rect2D(x: 1, y: 1, width: 2, height: 2))),
            TimelineLine(t: 8, event: .pause), TimelineLine(t: 8, event: .resume),
            TimelineLine(t: 9, event: .trunc(.size)), TimelineLine(t: 10, event: .end(events: 11)),
        ]
        let read = try TimelineReader.read(file(lines.map(TimelineLineEncoder.line)))
        #expect(read.header == Self.header)
        #expect(read.lines == lines)
    }

    @Test func aTypedKeyLineIsDroppedOnDecoding() throws {
        let read = try TimelineReader.read(
            file([#"{"t":1,"k":"key","key":"h","mods":[]}"#, #"{"t":2,"k":"key","key":"S","mods":["cmd"]}"#]))
        #expect(read.lines.count == 1)
        #expect(read.lines.first?.event == .key(try #require(TimelineKey(key: "S", modifiers: [.cmd]))))
    }

    @Test func elementDecodingNeverKeepsTextAndTrimsTitles() throws {
        let long = String(repeating: "x", count: 300)
        let read = try TimelineReader.read(
            file([
                #"{"t":1,"k":"element","click":1,"role":"AXButton","subrole":null,"title":"\#(long)","text":"typed","value":"typed","frame":{"x":0,"y":0,"w":1,"h":1}}"#
            ]))
        guard case .element(_, let element) = try #require(read.lines.first).event else {
            Issue.record("not an element")
            return
        }
        #expect(element.title?.count == 120)
    }

    @Test func unknownKindsAndKeysAreSkippedAndAPartialLastLineDropped() throws {
        let read = try TimelineReader.read(
            file(
                [
                    #"{"t":1,"k":"zoom","x":1}"#, #"{"t":2,"k":"move","x":1,"y":2,"extra":true}"#, "not json",
                    #"{"t":3,"k":"move","x":1"#,
                ], trailingNewline: false))
        #expect(read.lines == [TimelineLine(t: 2, event: .move(Point2D(x: 1, y: 2)))])
    }

    @Test func anUnknownVersionIsRefused() {
        let data = Data(#"{"format":"dev.msenechal.bugeye.timeline","version":2}"#.appending("\n").utf8)
        #expect(throws: TimelineReadError.unsupportedVersion(2)) { try TimelineReader.read(data) }
        #expect(throws: TimelineReadError.notATimeline) { try TimelineReader.read(Data("{}\n".utf8)) }
        #expect(throws: TimelineReadError.notATimeline) { try TimelineReader.read(Data()) }
    }

    @Test func storedByCaptureIdentity() throws {
        let id = try #require(CaptureID(string: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        #expect(
            EventTimeline.url(for: id, home: "/Users/m").path
                == "/Users/m/Library/Application Support/dev.msenechal.bugeye/Timelines/6f9619ff-8b86-d011-b42d-00c04fc964ff.timeline.jsonl"
        )
    }
}

@Suite struct TimelineSecureDecodingTests {
    /// claude-review #4 minor 1: a hand-written secure-field element line never keeps its title.
    @Test func aSecureSubroleLineDecodesAsWithheld() throws {
        #expect(
            TimelineElement(role: "AXTextField", subrole: "AXSecureTextField", title: "hunter2", frame: .zero) == nil)
        let header = TimelineReaderTests.header
        let line =
            #"{"t":1,"k":"element","click":1,"role":"AXTextField","subrole":"AXSecureTextField","title":"hunter2","frame":{"x":0,"y":0,"w":1,"h":1}}"#
        let data = Data((TimelineLineEncoder.header(header) + "\n" + line + "\n").utf8)
        #expect(try TimelineReader.read(data).lines == [TimelineLine(t: 1, event: .elementStatus(click: 1, .withheld))])
    }
}
