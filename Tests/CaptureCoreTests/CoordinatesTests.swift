import BugeyeCore
import CaptureCore
import Testing

@Suite struct CoordinatesTests {
    // Primary 1440 × 900 at the origin; an external 1920 × 1080 left of it and higher (negative x, its top above).
    let primaryHeight = 900.0

    @Test func cocoaToQuartzFlipsAroundThePrimaryHeight() {
        let rect = CocoaRect(x: 10, y: 100, width: 200, height: 50)
        #expect(rect.toQuartz(primaryHeight: primaryHeight) == QuartzRect(x: 10, y: 750, width: 200, height: 50))
        #expect(rect.toQuartz(primaryHeight: primaryHeight).toCocoa(primaryHeight: primaryHeight) == rect)
    }

    @Test func aDisplayLeftOfAndAboveThePrimaryHasANegativeQuartzOrigin() {
        let external = CocoaRect(x: -1920, y: 300, width: 1920, height: 1080)
        let quartz = external.toQuartz(primaryHeight: primaryHeight)
        #expect(quartz == QuartzRect(x: -1920, y: -480, width: 1920, height: 1080))
        #expect(quartz.toCocoa(primaryHeight: primaryHeight) == external)
    }

    @Test func aDisplayBelowThePrimaryHasAQuartzOriginBelowIt() {
        let below = CocoaRect(x: 0, y: -1080, width: 1920, height: 1080)
        #expect(below.toQuartz(primaryHeight: primaryHeight) == QuartzRect(x: 0, y: 900, width: 1920, height: 1080))
    }

    @Test func pointsFlipToo() {
        let point = CocoaPoint(x: -100, y: 1200)
        #expect(point.toQuartz(primaryHeight: primaryHeight) == QuartzPoint(x: -100, y: -300))
        #expect(point.toQuartz(primaryHeight: primaryHeight).toCocoa(primaryHeight: primaryHeight) == point)
    }

    @Test func viewToDisplayLocalFlipsAroundTheDisplayHeight() {
        let view = ViewRect(x: 10, y: 20, width: 30, height: 40)
        #expect(view.displayLocal(displayHeight: 1080) == DisplayRect(x: 10, y: 1020, width: 30, height: 40))
        #expect(view.displayLocal(displayHeight: 1080).viewRect(displayHeight: 1080) == view)
        #expect(ViewPoint(x: 5, y: 80).displayLocal(displayHeight: 100) == DisplayPoint(x: 5, y: 20))
        #expect(DisplayPoint(x: 5, y: 20).viewPoint(displayHeight: 100) == ViewPoint(x: 5, y: 80))
    }

    @Test func displayLocalToPixelsScalesAndRoundsOutward() {
        let rect = DisplayRect(x: 10.25, y: 20.5, width: 100.5, height: 50.1)
        // ×2: 20.5 41 → 221.5 141.2, rounded outward: 20 41 → 222 142.
        #expect(
            rect.pixelRect(scale: 2, imageWidth: 2880, imageHeight: 1800)
                == PixelRect(x: 20, y: 41, width: 202, height: 101))
    }

    @Test func pixelsAtOneXAreThePoints() {
        let rect = DisplayRect(x: 100, y: 200, width: 300, height: 150)
        #expect(
            rect.pixelRect(scale: 1, imageWidth: 1920, imageHeight: 1080)
                == PixelRect(x: 100, y: 200, width: 300, height: 150))
    }

    @Test func pixelsAreIntersectedWithTheImage() {
        let rect = DisplayRect(x: -10, y: 1000, width: 100, height: 200)
        #expect(
            rect.pixelRect(scale: 1, imageWidth: 1920, imageHeight: 1080)
                == PixelRect(x: 0, y: 1000, width: 90, height: 80))
    }

    @Test func lessThanOnePixelIsNil() {
        #expect(
            DisplayRect(x: 0, y: 0, width: 0.2, height: 10).pixelRect(scale: 1, imageWidth: 10, imageHeight: 10) != nil)
        #expect(
            DisplayRect(x: 20, y: 0, width: 5, height: 5).pixelRect(scale: 1, imageWidth: 10, imageHeight: 10) == nil)
        #expect(
            DisplayRect(x: 0, y: 0, width: 0, height: 5).pixelRect(scale: 2, imageWidth: 10, imageHeight: 10) == nil)
    }

    @Test func floatingNoiseDoesNotGrowTheCrop() {
        // 0.1 × 3 = 0.30000000000000004: must not round out to an extra pixel.
        let rect = DisplayRect(x: 0.1 * 3 * 10, y: 0, width: 10, height: 10)
        #expect(
            rect.pixelRect(scale: 1, imageWidth: 100, imageHeight: 100) == PixelRect(x: 3, y: 0, width: 10, height: 10))
    }

    @Test func mixedScalesUseEachDisplaysOwnScale() {
        let rect = DisplayRect(x: 10, y: 10, width: 20, height: 20)
        #expect(
            rect.pixelRect(scale: 2, imageWidth: 100, imageHeight: 100)
                == PixelRect(x: 20, y: 20, width: 40, height: 40))
        #expect(
            rect.pixelRect(scale: 1, imageWidth: 100, imageHeight: 100)
                == PixelRect(x: 10, y: 10, width: 20, height: 20))
    }

    @Test func displayLocalToQuartzAddsTheDisplaysQuartzOrigin() {
        let display = DisplayInfo(
            id: DisplayID(2), frame: Rect2D(x: -1920, y: 300, width: 1920, height: 1080), scale: 1)
        let quartz = display.quartzFrame(primaryHeight: primaryHeight)
        #expect(quartz == QuartzRect(x: -1920, y: -480, width: 1920, height: 1080))
        #expect(
            DisplayPoint(x: 10, y: 20).quartz(displayQuartzFrame: quartz) == QuartzPoint(x: -1910, y: -460))
        #expect(
            QuartzRect(x: -1900, y: -470, width: 10, height: 10).displayLocal(displayQuartzFrame: quartz)
                == DisplayRect(x: 20, y: 10, width: 10, height: 10))
    }

    @Test func primaryHeightIsTheHeightOfTheDisplayAtTheOrigin() {
        let displays = [
            DisplayInfo(id: DisplayID(2), frame: Rect2D(x: -1920, y: 300, width: 1920, height: 1080), scale: 1),
            DisplayInfo(id: DisplayID(1), frame: Rect2D(x: 0, y: 0, width: 1440, height: 900), scale: 2),
        ]
        #expect(DisplayInfo.primaryHeight(of: displays) == 900)
        #expect(DisplayInfo.primaryHeight(of: Array(displays.prefix(1))) == 1080)
        #expect(DisplayInfo.primaryHeight(of: []) == 0)
    }
}
