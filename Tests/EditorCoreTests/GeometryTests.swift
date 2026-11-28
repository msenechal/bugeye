import BugeyeCore
import BugeyeTestSupport
import EditorCore
import Foundation
import Testing

@Suite struct EditorGeometryTests {
    let image = Size2D(width: 200, height: 100)

    @Test func clampedCropRoundsIntersectsAndRejectsUnderThreePixels() {
        #expect(
            EditorGeometry.clampedCrop(Rect2D(x: 10.4, y: 20.6, width: 50.2, height: 30.1), imageSize: image)
                == Rect2D(x: 10, y: 21, width: 51, height: 30))
        #expect(
            EditorGeometry.clampedCrop(Rect2D(x: 150, y: 50, width: -20, height: 100), imageSize: image)
                == Rect2D(x: 130, y: 50, width: 20, height: 50))
        #expect(
            EditorGeometry.clampedCrop(Rect2D(x: -40, y: -40, width: 400, height: 400), imageSize: image)
                == Rect2D(x: 0, y: 0, width: 200, height: 100))
        #expect(EditorGeometry.clampedCrop(Rect2D(x: 10, y: 10, width: 2, height: 50), imageSize: image) == nil)
        #expect(EditorGeometry.clampedCrop(Rect2D(x: 300, y: 10, width: 20, height: 20), imageSize: image) == nil)
    }

    @Test func shiftSnapsSegmentsTo45DegreesKeepingTheirLength() {
        let from = Point2D(x: 0, y: 0)
        let snapped = EditorGeometry.snapped45(from: from, to: Point2D(x: 10, y: 1))
        #expect(abs(snapped.x - 10.0499) < 0.001 && abs(snapped.y) < 1e-9)
        let diagonal = EditorGeometry.snapped45(from: from, to: Point2D(x: 10, y: 9))
        #expect(abs(diagonal.x - diagonal.y) < 1e-9)
        let up = EditorGeometry.snapped45(from: from, to: Point2D(x: 1, y: -10))
        #expect(abs(up.x) < 1e-9 && up.y < -10)
    }

    @Test func shiftMakesSquaresTowardTheDrag() {
        #expect(
            EditorGeometry.rect(from: Point2D(x: 10, y: 10), to: Point2D(x: 30, y: 15), square: true)
                == Rect2D(x: 10, y: 10, width: 20, height: 20))
        #expect(
            EditorGeometry.rect(from: Point2D(x: 10, y: 10), to: Point2D(x: 5, y: -20), square: true)
                == Rect2D(x: -20, y: -20, width: 30, height: 30))
        #expect(
            EditorGeometry.rect(from: Point2D(x: 10, y: 10), to: Point2D(x: 5, y: 30), square: false)
                == Rect2D(x: 5, y: 10, width: 5, height: 20))
    }

    @Test func distanceToASegment() {
        let a = Point2D(x: 0, y: 0)
        let b = Point2D(x: 10, y: 0)
        #expect(EditorGeometry.distance(Point2D(x: 5, y: 3), toSegment: a, b) == 3)
        #expect(EditorGeometry.distance(Point2D(x: 13, y: 4), toSegment: a, b) == 5)
        #expect(EditorGeometry.distance(Point2D(x: 3, y: 4), toSegment: a, a) == 5)
    }

    @Test func overlapUsesClosedIntervalsSoFlatBoundsInsideCount() {
        let visible = Rect2D(x: 0, y: 0, width: 100, height: 100)
        #expect(EditorGeometry.overlaps(Rect2D(x: 10, y: 50, width: 40, height: 0), visible))
        #expect(EditorGeometry.overlaps(Rect2D(x: 90, y: 90, width: 40, height: 40), visible))
        #expect(!EditorGeometry.overlaps(Rect2D(x: 101, y: 50, width: 40, height: 0), visible))
        #expect(!EditorGeometry.overlaps(Rect2D(x: -50, y: -50, width: 40, height: 40), visible))
    }
}

@Suite struct TextLayoutTests {
    let measurer = FakeTextMeasurer()

    @Test func linesSitOnBaselinesSpacedByAscentPlusDescent() {
        let layout = TextLayout(
            string: "ab\n\nabcd", origin: Point2D(x: 10, y: 20), fontSize: 10, ppp: 2, measurer: measurer)
        // size 20 px: ascent 16, descent 4, width 12 per character
        #expect(layout.font == FontDescriptor(name: "system", size: 20, weight: 0.4))
        #expect(layout.ascent == 16)
        #expect(layout.descent == 4)
        #expect(layout.lines.map(\.string) == ["ab", "", "abcd"])
        #expect(layout.lines.map(\.width) == [24, 0, 48])
        #expect(
            layout.lines.map(\.baseline) == [Point2D(x: 10, y: 36), Point2D(x: 10, y: 56), Point2D(x: 10, y: 76)])
        #expect(layout.bounds == Rect2D(x: 10, y: 20, width: 48, height: 60))
    }
}

@Suite struct AnnotationGeometryTests {
    let metrics = EditorMetrics(ppp: 2, measurer: FakeTextMeasurer())

