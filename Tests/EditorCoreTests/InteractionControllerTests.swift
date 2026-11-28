import BugeyeCore
import BugeyeTestSupport
import EditorCore
import Foundation
import Testing

@Suite struct InteractionControllerTests {
    /// A 400 × 300 image at 1×, zoom 1: tolerances are 6 px (hit) and 8 px (handles).
    static func make(ppp: Double = 1, state: EditorState = EditorState()) -> InteractionController {
        InteractionController(
            document: EditorDocument(state: state), imageSize: Size2D(width: 400, height: 300),
            metrics: EditorMetrics(ppp: ppp, measurer: FakeTextMeasurer()))
    }

    static func drag(_ c: InteractionController, _ from: Point2D, _ to: Point2D, shift: Bool = false) {
        _ = c.mouseDown(at: from, clickCount: 1, shift: shift)
        c.mouseDragged(to: Point2D(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2), shift: shift)
        c.mouseDragged(to: to, shift: shift)
        c.mouseUp(at: to, shift: shift)
    }

    static func undoSteps(_ document: EditorDocument) -> Int {
        var n = 0
        while document.canUndo {
            document.undo()
            n += 1
        }
        return n
    }

    @Test func theDefaultToolIsArrowWithDefaultOptions() {
        let c = Self.make()
        #expect(c.tool == .arrow)
        #expect(c.options == ToolOptions())
    }

