import BugeyeCore
import BugeyeTestSupport
import EditorCore
import Foundation
import Testing

@Suite struct EditorRendererTests {
    static let image = Size2D(width: 400, height: 300)
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
    static func metrics(_ ppp: Double) -> EditorMetrics { EditorMetrics(ppp: ppp, measurer: FakeTextMeasurer()) }

    static func lists(
        _ state: EditorState, ppp: Double = 1, active: UUID? = nil, hidden: UUID? = nil, selection: UUID? = nil,
        cropMode: Bool = false, zoom: Double = 1
    ) -> EditorLists {
        let layout = CanvasLayout(imageSize: image, state: state, pixelsPerPoint: ppp, showingFullImage: cropMode)
        return EditorRenderer.lists(
            state: state, layout: layout, metrics: metrics(ppp), active: active, hidden: hidden, selection: selection,
            cropMode: cropMode, zoom: zoom)
    }

    /// Compares with `Fixtures/<name>.json` as values (so JSON formatting can't differ between platforms).
    /// `BUGEYE_RECORD_GOLDENS=1` rewrites the file in the source tree instead.
    static func checkGolden(_ list: DisplayList, _ name: String) throws {
        #expect(list.isBalanced)
        let json = try list.goldenJSON()
        if ProcessInfo.processInfo.environment["BUGEYE_RECORD_GOLDENS"] == "1" {
            let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/\(name).json")
            try Data((json + "\n").utf8).write(to: url)
            return
        }
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        let golden = try JSONDecoder().decode(DisplayList.self, from: Data(contentsOf: url))
        #expect(golden == list, "golden \(name) differs; produced:\n\(json)")
    }

    // MARK: Maths

