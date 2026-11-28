import BugeyeCore
import EditorCore
import Testing

@Suite struct ModelTests {
    @Test func strokeWidthsAreTwoFourEightPointsAndStepDiametersFollow() {
        #expect(StrokeWidth.thin.points == 2)
        #expect(StrokeWidth.medium.points == 4)
        #expect(StrokeWidth.thick.points == 8)
        #expect(StrokeWidth.thin.stepDiameter == 22)
        #expect(StrokeWidth.medium.stepDiameter == 28)
        #expect(StrokeWidth.thick.stepDiameter == 36)
    }

    @Test func toolOptionsStartAtTheSpecDefaults() {
        let options = ToolOptions()
        #expect(options.color == EditorPalette.red)
        #expect(options.width == .medium)
        #expect(options.filled == false)
        #expect(options.shadow == false)
        #expect(options.fontSize == 24)
        #expect(options.blurMode == .pixelate)
        #expect(options.blurStrength == 2)
    }

    @Test func aNewFrameHasTheSpecDefaults() {
        let frame = BackgroundFrame()
        #expect(frame.padding == 48)
        #expect(frame.fill == .gradient(0))
        #expect(frame.cornerRadius == 10)
        #expect(frame.shadow == true)
        #expect(EditorState().frame == nil)
        #expect(EditorState().crop == nil)
        #expect(EditorState().annotations.isEmpty)
    }

    @Test func thePaletteHasTheSpecValues() {
        #expect(
            EditorPalette.swatches.map(\.color) == [
                RGBAColor(red: 1, green: 0.23, blue: 0.19), RGBAColor(red: 1, green: 0.58, blue: 0),
                RGBAColor(red: 1, green: 0.8, blue: 0), RGBAColor(red: 0.2, green: 0.78, blue: 0.35),
                RGBAColor(red: 0, green: 0.48, blue: 1), RGBAColor(red: 0, green: 0, blue: 0),
            ])
        #expect(EditorPalette.swatches.map(\.name) == ["Red", "Orange", "Yellow", "Green", "Blue", "Black"])
        #expect(
            EditorPalette.fills.map(\.fill) == [.gradient(0), .gradient(1), .gradient(2), .gradient(3), .white, .black])
        #expect(
            EditorPalette.fills.map(\.name) == [
                "Indigo to pink", "Orange to coral", "Teal to blue", "Graphite", "White", "Black",
            ])
        #expect(
            EditorPalette.gradientColors(0)
                == [RGBAColor(red: 0.39, green: 0.40, blue: 0.95), RGBAColor(red: 0.93, green: 0.36, blue: 0.70)])
        #expect(
            EditorPalette.gradientColors(1)
                == [RGBAColor(red: 1, green: 0.62, blue: 0.27), RGBAColor(red: 0.96, green: 0.31, blue: 0.45)])
        #expect(
            EditorPalette.gradientColors(2)
                == [RGBAColor(red: 0.20, green: 0.80, blue: 0.75), RGBAColor(red: 0.16, green: 0.42, blue: 0.90)])
        #expect(
            EditorPalette.gradientColors(3)
                == [RGBAColor(red: 0.30, green: 0.32, blue: 0.36), RGBAColor(red: 0.08, green: 0.08, blue: 0.10)])
        #expect(EditorPalette.fillColors(.white) == [RGBAColor(red: 1, green: 1, blue: 1)])
        #expect(EditorPalette.fillColors(.black) == [RGBAColor(red: 0, green: 0, blue: 0)])
    }

    @Test func eachShapeBelongsToItsTool() {
        let p = Point2D(x: 1, y: 2)
        let r = Rect2D(x: 0, y: 0, width: 4, height: 4)
        #expect(AnnotationShape.arrow(from: p, to: p).tool == .arrow)
        #expect(AnnotationShape.line(from: p, to: p).tool == .line)
        #expect(AnnotationShape.rectangle(r, filled: false).tool == .rectangle)
        #expect(AnnotationShape.ellipse(r, filled: true).tool == .ellipse)
        #expect(AnnotationShape.text(origin: p, string: "a", fontSize: 24).tool == .text)
        #expect(AnnotationShape.pen([p]).tool == .pen)
        #expect(AnnotationShape.highlighter([p]).tool == .highlighter)
        #expect(AnnotationShape.blur(r, mode: .blur, strength: 3).tool == .blur)
        #expect(AnnotationShape.step(center: p).tool == .step)
    }
}
