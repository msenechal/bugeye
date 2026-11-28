import BugeyeCore
import RecordingCore
import Testing

@Suite struct RecordingGeometryTests {
    @Test func outputSizeIsPixelsRoundedDownToEven() {
        #expect(
            RecordingGeometry.outputSize(points: Size2D(width: 641, height: 361), scale: 1, codec: .h264)
                == PixelSize(width: 640, height: 360))
        #expect(
            RecordingGeometry.outputSize(points: Size2D(width: 640.5, height: 360), scale: 2, codec: .h264)
                == PixelSize(width: 1280, height: 720))
        #expect(
            RecordingGeometry.outputSize(points: Size2D(width: 0.4, height: 0.4), scale: 1, codec: .h264)
                == PixelSize(width: 2, height: 2))
    }

    @Test func h264IsShrunkInto4096By2304KeepingAspect() {
        // A 5K display: 5120 × 2880 → 4096 × 2304.
        #expect(
            RecordingGeometry.outputSize(points: Size2D(width: 2560, height: 1440), scale: 2, codec: .h264)
                == PixelSize(width: 4096, height: 2304))
        // HEVC keeps it.
        #expect(
            RecordingGeometry.outputSize(points: Size2D(width: 2560, height: 1440), scale: 2, codec: .hevc)
                == PixelSize(width: 5120, height: 2880))
        // Portrait: the limit applies to the long and short sides.
        #expect(
            RecordingGeometry.outputSize(points: Size2D(width: 1440, height: 2560), scale: 2, codec: .h264)
                == PixelSize(width: 2304, height: 4096))
        // 6K on HEVC: 6016 × 3384 fits 8192 × 4320.
        #expect(
            RecordingGeometry.outputSize(points: Size2D(width: 3008, height: 1692), scale: 2, codec: .hevc)
                == PixelSize(width: 6016, height: 3384))
        // A very wide strip is limited by its long side.
        #expect(
            RecordingGeometry.outputSize(points: Size2D(width: 6000, height: 100), scale: 1, codec: .h264)
                == PixelSize(width: 4096, height: 68))
    }

    @Test func bitrateIsPixelsTimesFpsTimesQualityClamped() {
        #expect(
            RecordingGeometry.bitrate(PixelSize(width: 1920, height: 1080), fps: 30, quality: .standard) == 3_732_480)
        #expect(RecordingGeometry.bitrate(PixelSize(width: 1920, height: 1080), fps: 30, quality: .high) == 7_464_960)
        #expect(RecordingGeometry.bitrate(PixelSize(width: 320, height: 200), fps: 30, quality: .standard) == 2_000_000)
        #expect(RecordingGeometry.bitrate(PixelSize(width: 8192, height: 4320), fps: 60, quality: .high) == 100_000_000)
    }

    @Test func theSourceRectIsWholePointsInsideTheDisplay() {
        let display = Size2D(width: 1512, height: 982)
        #expect(
            RecordingGeometry.clampedSourceRect(Rect2D(x: 10.4, y: 20.6, width: 300.2, height: 200.7), display: display)
                == Rect2D(x: 10, y: 20, width: 301, height: 202))
        #expect(
            RecordingGeometry.clampedSourceRect(Rect2D(x: -50, y: 900, width: 300, height: 200), display: display)
                == Rect2D(x: 0, y: 782, width: 300, height: 200))
        #expect(
            RecordingGeometry.clampedSourceRect(Rect2D(x: 5, y: 5, width: 0.5, height: 0), display: display)
                == Rect2D(x: 5, y: 5, width: 2, height: 2))
        #expect(
            RecordingGeometry.clampedSourceRect(Rect2D(x: 0, y: 0, width: 3000, height: 3000), display: display)
                == Rect2D(x: 0, y: 0, width: 1512, height: 982))
    }
}

@Suite struct OptionsBarPlacementTests {
    let screen = Rect2D(x: 0, y: 0, width: 1512, height: 982)
    let bar = Size2D(width: 500, height: 44)

    @Test func underTheSelection12PointsAwayAndCentred() {
        let selection = Rect2D(x: 300, y: 100, width: 400, height: 300)
        #expect(
            OptionsBarPlacement.origin(bar: bar, selection: selection, screen: screen, wholeDisplay: false)
                == Point2D(x: 250, y: 412))
    }

    @Test func aboveWhenItDoesNotFitUnder() {
        let selection = Rect2D(x: 300, y: 600, width: 400, height: 340)
        #expect(
            OptionsBarPlacement.origin(bar: bar, selection: selection, screen: screen, wholeDisplay: false)
                == Point2D(x: 250, y: 544))
    }

    @Test func insideTheBottomEdgeWhenNeitherFitsOrForAWholeDisplay() {
        let tall = Rect2D(x: 300, y: 20, width: 400, height: 950)
        #expect(
            OptionsBarPlacement.origin(bar: bar, selection: tall, screen: screen, wholeDisplay: false)
                == Point2D(x: 250, y: 914))
        #expect(
            OptionsBarPlacement.origin(bar: bar, selection: screen, screen: screen, wholeDisplay: true)
                == Point2D(x: 506, y: 926))
    }

    @Test func keptOnTheScreenHorizontally() {
        let left = Rect2D(x: 0, y: 100, width: 100, height: 100)
        #expect(OptionsBarPlacement.origin(bar: bar, selection: left, screen: screen, wholeDisplay: false).x == 0)
        let right = Rect2D(x: 1450, y: 100, width: 62, height: 100)
        #expect(OptionsBarPlacement.origin(bar: bar, selection: right, screen: screen, wholeDisplay: false).x == 1012)
    }
}

