import BugeyeCore
import CaptureCore
import Testing

@Suite struct SelectionGeometryTests {
    let display = Size2D(width: 1000, height: 800)

    func drag(_ anchor: DisplayPoint) -> Drag { Drag(display: DisplayID(1), anchor: anchor, fromCentre: false) }

    @Test func aDragSpansAnchorToPointerInEitherDirection() {
        var d = drag(DisplayPoint(x: 100, y: 100))
        d.update(to: DisplayPoint(x: 40, y: 160), shift: false, option: false, displaySize: display)
        #expect(d.rect(displaySize: display) == DisplayRect(x: 40, y: 100, width: 60, height: 60))
    }

    @Test func optionResizesFromTheCentre() {
        var d = drag(DisplayPoint(x: 100, y: 100))
        d.update(to: DisplayPoint(x: 130, y: 120), shift: false, option: true, displaySize: display)
        #expect(d.rect(displaySize: display) == DisplayRect(x: 70, y: 80, width: 60, height: 40))
        d.update(to: DisplayPoint(x: 130, y: 120), shift: false, option: false, displaySize: display)
        #expect(d.rect(displaySize: display) == DisplayRect(x: 100, y: 100, width: 30, height: 20))
    }

    @Test func aSelectionIsClippedToItsDisplay() {
        var d = drag(DisplayPoint(x: 900, y: 700))
        d.update(to: DisplayPoint(x: 1500, y: 2000), shift: false, option: false, displaySize: display)
        #expect(d.rect(displaySize: display) == DisplayRect(x: 900, y: 700, width: 100, height: 100))
        d.update(to: DisplayPoint(x: 950, y: 750), shift: false, option: true, displaySize: display)
        #expect(d.rect(displaySize: display) == DisplayRect(x: 850, y: 650, width: 100, height: 100))
        var e = drag(DisplayPoint(x: 10, y: 10))
        e.update(to: DisplayPoint(x: 100, y: 100), shift: false, option: true, displaySize: display)
        #expect(e.rect(displaySize: display) == DisplayRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test func shiftBeforeTheSelectionHasASizeDoesNotLockAtZero() {
        var d = drag(DisplayPoint(x: 100, y: 100))
        d.update(to: DisplayPoint(x: 100, y: 100), shift: true, option: false, displaySize: display)
        #expect(d.shiftPoint == nil)
        d.update(to: DisplayPoint(x: 150, y: 101), shift: true, option: false, displaySize: display)
        #expect(d.shiftPoint == DisplayPoint(x: 150, y: 101))
        #expect(d.lockedAxis == nil)
    }

    @Test func shiftLocksTheAxisThatMovedLessOnceThePointerMovedMoreThanTwoPoints() {
        var d = drag(DisplayPoint(x: 100, y: 100))
        d.update(to: DisplayPoint(x: 150, y: 150), shift: true, option: false, displaySize: display)
        d.update(to: DisplayPoint(x: 151, y: 151), shift: true, option: false, displaySize: display)
        #expect(d.lockedAxis == nil)
        d.update(to: DisplayPoint(x: 200, y: 152), shift: true, option: false, displaySize: display)
        #expect(d.lockedAxis == .y)
        #expect(d.rect(displaySize: display) == DisplayRect(x: 100, y: 100, width: 100, height: 50))
        d.update(to: DisplayPoint(x: 250, y: 300), shift: true, option: false, displaySize: display)
        #expect(d.rect(displaySize: display) == DisplayRect(x: 100, y: 100, width: 150, height: 50))
        d.update(to: DisplayPoint(x: 250, y: 300), shift: false, option: false, displaySize: display)
        #expect(d.lockedAxis == nil && d.shiftPoint == nil)
        #expect(d.rect(displaySize: display) == DisplayRect(x: 100, y: 100, width: 150, height: 200))
    }

    @Test func shiftCanLockTheHorizontalAxis() {
        var d = drag(DisplayPoint(x: 100, y: 100))
        d.update(to: DisplayPoint(x: 150, y: 150), shift: true, option: false, displaySize: display)
        d.update(to: DisplayPoint(x: 151, y: 250), shift: true, option: false, displaySize: display)
        #expect(d.lockedAxis == .x)
        #expect(d.rect(displaySize: display) == DisplayRect(x: 100, y: 100, width: 50, height: 150))
    }

    @Test func capturableNeedsFourByFourPoints() {
        #expect(SelectionGeometry.isCapturable(DisplayRect(x: 0, y: 0, width: 4, height: 4)))
        #expect(!SelectionGeometry.isCapturable(DisplayRect(x: 0, y: 0, width: 3.9, height: 100)))
        #expect(!SelectionGeometry.isCapturable(DisplayRect(x: 0, y: 0, width: 100, height: 3)))
    }

    @Test func theLoupeSitsBelowRightAndFlipsNearTheEdges() {
        #expect(
            SelectionGeometry.loupeFrame(pointer: DisplayPoint(x: 100, y: 100), displaySize: display)
                == DisplayRect(x: 120, y: 120, width: 120, height: 120))
        #expect(
            SelectionGeometry.loupeFrame(pointer: DisplayPoint(x: 900, y: 700), displaySize: display)
                == DisplayRect(x: 760, y: 560, width: 120, height: 120))
    }

    @Test func theLoupeStaysFullyOnScreen() {
        let tiny = Size2D(width: 200, height: 150)
        let frame = SelectionGeometry.loupeFrame(pointer: DisplayPoint(x: 100, y: 75), displaySize: tiny)
        #expect(frame.raw.minX >= 0 && frame.raw.maxX <= 200 && frame.raw.minY >= 0 && frame.raw.maxY <= 150)
    }

    @Test func theLoupeSampleIsFifteenPixelsSlidInsideTheImage() {
        let middle = SelectionGeometry.loupeSample(
            pointerPixelX: 100, pointerPixelY: 50, imageWidth: 400, imageHeight: 300)
        #expect(
            middle == LoupeSample(rect: PixelRect(x: 93, y: 43, width: 15, height: 15), markerColumn: 7, markerRow: 7))
        let corner = SelectionGeometry.loupeSample(
            pointerPixelX: 2, pointerPixelY: 299, imageWidth: 400, imageHeight: 300)
        #expect(
            corner == LoupeSample(rect: PixelRect(x: 0, y: 285, width: 15, height: 15), markerColumn: 2, markerRow: 14))
        let farRight = SelectionGeometry.loupeSample(
            pointerPixelX: 399, pointerPixelY: 0, imageWidth: 400, imageHeight: 300)
        #expect(farRight.rect.raw.width == 15 && farRight.rect.raw.minX == 385 && farRight.markerColumn == 14)
    }

    @Test func theReadoutIsWidthTimesHeightInRoundedPoints() {
        #expect(SelectionGeometry.readoutText(DisplayRect(x: 0, y: 0, width: 120.4, height: 80.6)) == "120 \u{00D7} 81")
    }

    @Test func theReadoutSitsOffTheCornerAndStaysOnScreen() {
        let label = Size2D(width: 80, height: 20)
        #expect(
            SelectionGeometry.readoutFrame(
                selection: DisplayRect(x: 100, y: 100, width: 50, height: 50), labelSize: label, displaySize: display)
                == DisplayRect(x: 158, y: 174, width: 80, height: 20))
        let edge = SelectionGeometry.readoutFrame(
            selection: DisplayRect(x: 900, y: 700, width: 100, height: 100), labelSize: label, displaySize: display)
        #expect(edge == DisplayRect(x: 920, y: 780, width: 80, height: 20))
    }
}