    @Test func drawingIsOneStepWithTheCurrentOptions() {
        let c = Self.make()
        c.setOptions(ToolOptions(color: EditorPalette.swatches[4].color, width: .thick, shadow: true))
        Self.drag(c, Point2D(x: 10, y: 10), Point2D(x: 100, y: 50))
        let added = c.document.state.annotations
        #expect(added.count == 1)
        #expect(added.first?.shape == .arrow(from: Point2D(x: 10, y: 10), to: Point2D(x: 100, y: 50)))
        #expect(
            added.first?.style == AnnotationStyle(color: EditorPalette.swatches[4].color, width: .thick, shadow: true))
        #expect(Self.undoSteps(c.document) == 1)
    }

    @Test func whileDrawingTheDraftIsActiveAndNotInTheDocument() {
        let c = Self.make()
        c.setTool(.rectangle)
        _ = c.mouseDown(at: Point2D(x: 10, y: 10), clickCount: 1, shift: false)
        c.mouseDragged(to: Point2D(x: 60, y: 40), shift: false)
        #expect(c.document.state.annotations.isEmpty)
        let draft = c.displayState.annotations.last
        #expect(draft?.shape == .rectangle(Rect2D(x: 10, y: 10, width: 50, height: 30), filled: false))
        #expect(c.activeID == draft?.id)
    }

    @Test func shiftMakesSquaresAndSnapsSegments() {
        let c = Self.make()
        c.setTool(.ellipse)
        Self.drag(c, Point2D(x: 10, y: 10), Point2D(x: 60, y: 30), shift: true)
        #expect(
            c.document.state.annotations.last?.shape
                == .ellipse(Rect2D(x: 10, y: 10, width: 50, height: 50), filled: false))
        c.setTool(.line)
        Self.drag(c, Point2D(x: 10, y: 100), Point2D(x: 110, y: 104), shift: true)
        guard case .line(_, let to) = c.document.state.annotations.last?.shape else {
            Issue.record("no line")
            return
        }
        #expect(abs(to.y - 100) < 1e-9)
    }

    @Test func filledRectanglesFollowTheOption() {
        let c = Self.make()
        c.setTool(.rectangle)
        c.setOptions(ToolOptions(filled: true))
        Self.drag(c, Point2D(x: 10, y: 10), Point2D(x: 60, y: 30))
        #expect(
            c.document.state.annotations.last?.shape
                == .rectangle(Rect2D(x: 10, y: 10, width: 50, height: 20), filled: true))
    }

    @Test func degenerateDragsCreateNothing() {
        let c = Self.make()
        for tool in [EditorTool.arrow, .line, .rectangle, .ellipse, .pen, .highlighter, .blur] {
            c.setTool(tool)
            Self.drag(c, Point2D(x: 10, y: 10), Point2D(x: 12, y: 11.5))
        }
        #expect(c.document.state.annotations.isEmpty)
        #expect(!c.document.canUndo)
    }

    @Test func shapesWhoseBoundsMissTheVisibleRectAreDropped() {
        let c = Self.make(state: EditorState(crop: Rect2D(x: 100, y: 100, width: 100, height: 100)))
        c.setTool(.rectangle)
        Self.drag(c, Point2D(x: 10, y: 10), Point2D(x: 50, y: 50))
        #expect(c.document.state.annotations.isEmpty)
        Self.drag(c, Point2D(x: 50, y: 50), Point2D(x: 120, y: 120))
        #expect(c.document.state.annotations.count == 1)
    }

    @Test func aBlurIsClampedToTheVisibleRectThenDroppedIfTooSmall() {
        let c = Self.make(state: EditorState(crop: Rect2D(x: 100, y: 100, width: 100, height: 100)))
        c.setTool(.blur)
        c.setOptions(ToolOptions(blurMode: .blur, blurStrength: 3))
        Self.drag(c, Point2D(x: 50, y: 50), Point2D(x: 150, y: 120))
        #expect(
            c.document.state.annotations.last?.shape
                == .blur(Rect2D(x: 100, y: 100, width: 50, height: 20), mode: .blur, strength: 3))
        #expect(c.document.state.annotations.last?.style.shadow == false)
        Self.drag(c, Point2D(x: 50, y: 50), Point2D(x: 102, y: 150))
        #expect(c.document.state.annotations.count == 1)
    }

    @Test func highlighterAndBlurNeverHaveAShadow() {
        let c = Self.make()
        c.setOptions(ToolOptions(shadow: true))
        c.setTool(.highlighter)
        Self.drag(c, Point2D(x: 10, y: 10), Point2D(x: 100, y: 10))
        #expect(c.document.state.annotations.last?.style.shadow == false)
    }

    @Test func penStrokesCollectEveryPoint() {
        let c = Self.make()
        c.setTool(.pen)
        Self.drag(c, Point2D(x: 10, y: 10), Point2D(x: 30, y: 10))
        #expect(
            c.document.state.annotations.last?.shape
                == .pen([Point2D(x: 10, y: 10), Point2D(x: 20, y: 10), Point2D(x: 30, y: 10)]))
    }

    @Test func stepsAreAddedByAClickInsideTheVisibleRect() {
        let c = Self.make(state: EditorState(crop: Rect2D(x: 100, y: 100, width: 100, height: 100)))
        c.setTool(.step)
        _ = c.mouseDown(at: Point2D(x: 150, y: 150), clickCount: 1, shift: false)
        c.mouseUp(at: Point2D(x: 150, y: 150), shift: false)
        _ = c.mouseDown(at: Point2D(x: 10, y: 10), clickCount: 1, shift: false)
        c.mouseUp(at: Point2D(x: 10, y: 10), shift: false)
        #expect(c.document.state.annotations.map(\.shape) == [.step(center: Point2D(x: 150, y: 150))])
        #expect(Self.undoSteps(c.document) == 1)
    }

    @Test func selectingLoadsTheAnnotationsStyleIntoTheOptions() {
        let rect = Annotation(
            shape: .rectangle(Rect2D(x: 10, y: 10, width: 100, height: 100), filled: true),
            style: AnnotationStyle(color: EditorPalette.swatches[3].color, width: .thin, shadow: true))
        let c = Self.make(state: EditorState(annotations: [rect]))
        c.setTool(.select)
        _ = c.mouseDown(at: Point2D(x: 50, y: 50), clickCount: 1, shift: false)
        c.mouseUp(at: Point2D(x: 50, y: 50), shift: false)
        #expect(c.selection == rect.id)
        #expect(c.options.color == EditorPalette.swatches[3].color)
        #expect(c.options.width == .thin)
        #expect(c.options.filled)
        #expect(c.options.shadow)
        #expect(!c.document.canUndo)
    }

    @Test func theTopmostHitIsSelectedAndAMissDeselects() {
        let bottom = Annotation(shape: .rectangle(Rect2D(x: 0, y: 0, width: 100, height: 100), filled: true))
        let top = Annotation(shape: .rectangle(Rect2D(x: 50, y: 50, width: 100, height: 100), filled: true))
        let c = Self.make(state: EditorState(annotations: [bottom, top]))
        c.setTool(.select)
        _ = c.mouseDown(at: Point2D(x: 75, y: 75), clickCount: 1, shift: false)
        c.mouseUp(at: Point2D(x: 75, y: 75), shift: false)
        #expect(c.selection == top.id)
        _ = c.mouseDown(at: Point2D(x: 300, y: 250), clickCount: 1, shift: false)
        c.mouseUp(at: Point2D(x: 300, y: 250), shift: false)
        #expect(c.selection == nil)
    }

    @Test func aMoveIsOneStepAndNotClamped() {
        let rect = Annotation(shape: .rectangle(Rect2D(x: 10, y: 10, width: 50, height: 50), filled: true))
        let c = Self.make(state: EditorState(annotations: [rect]))
        c.setTool(.select)
        Self.drag(c, Point2D(x: 20, y: 20), Point2D(x: -80, y: 20))
        #expect(
            c.document.state.annotations.first?.shape
                == .rectangle(Rect2D(x: -90, y: 10, width: 50, height: 50), filled: true))
        #expect(Self.undoSteps(c.document) == 1)
    }

    @Test func aClickWithoutMovingMakesNoStep() {
        let rect = Annotation(shape: .rectangle(Rect2D(x: 10, y: 10, width: 50, height: 50), filled: true))
        let c = Self.make(state: EditorState(annotations: [rect]))
        c.setTool(.select)
        _ = c.mouseDown(at: Point2D(x: 20, y: 20), clickCount: 1, shift: false)
        c.mouseUp(at: Point2D(x: 20, y: 20), shift: false)
        #expect(!c.document.canUndo)
    }

    @Test func aResizeKeepsTheGrabOffsetAndIgnoresShift() {
        let rect = Annotation(shape: .rectangle(Rect2D(x: 10, y: 10, width: 50, height: 50), filled: false))
        let c = Self.make(state: EditorState(annotations: [rect]))
        c.setTool(.select)
        _ = c.mouseDown(at: Point2D(x: 10, y: 30), clickCount: 1, shift: false)  // selects via the outline
        c.mouseUp(at: Point2D(x: 10, y: 30), shift: false)
        // grab the bottom-right handle 3 px off its centre
        _ = c.mouseDown(at: Point2D(x: 63, y: 62), clickCount: 1, shift: true)
        c.mouseUp(at: Point2D(x: 63, y: 62), shift: true)
        #expect(c.document.state.annotations.first?.shape == rect.shape)
        Self.drag(c, Point2D(x: 63, y: 62), Point2D(x: 103, y: 72), shift: true)
        #expect(
            c.document.state.annotations.first?.shape
                == .rectangle(Rect2D(x: 10, y: 10, width: 90, height: 60), filled: false))
        #expect(Self.undoSteps(c.document) == 1)
    }

    @Test func handlesAndTolerancesKeepTheirScreenSizeAtAnyZoom() {
        let line = Annotation(
            shape: .line(from: Point2D(x: 0, y: 100), to: Point2D(x: 300, y: 100)), style: AnnotationStyle(width: .thin)
        )
        let c = Self.make(ppp: 2, state: EditorState(annotations: [line]))
        c.setTool(.select)
        c.zoom = 0.25  // tolerance = 6 × 2 / 0.25 = 48 px
        _ = c.mouseDown(at: Point2D(x: 150, y: 140), clickCount: 1, shift: false)
        c.mouseUp(at: Point2D(x: 150, y: 140), shift: false)
        #expect(c.selection == line.id)
        c.zoom = 4  // tolerance = 3 px
        _ = c.mouseDown(at: Point2D(x: 150, y: 105), clickCount: 1, shift: false)
        c.mouseUp(at: Point2D(x: 150, y: 105), shift: false)
        #expect(c.selection == nil)
    }

    @Test func escapeDuringADragCancelsItWithNoStep() {
        let rect = Annotation(shape: .rectangle(Rect2D(x: 10, y: 10, width: 50, height: 50), filled: true))
        let c = Self.make(state: EditorState(annotations: [rect]))
        c.setTool(.select)
        _ = c.mouseDown(at: Point2D(x: 20, y: 20), clickCount: 1, shift: false)
        c.mouseDragged(to: Point2D(x: 80, y: 80), shift: false)
        c.escape()
        c.mouseUp(at: Point2D(x: 80, y: 80), shift: false)
        #expect(c.document.state.annotations == [rect])
        #expect(!c.document.canUndo)
        #expect(c.selection == rect.id)
        c.escape()
        #expect(c.selection == nil)

        c.setTool(.arrow)
        _ = c.mouseDown(at: Point2D(x: 20, y: 20), clickCount: 1, shift: false)
        c.mouseDragged(to: Point2D(x: 80, y: 80), shift: false)
        c.escape()
        #expect(c.activeID == nil)
        c.mouseUp(at: Point2D(x: 80, y: 80), shift: false)
        #expect(c.document.state.annotations == [rect])
    }

    @Test func undoDuringADragIsIgnored() {
        let c = Self.make()
        Self.drag(c, Point2D(x: 10, y: 10), Point2D(x: 100, y: 50))
        _ = c.mouseDown(at: Point2D(x: 20, y: 200), clickCount: 1, shift: false)
        c.mouseDragged(to: Point2D(x: 80, y: 200), shift: false)
        c.undo()
        #expect(c.document.state.annotations.count == 1)
        c.mouseUp(at: Point2D(x: 80, y: 200), shift: false)
        #expect(c.document.state.annotations.count == 2)
    }

    @Test func deleteRemovesTheSelectionInOneStep() {
        let rect = Annotation(shape: .rectangle(Rect2D(x: 10, y: 10, width: 50, height: 50), filled: true))
        let c = Self.make(state: EditorState(annotations: [rect]))
        #expect(!c.deleteSelection())
        c.setTool(.select)
        _ = c.mouseDown(at: Point2D(x: 20, y: 20), clickCount: 1, shift: false)
        c.mouseUp(at: Point2D(x: 20, y: 20), shift: false)
        #expect(c.deleteSelection())
        #expect(c.document.state.annotations.isEmpty)
        #expect(c.selection == nil)
        #expect(Self.undoSteps(c.document) == 1)
    }

    @Test func switchingAwayFromSelectDeselects() {
        let rect = Annotation(shape: .rectangle(Rect2D(x: 10, y: 10, width: 50, height: 50), filled: true))
        let c = Self.make(state: EditorState(annotations: [rect]))
        c.setTool(.select)
        _ = c.mouseDown(at: Point2D(x: 20, y: 20), clickCount: 1, shift: false)
        c.mouseUp(at: Point2D(x: 20, y: 20), shift: false)
        c.setTool(.rectangle)
        #expect(c.selection == nil)
    }

    @Test func aSelectionWhoseAnnotationIsUndoneAwayIsCleared() {
        let c = Self.make()
        Self.drag(c, Point2D(x: 10, y: 10), Point2D(x: 100, y: 10))
        c.setTool(.select)
        _ = c.mouseDown(at: Point2D(x: 50, y: 10), clickCount: 1, shift: false)
        c.mouseUp(at: Point2D(x: 50, y: 10), shift: false)
        #expect(c.selection != nil)
        c.undo()
        #expect(c.selection == nil)
        c.redo()
        #expect(c.document.state.annotations.count == 1)
    }

    @Test func restylingTheSelectionCoalescesIntoOneStepUntilAnotherAction() {
        let rect = Annotation(shape: .rectangle(Rect2D(x: 10, y: 10, width: 50, height: 50), filled: false))
        let c = Self.make(state: EditorState(annotations: [rect]))
        c.setTool(.select)
        _ = c.mouseDown(at: Point2D(x: 10, y: 30), clickCount: 1, shift: false)
        c.mouseUp(at: Point2D(x: 10, y: 30), shift: false)
        for i in 1...20 {  // a colour-panel drag
            var options = c.options
            options.color = RGBAColor(red: Double(i) / 20, green: 0, blue: 0)
            c.setOptions(options)
        }
        var options = c.options
        options.filled = true
        c.setOptions(options)
        #expect(c.document.state.annotations.first?.style.color == RGBAColor(red: 1, green: 0, blue: 0))
        #expect(
            c.document.state.annotations.first?.shape
                == .rectangle(Rect2D(x: 10, y: 10, width: 50, height: 50), filled: true))
        #expect(c.document.canUndo)
        c.undo()
        #expect(c.document.state.annotations == [rect])
        #expect(!c.document.canUndo)
    }

    @Test func anotherActionClosesTheRestyle() {
        let rect = Annotation(shape: .rectangle(Rect2D(x: 10, y: 10, width: 50, height: 50), filled: false))
        let c = Self.make(state: EditorState(annotations: [rect]))
        c.setTool(.select)
        _ = c.mouseDown(at: Point2D(x: 10, y: 30), clickCount: 1, shift: false)
        c.mouseUp(at: Point2D(x: 10, y: 30), shift: false)
        var options = c.options
        options.width = .thick
        c.setOptions(options)
        c.setFrameEnabled(true)
        options.width = .thin
        c.setOptions(options)
        #expect(Self.undoSteps(c.document) == 3)
    }

    @Test func optionsWithoutASelectionChangeNothingInTheDocument() {
        let c = Self.make()
        var options = c.options
        options.width = .thick
        c.setOptions(options)
        #expect(!c.document.canUndo)
        #expect(c.options.width == .thick)
    }

    @Test func textEntryAddsReplacesAndRemoves() {
        let c = Self.make()
        c.setTool(.text)
        c.setOptions(ToolOptions(color: EditorPalette.swatches[5].color, fontSize: 36))
        let result = c.mouseDown(at: Point2D(x: 20, y: 30), clickCount: 1, shift: false)
        guard case .beginTextEntry(let entry) = result else {
            Issue.record("no text entry")
            return
        }
        #expect(
            entry
                == TextEntry(
                    origin: Point2D(x: 20, y: 30), editingID: nil, string: "", fontSize: 36,
                    color: EditorPalette.swatches[5].color))
        c.mouseUp(at: Point2D(x: 20, y: 30), shift: false)
        c.commitText("Hello\nworld")
        let text = c.document.state.annotations.first
        #expect(text?.shape == .text(origin: Point2D(x: 20, y: 30), string: "Hello\nworld", fontSize: 36))
        #expect(text?.style.color == EditorPalette.swatches[5].color)

        // re-edit keeps size and colour, hides the annotation while editing
        c.setOptions(ToolOptions(color: EditorPalette.red, fontSize: 16))
        let again = c.mouseDown(at: Point2D(x: 25, y: 35), clickCount: 1, shift: false)
        guard case .beginTextEntry(let edit) = again else {
            Issue.record("no re-edit")
            return
        }
        #expect(edit.editingID == text?.id)
        #expect(edit.string == "Hello\nworld")
        #expect(edit.fontSize == 36)
        #expect(c.displayState.annotations.isEmpty)
        c.commitText("Hello\nworld")
        #expect(c.document.state.annotations == [text!])  // unchanged: no step
        #expect(Self.undoSteps(c.document) == 1)
        c.document.redo()

        _ = c.mouseDown(at: Point2D(x: 25, y: 35), clickCount: 1, shift: false)
        c.commitText("Bye")
        #expect(
            c.document.state.annotations.first?.shape
                == .text(origin: Point2D(x: 20, y: 30), string: "Bye", fontSize: 36))
        _ = c.mouseDown(at: Point2D(x: 25, y: 35), clickCount: 1, shift: false)
        c.commitText("  \n ")
        #expect(c.document.state.annotations.isEmpty)
    }

    @Test func emptyOrCancelledTextAddsNothingAndTextOutsideTheVisibleRectCantStart() {
        let c = Self.make(state: EditorState(crop: Rect2D(x: 100, y: 100, width: 100, height: 100)))
        c.setTool(.text)
        #expect(c.mouseDown(at: Point2D(x: 10, y: 10), clickCount: 1, shift: false) == .none)
        _ = c.mouseDown(at: Point2D(x: 150, y: 150), clickCount: 1, shift: false)
        c.commitText("   ")
        #expect(c.document.state.annotations.isEmpty)
        _ = c.mouseDown(at: Point2D(x: 150, y: 150), clickCount: 1, shift: false)
        #expect(c.textEntry != nil)
        c.cancelText()
        #expect(c.textEntry == nil)
        #expect(!c.document.canUndo)
    }

    @Test func doubleClickingATextAnnotationWithSelectReEditsIt() {
        let text = Annotation(shape: .text(origin: Point2D(x: 20, y: 30), string: "Hi", fontSize: 24))
        let c = Self.make(state: EditorState(annotations: [text]))
        c.setTool(.select)
        _ = c.mouseDown(at: Point2D(x: 25, y: 35), clickCount: 1, shift: false)
        c.mouseUp(at: Point2D(x: 25, y: 35), shift: false)
        let result = c.mouseDown(at: Point2D(x: 25, y: 35), clickCount: 2, shift: false)
        guard case .beginTextEntry(let entry) = result else {
            Issue.record("no re-edit")
            return
        }
        #expect(entry.editingID == text.id)
    }

    @Test func eachCropDragDrawsANewCropInOneStepAndResetIsOneStep() {
        let c = Self.make()
        c.setTool(.crop)
        #expect(c.showsFullImage)
        _ = c.mouseDown(at: Point2D(x: 10.2, y: 10), clickCount: 1, shift: false)
        c.mouseDragged(to: Point2D(x: 100, y: 80.6), shift: false)
        #expect(c.displayState.crop == Rect2D(x: 10.2, y: 10, width: 89.8, height: 70.6))
        c.mouseUp(at: Point2D(x: 100, y: 80.6), shift: false)
        #expect(c.document.state.crop == Rect2D(x: 10, y: 10, width: 90, height: 71))
        Self.drag(c, Point2D(x: 200, y: 200), Point2D(x: 500, y: 500))
        #expect(c.document.state.crop == Rect2D(x: 200, y: 200, width: 200, height: 100))
        Self.drag(c, Point2D(x: 50, y: 50), Point2D(x: 51, y: 51))
        #expect(c.document.state.crop == Rect2D(x: 200, y: 200, width: 200, height: 100))
        c.resetCrop()
        #expect(c.document.state.crop == nil)
        #expect(Self.undoSteps(c.document) == 3)
    }

    @Test func turningTheFrameOnIsOneStepAndASliderDragIsOneStep() {
        let c = Self.make()
        c.setFrameEnabled(true)
        #expect(c.document.state.frame == BackgroundFrame())
        c.beginFrameChange()
        for padding in stride(from: 50.0, through: 120, by: 10) {
            c.setFrame(BackgroundFrame(padding: padding))
        }
        c.endFrameChange()
        #expect(c.document.state.frame?.padding == 120)
        #expect(Self.undoSteps(c.document) == 2)
    }

    @Test func aRunOfKeyboardSliderStepsIsOneStepClosedByTheNextEdit() {
        let c = Self.make()
        c.setFrameEnabled(true)
        c.setFrame(BackgroundFrame(padding: 49))
        c.setFrame(BackgroundFrame(padding: 50))
        #expect(c.document.canUndo)
        c.setTool(.rectangle)
        Self.drag(c, Point2D(x: 10, y: 10), Point2D(x: 60, y: 60))
        #expect(Self.undoSteps(c.document) == 3)
    }

    @Test func undoClosesAnOpenKeyboardRunFirst() {
        let c = Self.make()
        c.setFrameEnabled(true)
        c.setFrame(BackgroundFrame(padding: 49))
        c.undo()
        #expect(c.document.state.frame == BackgroundFrame())
        c.undo()
        #expect(c.document.state.frame == nil)
    }

    @Test func theSnappingHookSeesEveryDraftAndIsIdentityByDefault() {
        let c = Self.make()
        c.snapping = { shape in shape.translated(by: Point2D(x: 1, y: 0)) }
        Self.drag(c, Point2D(x: 10, y: 10), Point2D(x: 100, y: 10))
        #expect(
            c.document.state.annotations.first?.shape == .arrow(from: Point2D(x: 11, y: 10), to: Point2D(x: 101, y: 10))
        )
    }
}