@Suite struct WindowFollowTests {
    let display = Rect2D(x: 0, y: 0, width: 1512, height: 982)

    @Test func followsAtItsStartingSizeClampedAndRounded() {
        let size = Size2D(width: 800, height: 600)
        #expect(
            WindowFollow.followedRect(
                windowBounds: Rect2D(x: 100.4, y: 50.6, width: 900, height: 700), size: size, displayBounds: display)
                == Rect2D(x: 100, y: 51, width: 800, height: 600))
        #expect(
            WindowFollow.followedRect(
                windowBounds: Rect2D(x: -200, y: 700, width: 800, height: 600), size: size, displayBounds: display)
                == Rect2D(x: 0, y: 382, width: 800, height: 600))
        // On a display at (1512, -200): display-local.
        let second = Rect2D(x: 1512, y: -200, width: 1920, height: 1080)
        #expect(
            WindowFollow.followedRect(
                windowBounds: Rect2D(x: 1600, y: -100, width: 800, height: 600), size: size, displayBounds: second)
                == Rect2D(x: 88, y: 100, width: 800, height: 600))
    }

    @Test func childWindowsAreTheSameProcessAboveLayerZeroAndOverlapping() {
        let followed = Rect2D(x: 100, y: 100, width: 800, height: 600)
        let windows = [
            WindowSnapshot(id: WindowID(1), processID: 10, layer: 0, frame: followed),
            WindowSnapshot(
                id: WindowID(2), processID: 10, layer: 101, frame: Rect2D(x: 150, y: 120, width: 200, height: 300)),
            WindowSnapshot(
                id: WindowID(3), processID: 10, layer: 3, frame: Rect2D(x: 1200, y: 100, width: 50, height: 50)),
            WindowSnapshot(
                id: WindowID(4), processID: 11, layer: 101, frame: Rect2D(x: 150, y: 120, width: 200, height: 300)),
            WindowSnapshot(
                id: WindowID(5), processID: 10, layer: 0, frame: Rect2D(x: 150, y: 120, width: 200, height: 300)),
            WindowSnapshot(
                id: WindowID(6), processID: 10, layer: 8, frame: Rect2D(x: 880, y: 680, width: 100, height: 100)),
        ]
        #expect(
            ChildWindowFilter.children(of: WindowID(1), in: windows, followed: followed) == [WindowID(2), WindowID(6)])
        #expect(ChildWindowFilter.children(of: WindowID(99), in: windows, followed: followed) == [])
    }

    @Test func moreThanTwoDroppedFramesAfterAFilterUpdateFallsBackToTheWindowAlone() {
        var monitor = ChildWindowFallback()
        monitor.filterUpdated()
        monitor.frameDropped()
        monitor.frameDropped()
        monitor.frameDelivered()
        #expect(!monitor.useWindowAlone)
        monitor.filterUpdated()
        monitor.frameDropped()
        monitor.frameDropped()
        #expect(!monitor.useWindowAlone)
        monitor.frameDropped()
        #expect(monitor.useWindowAlone)
        monitor.filterUpdated()
        monitor.frameDelivered()
        #expect(monitor.useWindowAlone)
        // Dropped frames with no update pending don't count.
        var quiet = ChildWindowFallback()
        for _ in 0..<5 { quiet.frameDropped() }
        #expect(!quiet.useWindowAlone)
    }
}

@Suite struct BubbleLayoutTests {
    let area = Rect2D(x: 100, y: 100, width: 1000, height: 600)

    @Test func startsBottomRight24PointsIn() {
        #expect(
            BubbleLayout.frame(corner: .bottomRight, size: .medium, area: area)
                == Rect2D(x: 896, y: 496, width: 180, height: 180))
        #expect(
            BubbleLayout.frame(corner: .topLeft, size: .small, area: area)
                == Rect2D(x: 124, y: 124, width: 120, height: 120))
    }

    @Test func aDropSnapsToTheNearestCorner() {
        #expect(BubbleLayout.corner(nearest: Point2D(x: 200, y: 650), area: area) == .bottomLeft)
        #expect(BubbleLayout.corner(nearest: Point2D(x: 1000, y: 120), area: area) == .topRight)
        #expect(BubbleLayout.corner(nearest: Point2D(x: 5000, y: 5000), area: area) == .bottomRight)
    }

    @Test func centredOnAnAxisWhereTheAreaIsTooSmall() {
        let narrow = Rect2D(x: 0, y: 0, width: 200, height: 600)
        #expect(
            BubbleLayout.frame(corner: .topRight, size: .large, area: narrow)
                == Rect2D(x: -20, y: 24, width: 240, height: 240))
    }

    @Test func changes() {
        let medium = BubbleWish(cameraDevice: "", size: .medium)
        #expect(BubbleChange.decide(current: nil, wish: nil) == .none)
        #expect(BubbleChange.decide(current: nil, wish: medium) == .create)
        #expect(BubbleChange.decide(current: medium, wish: nil) == .remove)
        #expect(BubbleChange.decide(current: medium, wish: medium) == .none)
        #expect(BubbleChange.decide(current: medium, wish: BubbleWish(cameraDevice: "", size: .large)) == .resize)
        #expect(
            BubbleChange.decide(current: medium, wish: BubbleWish(cameraDevice: "cam-2", size: .large)) == .recreate)
    }
}