    @Test func anArrowsHeadAndShaft() {
        let state = EditorState(annotations: [
            Annotation(id: Self.id(1), shape: .arrow(from: Point2D(x: 0, y: 0), to: Point2D(x: 100, y: 0)))
        ])
        let commands = Self.lists(state).base.commands
        // width 4, head = max(14, 12) = 14, half-width 6.3, shaft ends 0.7 × 14 = 9.8 before the tip
        #expect(
            commands.contains(
                .strokePath(
                    VectorPath([.move(to: .zero), .line(to: Point2D(x: 90.2, y: 0))]), color: EditorPalette.red,
                    lineWidth: 4, cap: .round, join: .round)))
        #expect(
            commands.contains(
                .fillPath(
                    VectorPath([
                        .move(to: Point2D(x: 100, y: 0)), .line(to: Point2D(x: 86, y: 6.3)),
                        .line(to: Point2D(x: 86, y: -6.3)), .close,
                    ]), color: EditorPalette.red)))
    }

    @Test func aShortArrowsHeadIsItsLength() {
        let state = EditorState(annotations: [
            Annotation(shape: .arrow(from: Point2D(x: 0, y: 0), to: Point2D(x: 10, y: 0)))
        ])
        #expect(
            Self.lists(state, ppp: 2).base.commands.contains {
                if case .fillPath(let path, _) = $0 {
                    path.elements[1] == .line(to: Point2D(x: 0, y: 4.5))
                } else {
                    false
                }
            })
    }

    @Test func aStepsNumberIsCentredAndContrasting() throws {
        let red = Annotation(id: Self.id(1), shape: .step(center: Point2D(x: 50, y: 50)))
        let yellow = Annotation(
            id: Self.id(2), shape: .step(center: Point2D(x: 100, y: 50)),
            style: AnnotationStyle(color: EditorPalette.swatches[2].color))
        let commands = Self.lists(EditorState(annotations: [red, yellow])).base.commands
        // diameter 28, font 15.4: "1" is 9.24 wide, ascent 12.32, descent 3.08
        let runs = commands.compactMap { command -> (String, Point2D, RGBAColor)? in
            if case .textRun(let s, let origin, let font, let color) = command {
                abs(font.size - 15.4) < 1e-9 && font.weight == 0.4 ? (s, origin, color) : nil
            } else {
                nil
            }
        }
        try #require(runs.count == 2)
        #expect(runs.map(\.0) == ["1", "2"])
        #expect(abs(runs[0].1.x - (50 - 4.62)) < 1e-9 && abs(runs[0].1.y - (50 + 4.62)) < 1e-9)
        #expect(runs[0].2 == RGBAColor(red: 1, green: 1, blue: 1))
        #expect(runs[1].2 == RGBAColor(red: 0, green: 0, blue: 0))
    }

    @Test func aBlurSamplesTheIntegralRectUnderItClampedToTheImage() {
        let blur = Annotation(shape: .blur(Rect2D(x: 380.5, y: 10.2, width: 40, height: 20), mode: .blur, strength: 3))
        let state = EditorState(frame: BackgroundFrame(padding: 10))
        var withBlur = state
        withBlur.annotations = [blur]
        let commands = Self.lists(withBlur, ppp: 2).base.commands
        #expect(
            commands.contains(
                .blurRegion(
                    Rect2D(x: 400, y: 30, width: 20, height: 21), sourceImageID: "capture",
                    sourceRect: Rect2D(x: 380, y: 10, width: 20, height: 21), effect: .gaussian(radius: 30))))
        #expect(
            !commands.contains {
                if case .pushGroup(let s) = $0 { s.shadow != nil && s.opacity == 1 && s.bounds != nil } else { false }
            })
    }

    @Test func activeAndHiddenAnnotationsAreLeftOutOfTheBase() {
        let a = Annotation(id: Self.id(1), shape: .line(from: .zero, to: Point2D(x: 50, y: 50)))
        let b = Annotation(id: Self.id(2), shape: .line(from: .zero, to: Point2D(x: 60, y: 10)))
        let state = EditorState(annotations: [a, b])
        let lists = Self.lists(state, active: a.id, hidden: b.id)
        #expect(
            lists.base == EditorRenderer.export(state: EditorState(), imageSize: Self.image, metrics: Self.metrics(1)))
        #expect(lists.active.commands.count > 2)
        #expect(lists.active.isBalanced)
        #expect(
            EditorRenderer.export(state: state, imageSize: Self.image, metrics: Self.metrics(1))
                == Self.lists(state).base)
    }

    @Test func theSelectionOutlineAndHandlesKeepTheirScreenSize() {
        let rect = Annotation(
            id: Self.id(1), shape: .rectangle(Rect2D(x: 10, y: 10, width: 100, height: 50), filled: false))
        let overlay = Self.lists(EditorState(annotations: [rect]), ppp: 2, selection: rect.id, zoom: 4).overlay
        // one screen point = 2 / 4 = 0.5 canvas px
        #expect(
            overlay.commands.first
                == .strokePath(
                    .rect(Rect2D(x: 9, y: 9, width: 102, height: 52)), color: RGBAColor(red: 0, green: 0.48, blue: 1),
                    lineWidth: 0.5, dash: [2, 1.5]))
        #expect(overlay.commands.count == 1 + 8 * 2)
        #expect(
            overlay.commands[1]
                == .fillPath(
                    .rect(Rect2D(x: 8, y: 8, width: 4, height: 4)), color: RGBAColor(red: 1, green: 1, blue: 1)))
    }

    // MARK: Goldens

    static func everyTool() -> EditorState {
        EditorState(annotations: [
            Annotation(id: id(1), shape: .arrow(from: Point2D(x: 20, y: 20), to: Point2D(x: 120, y: 80))),
            Annotation(
                id: id(2), shape: .line(from: Point2D(x: 20, y: 100), to: Point2D(x: 120, y: 100)),
                style: AnnotationStyle(width: .thin)),
            Annotation(id: id(3), shape: .rectangle(Rect2D(x: 150, y: 20, width: 80, height: 40), filled: false)),
            Annotation(
                id: id(4), shape: .rectangle(Rect2D(x: 250, y: 20, width: 80, height: 40), filled: true),
                style: AnnotationStyle(color: EditorPalette.swatches[4].color)),
            Annotation(
                id: id(5), shape: .ellipse(Rect2D(x: 150, y: 80, width: 60, height: 40), filled: false),
                style: AnnotationStyle(width: .thick)),
            Annotation(id: id(6), shape: .text(origin: Point2D(x: 20, y: 140), string: "Two\nlines", fontSize: 16)),
            Annotation(
                id: id(7), shape: .pen([Point2D(x: 250, y: 100), Point2D(x: 260, y: 110), Point2D(x: 275, y: 105)])),
            Annotation(
                id: id(8), shape: .highlighter([Point2D(x: 20, y: 220), Point2D(x: 200, y: 220)]),
                style: AnnotationStyle(color: EditorPalette.swatches[2].color)),
            Annotation(
                id: id(9), shape: .blur(Rect2D(x: 300, y: 150, width: 50, height: 30), mode: .pixelate, strength: 2)),
            Annotation(
                id: id(10), shape: .blur(Rect2D(x: 300, y: 200, width: 50, height: 30), mode: .blur, strength: 1)),
            Annotation(id: id(11), shape: .step(center: Point2D(x: 240, y: 250))),
            Annotation(
                id: id(12), shape: .step(center: Point2D(x: 280, y: 250)), style: AnnotationStyle(width: .thick)),
        ])
    }

    @Test func goldenEveryToolAt1xWithoutFrame() throws {
        try Self.checkGolden(Self.lists(Self.everyTool()).base, "every-tool-1x")
    }

    @Test func goldenShadowsCropAndGradientFrameAt2x() throws {
        var state = EditorState(
            annotations: [
                Annotation(
                    id: Self.id(1), shape: .arrow(from: Point2D(x: 60, y: 60), to: Point2D(x: 150, y: 120)),
                    style: AnnotationStyle(shadow: true)),
                Annotation(
                    id: Self.id(2), shape: .highlighter([Point2D(x: 60, y: 140), Point2D(x: 180, y: 140)]),
                    style: AnnotationStyle(shadow: true)),
                Annotation(
                    id: Self.id(3), shape: .text(origin: Point2D(x: 70, y: 70), string: "Hi", fontSize: 24),
                    style: AnnotationStyle(shadow: true)),
            ], crop: Rect2D(x: 50, y: 50, width: 200, height: 150))
        state.frame = BackgroundFrame(fill: .gradient(2), cornerRadius: 12)
        try Self.checkGolden(Self.lists(state, ppp: 2).base, "shadows-crop-frame-2x")
    }

    @Test func goldenSolidFrameWithoutShadow() throws {
        let state = EditorState(
            annotations: [
                Annotation(id: Self.id(1), shape: .rectangle(Rect2D(x: 10, y: 10, width: 50, height: 50), filled: true))
            ],
            frame: BackgroundFrame(padding: 20, fill: .white, cornerRadius: 0, shadow: false))
        try Self.checkGolden(Self.lists(state).base, "solid-frame")
    }

    @Test func goldenActiveAnnotationInsideAFrame() throws {
        let state = EditorState(
            annotations: [
                Annotation(id: Self.id(1), shape: .ellipse(Rect2D(x: 10, y: 10, width: 50, height: 30), filled: false))
            ],
            frame: BackgroundFrame())
        try Self.checkGolden(Self.lists(state, active: Self.id(1)).active, "active-in-frame")
    }

    @Test func goldenSelectionOverlay() throws {
        let state = Self.everyTool()
        try Self.checkGolden(Self.lists(state, ppp: 2, selection: Self.id(1), zoom: 0.5).overlay, "overlay-selection")
    }

    @Test func goldenCropToolOverlay() throws {
        let state = EditorState(crop: Rect2D(x: 50, y: 40, width: 100, height: 80), frame: BackgroundFrame())
        let lists = Self.lists(state, ppp: 2, selection: nil, cropMode: true, zoom: 1)
        try Self.checkGolden(lists.overlay, "overlay-crop")
        try Self.checkGolden(lists.base, "crop-tool-base")
    }
}
