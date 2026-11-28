import BugeyeCore
import EditorCore
import Foundation
import Testing

@Suite struct CanvasLayoutTests {
    let image = Size2D(width: 400, height: 300)

    @Test func withoutFrameOrCropTheCanvasIsTheImage() {
        let layout = CanvasLayout(imageSize: image, state: EditorState(), pixelsPerPoint: 2, showingFullImage: false)
        #expect(layout.size == image)
        #expect(layout.contentRect == Rect2D(x: 0, y: 0, width: 400, height: 300))
        #expect(layout.imageOrigin == .zero)
        #expect(layout.visible == Rect2D(x: 0, y: 0, width: 400, height: 300))
        #expect(layout.frame == nil)
    }

    @Test func aCropAndAFrameAt2x() {
        let state = EditorState(
            crop: Rect2D(x: 50, y: 40, width: 100, height: 80), frame: BackgroundFrame(padding: 48.3))
        let layout = CanvasLayout(imageSize: image, state: state, pixelsPerPoint: 2, showingFullImage: false)
        // pad = round(48.3 × 2) = 97
        #expect(layout.padding == 97)
        #expect(layout.size == Size2D(width: 294, height: 274))
        #expect(layout.contentRect == Rect2D(x: 97, y: 97, width: 100, height: 80))
        #expect(layout.imageOrigin == Point2D(x: 47, y: 57))
        #expect(layout.imagePoint(fromCanvas: Point2D(x: 97, y: 97)) == Point2D(x: 50, y: 40))
        #expect(layout.canvasPoint(fromImage: Point2D(x: 50, y: 40)) == Point2D(x: 97, y: 97))
    }

    @Test func at1xTheFrameIsItsPadding() {
        let state = EditorState(frame: BackgroundFrame(padding: 48))
        let layout = CanvasLayout(imageSize: image, state: state, pixelsPerPoint: 1, showingFullImage: false)
        #expect(layout.size == Size2D(width: 496, height: 396))
        #expect(layout.imageOrigin == Point2D(x: 48, y: 48))
    }

    @Test func aPixelsPerPointBelowOneCountsAsOne() {
        let state = EditorState(frame: BackgroundFrame(padding: 10))
        let layout = CanvasLayout(imageSize: image, state: state, pixelsPerPoint: 0.5, showingFullImage: false)
        #expect(layout.padding == 10)
    }

    @Test func theCropToolShowsTheWholeImageWithoutFrame() {
        let state = EditorState(crop: Rect2D(x: 50, y: 40, width: 100, height: 80), frame: BackgroundFrame())
        let layout = CanvasLayout(imageSize: image, state: state, pixelsPerPoint: 2, showingFullImage: true)
        #expect(layout.size == image)
        #expect(layout.imageOrigin == .zero)
        #expect(layout.frame == nil)
        #expect(layout.padding == 0)
    }
}

@Suite struct EditorDocumentTests {
    static let a = Annotation(shape: .step(center: Point2D(x: 1, y: 1)))
    static let b = Annotation(shape: .step(center: Point2D(x: 2, y: 2)))

    @Test func applyMakesOneStepAndClearsRedo() {
        let document = EditorDocument()
        #expect(!document.canUndo)
        document.apply { $0.annotations.append(Self.a) }
        #expect(document.canUndo)
        document.undo()
        #expect(document.state.annotations.isEmpty)
        #expect(document.canRedo)
        document.apply { $0.annotations.append(Self.b) }
        #expect(!document.canRedo)
        #expect(document.state.annotations == [Self.b])
    }

    @Test func aChangeThatChangesNothingMakesNoStep() {
        let document = EditorDocument()
        document.beginChange()
        document.update { $0.crop = nil }
        document.endChange()
        #expect(!document.canUndo)
    }

    @Test func aDragIsOneStepAndBeginOnlyRemembersTheFirstState() {
        let document = EditorDocument()
        document.beginChange()
        document.update { $0.annotations = [Self.a] }
        document.beginChange()
        document.update { $0.annotations = [Self.a, Self.b] }
        document.endChange()
        document.undo()
        #expect(document.state.annotations.isEmpty)
        #expect(!document.canUndo)
    }

    @Test func atMost200UndoStepsTheOldestDropped() {
        let document = EditorDocument()
        for i in 0..<205 {
            document.apply { $0.annotations = [Annotation(shape: .step(center: Point2D(x: Double(i), y: 0)))] }
        }
        var count = 0
        while document.canUndo {
            document.undo()
            count += 1
        }
        #expect(count == 200)
        #expect(document.state.annotations.first?.shape == .step(center: Point2D(x: 4, y: 0)))
    }

    @Test func anOpenChangeThatDiffersCanBeUndoneAndUndoClosesItFirst() {
        let document = EditorDocument()
        document.apply { $0.annotations = [Self.a] }
        document.undo()
        document.beginChange()
        #expect(!document.canUndo)
        document.update { $0.frame = BackgroundFrame() }
        #expect(document.canUndo)
        #expect(document.isChangeOpen)
        document.undo()
        #expect(document.state.frame == nil)
        #expect(!document.isChangeOpen)
        #expect(document.canRedo)
    }

    @Test func cancellingAChangeRestoresItsStartWithoutAStep() {
        let document = EditorDocument()
        document.beginChange()
        document.update { $0.annotations = [Self.a] }
        document.cancelChange()
        #expect(document.state.annotations.isEmpty)
        #expect(!document.canUndo)
        #expect(!document.isChangeOpen)
    }

    @Test func dirtinessComparesWithTheStateThatWasSaved() {
        let document = EditorDocument()
        #expect(!document.isDirty)
        document.apply { $0.annotations = [Self.a] }
        let written = document.state
        document.apply { $0.annotations = [Self.a, Self.b] }
        document.markSaved(written)
        #expect(document.isDirty)
        document.undo()
        #expect(!document.isDirty)
    }
}