    @Test func boundsOfEveryShape() {
        let p = Point2D(x: 10, y: 20)
        let q = Point2D(x: 40, y: 5)
        #expect(Annotation(shape: .arrow(from: p, to: q)).bounds(metrics) == Rect2D(x: 10, y: 5, width: 30, height: 15))
        #expect(
            Annotation(shape: .rectangle(Rect2D(x: 40, y: 40, width: -10, height: 5), filled: false)).bounds(metrics)
                == Rect2D(x: 30, y: 40, width: 10, height: 5))
        #expect(
            Annotation(shape: .pen([p, q, Point2D(x: 0, y: 30)])).bounds(metrics)
                == Rect2D(x: 0, y: 5, width: 40, height: 25))
        // medium step: 28 pt × 2 = 56 px
        #expect(Annotation(shape: .step(center: p)).bounds(metrics) == Rect2D(x: -18, y: -8, width: 56, height: 56))
        #expect(
            Annotation(shape: .text(origin: p, string: "abc", fontSize: 10)).bounds(metrics)
                == Rect2D(x: 10, y: 20, width: 36, height: 20))
    }

    @Test func degenerateShapesAreNotMeaningful() {
        let p = Point2D(x: 10, y: 10)
        #expect(!AnnotationShape.arrow(from: p, to: Point2D(x: 12, y: 11)).isMeaningful)
        #expect(AnnotationShape.line(from: p, to: Point2D(x: 13, y: 10)).isMeaningful)
        #expect(!AnnotationShape.rectangle(Rect2D(x: 0, y: 0, width: 50, height: 2), filled: false).isMeaningful)
        #expect(AnnotationShape.ellipse(Rect2D(x: 0, y: 0, width: 3, height: 3), filled: false).isMeaningful)
        #expect(
            !AnnotationShape.blur(Rect2D(x: 0, y: 0, width: 2.9, height: 40), mode: .blur, strength: 1).isMeaningful)
        #expect(!AnnotationShape.pen([p, Point2D(x: 12, y: 12)]).isMeaningful)
        #expect(AnnotationShape.highlighter([p, Point2D(x: 10, y: 14)]).isMeaningful)
        #expect(AnnotationShape.step(center: p).isMeaningful)
    }

    @Test func handlesPerShape() {
        let rect = Annotation(shape: .rectangle(Rect2D(x: 0, y: 0, width: 10, height: 20), filled: false))
        #expect(rect.handles(metrics).count == 8)
        #expect(rect.handles(metrics).first { $0.handle == .bottomRight }?.point == Point2D(x: 10, y: 20))
        #expect(rect.handles(metrics).first { $0.handle == .top }?.point == Point2D(x: 5, y: 0))
        let line = Annotation(shape: .line(from: Point2D(x: 1, y: 2), to: Point2D(x: 3, y: 4)))
        #expect(line.handles(metrics).map(\.handle) == [.start, .end])
        #expect(Annotation(shape: .pen([Point2D(x: 1, y: 1)])).handles(metrics).isEmpty)
        #expect(Annotation(shape: .step(center: .zero)).handles(metrics).isEmpty)
        #expect(Annotation(shape: .text(origin: .zero, string: "a", fontSize: 16)).handles(metrics).isEmpty)
        #expect(Annotation(shape: .highlighter([.zero])).handles(metrics).isEmpty)
        #expect(
            Annotation(shape: .blur(Rect2D(x: 0, y: 0, width: 4, height: 4), mode: .blur, strength: 1)).handles(metrics)
                .count == 8)
    }

    @Test func hitTestingLinesRingsFillsAndBounds() {
        let line = Annotation(shape: .line(from: Point2D(x: 0, y: 0), to: Point2D(x: 100, y: 0)))
        #expect(line.hitTest(Point2D(x: 50, y: 5), tolerance: 6, metrics))
        #expect(!line.hitTest(Point2D(x: 50, y: 7), tolerance: 6, metrics))

        let outline = Annotation(shape: .rectangle(Rect2D(x: 0, y: 0, width: 100, height: 100), filled: false))
        #expect(outline.hitTest(Point2D(x: 104, y: 50), tolerance: 6, metrics))
        #expect(outline.hitTest(Point2D(x: 3, y: 50), tolerance: 6, metrics))
        #expect(!outline.hitTest(Point2D(x: 50, y: 50), tolerance: 6, metrics))
        let filled = Annotation(shape: .rectangle(Rect2D(x: 0, y: 0, width: 100, height: 100), filled: true))
        #expect(filled.hitTest(Point2D(x: 50, y: 50), tolerance: 6, metrics))

        let ellipse = Annotation(shape: .ellipse(Rect2D(x: 0, y: 0, width: 100, height: 50), filled: false))
        #expect(ellipse.hitTest(Point2D(x: 100, y: 25), tolerance: 6, metrics))
        #expect(ellipse.hitTest(Point2D(x: 50, y: 2), tolerance: 6, metrics))
        #expect(!ellipse.hitTest(Point2D(x: 50, y: 25), tolerance: 6, metrics))
        #expect(!ellipse.hitTest(Point2D(x: 2, y: 2), tolerance: 6, metrics))
        let filledEllipse = Annotation(shape: .ellipse(Rect2D(x: 0, y: 0, width: 100, height: 50), filled: true))
        #expect(filledEllipse.hitTest(Point2D(x: 50, y: 25), tolerance: 6, metrics))

        let pen = Annotation(shape: .pen([Point2D(x: 0, y: 0), Point2D(x: 10, y: 0), Point2D(x: 10, y: 10)]))
        #expect(pen.hitTest(Point2D(x: 14, y: 5), tolerance: 6, metrics))
        #expect(!pen.hitTest(Point2D(x: 3, y: 9), tolerance: 6, metrics))

        let blur = Annotation(shape: .blur(Rect2D(x: 0, y: 0, width: 10, height: 10), mode: .blur, strength: 1))
        #expect(blur.hitTest(Point2D(x: 5, y: 5), tolerance: 6, metrics))
        #expect(!blur.hitTest(Point2D(x: 12, y: 5), tolerance: 6, metrics))
    }

    @Test func theHitToleranceIsHalfTheStrokeOrTheMinimum() {
        let thick = Annotation(
            shape: .line(from: .zero, to: Point2D(x: 10, y: 0)), style: AnnotationStyle(width: .thick))
        #expect(thick.hitTolerance(minimum: 6, metrics) == 8)  // 8 pt × 2 / 2
        let thin = Annotation(shape: .line(from: .zero, to: Point2D(x: 10, y: 0)), style: AnnotationStyle(width: .thin))
        #expect(thin.hitTolerance(minimum: 6, metrics) == 6)
        let highlighter = Annotation(shape: .highlighter([.zero]), style: AnnotationStyle(width: .medium))
        #expect(highlighter.hitTolerance(minimum: 6, metrics) == 12)  // 3 × 4 pt × 2 / 2
    }

    @Test func translatingMovesEveryPoint() {
        let d = Point2D(x: 5, y: -2)
        #expect(
            AnnotationShape.arrow(from: .zero, to: Point2D(x: 1, y: 1)).translated(by: d)
                == .arrow(from: Point2D(x: 5, y: -2), to: Point2D(x: 6, y: -1)))
        #expect(
            AnnotationShape.text(origin: .zero, string: "a", fontSize: 16).translated(by: d)
                == .text(origin: d, string: "a", fontSize: 16))
        #expect(AnnotationShape.pen([.zero, d]).translated(by: d) == .pen([d, Point2D(x: 10, y: -4)]))
        #expect(
            AnnotationShape.blur(Rect2D(x: 0, y: 0, width: 4, height: 4), mode: .pixelate, strength: 2).translated(
                by: d) == .blur(Rect2D(x: 5, y: -2, width: 4, height: 4), mode: .pixelate, strength: 2))
        #expect(AnnotationShape.step(center: .zero).translated(by: d) == .step(center: d))
    }

    @Test func resizingMovesTheHandlesEdgesAndFlipsPastTheOpposite() {
        let rect = AnnotationShape.rectangle(Rect2D(x: 10, y: 10, width: 20, height: 20), filled: true)
        #expect(
            rect.resized(.bottomRight, to: Point2D(x: 50, y: 40))
                == .rectangle(Rect2D(x: 10, y: 10, width: 40, height: 30), filled: true))
        #expect(
            rect.resized(.left, to: Point2D(x: 0, y: 99))
                == .rectangle(Rect2D(x: 0, y: 10, width: 30, height: 20), filled: true))
        #expect(
            rect.resized(.top, to: Point2D(x: 0, y: 40))
                == .rectangle(Rect2D(x: 10, y: 30, width: 20, height: 10), filled: true))
        let line = AnnotationShape.line(from: .zero, to: Point2D(x: 10, y: 10))
        #expect(line.resized(.end, to: Point2D(x: 3, y: 4)) == .line(from: .zero, to: Point2D(x: 3, y: 4)))
        #expect(
            line.resized(.start, to: Point2D(x: 3, y: 4)) == .line(from: Point2D(x: 3, y: 4), to: Point2D(x: 10, y: 10))
        )
    }
}

@Suite struct StepNumberTests {
    @Test func aStepsNumberIsOnePlusTheStepsBelowIt() {
        let one = Annotation(shape: .step(center: .zero))
        let rect = Annotation(shape: .rectangle(Rect2D(x: 0, y: 0, width: 5, height: 5), filled: false))
        let two = Annotation(shape: .step(center: .zero))
        let three = Annotation(shape: .step(center: .zero))
        var state = EditorState(annotations: [one, rect, two, three])
        #expect(state.stepNumber(of: one.id) == 1)
        #expect(state.stepNumber(of: two.id) == 2)
        #expect(state.stepNumber(of: three.id) == 3)
        #expect(state.stepNumber(of: rect.id) == nil)
        state.annotations.remove(at: 2)
        #expect(state.stepNumber(of: three.id) == 2)
    }
}
