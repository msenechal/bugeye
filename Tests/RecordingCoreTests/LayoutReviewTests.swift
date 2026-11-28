import BugeyeCore
import BugeyeTestSupport
import Foundation
import RecordingCore
import Testing

/// Findings of the final review of PR #16.
@Suite struct LayoutReviewTests {
    /// I1: on a display away from the origin, the children of a followed window are found in global points.
    @Test func childWindowsOnADisplayAwayFromTheOrigin() {
        let display = Rect2D(x: 1512, y: -200, width: 1920, height: 1080)
        let window = Rect2D(x: 1600, y: -100, width: 800, height: 600)
        let local = WindowFollow.followedRect(
            windowBounds: window, size: Size2D(width: 800, height: 600), displayBounds: display)
        let followed = WindowFollow.global(local, displayBounds: display)
        #expect(followed == window)
        let windows = [
            WindowSnapshot(id: WindowID(1), processID: 10, layer: 3, frame: window),
            WindowSnapshot(
                id: WindowID(2), processID: 10, layer: 101, frame: Rect2D(x: 1700, y: -50, width: 100, height: 200)),
            // Overlaps the display-local rect (88, 100, 800, 600) but not the window.
            WindowSnapshot(
                id: WindowID(3), processID: 10, layer: 101, frame: Rect2D(x: 100, y: 150, width: 50, height: 50)),
        ]
        // Window 1's own layer is above 0: it is still never its own child (review minor 7).
        #expect(ChildWindowFilter.children(of: WindowID(1), in: windows, followedGlobal: followed) == [WindowID(2)])
    }

    /// I2: repeated filter updates don't reset the count; only a delivered frame does.
    @Test func dropsAcrossRepeatedUpdatesStillFallBack() {
        var fallback = ChildWindowFallback()
        for _ in 0..<3 {
            fallback.filterUpdated()
            fallback.frameDropped()
        }
        #expect(fallback.useWindowAlone)
    }

    /// Minor 8: a window larger than the display; an exact landscape limit where the short side binds.
    @Test func moreGeometryEdges() {
        let display = Rect2D(x: 0, y: 0, width: 1512, height: 982)
        #expect(
            WindowFollow.followedRect(
                windowBounds: Rect2D(x: 300, y: 300, width: 3000, height: 2000),
                size: Size2D(width: 3000, height: 2000), displayBounds: display)
                == Rect2D(x: 0, y: 0, width: 1512, height: 982))
        #expect(
            RecordingGeometry.outputSize(points: Size2D(width: 4000, height: 2400), scale: 1, codec: .h264)
                == PixelSize(width: 3840, height: 2304))
        let screen = Rect2D(x: -1920, y: -300, width: 1920, height: 1080)
        let selection = Rect2D(x: -1500, y: -200, width: 400, height: 300)
        #expect(
            OptionsBarPlacement.origin(
                bar: Size2D(width: 500, height: 44), selection: selection, screen: screen, wholeDisplay: false)
                == Point2D(x: -1550, y: 112))
    }

    /// Minor 11: a bar or badge wider than its space starts at the left edge.
    @Test func tooWideStartsAtTheLeftEdge() throws {
        let screen = Rect2D(x: 100, y: 0, width: 300, height: 900)
        #expect(
            OptionsBarPlacement.origin(
                bar: Size2D(width: 500, height: 44), selection: Rect2D(x: 150, y: 100, width: 100, height: 100),
                screen: screen, wholeDisplay: false
            ).x == 100)
        var badge = KeystrokeBadge()
        badge.press(String(repeating: "W", count: 40), at: 0)
        let list = try #require(
            badge.displayList(at: 0, area: Size2D(width: 200, height: 300), measurer: FakeTextMeasurer()))
        guard case .fillPath(let path, _) = list.commands[1], case .move(let start) = path.elements.first else {
            Issue.record("no badge rect")
            return
        }
        #expect(start.x >= 0)
    }

    /// Minor 13: Apple's function-key private-use characters and a two-letter uppercase have no base.
    @Test func privateUseAndMultiLetterUppercasesHaveNoBadGlyph() {
        #expect(KeystrokeFormatter.baseKey(keyCode: 105, characters: "\u{F710}") == nil)
        #expect(
            KeystrokeFormatter.label(keyCode: 105, characters: "\u{F710}", modifiers: [.cmd], showAllKeys: true) == nil)
        #expect(KeystrokeFormatter.baseKey(keyCode: 27, characters: "ß") == "ß")
    }

    /// Minor 14: the badge's opacity is rounded, so goldens don't store float noise.
    @Test func opacityIsRounded() {
        var badge = KeystrokeBadge()
        badge.press("⌘ S", at: 0)
        #expect(badge.opacity(at: 1.35) == 0.5)
    }
}

@Suite struct TakeRecoveryReviewTests {
    let a = UUID()
    let b = UUID()
    let c = UUID()
    let now = Date(timeIntervalSince1970: 10_000)

    private func file(_ uuid: UUID, _ suffix: String, _ seconds: Double = 0, size: Int64 = 1_000_000)
        -> TakeRecovery.File
    {
        TakeRecovery.File(
            name: "Take-" + uuid.uuidString.lowercased() + suffix, created: Date(timeIntervalSince1970: seconds),
            modified: Date(timeIntervalSince1970: seconds), size: size)
    }

    /// I3: a movie too small to hold a fragment (a crash in the countdown) is deleted, not recovered.
    @Test func anEmptyMovieIsDeletedWithItsTimeline() {
        let plan = TakeRecovery.plan(
            files: [file(a, ".mov", 5, size: 2_000), file(a, ".timeline.jsonl", 5, size: 300)], liveTakes: [], now: now)
        #expect(plan.recover.isEmpty)
        #expect(plan.delete == [TakeRecovery.movieName(take: a), TakeRecovery.timelineName(take: a)].sorted())
    }

    /// Minor 1: a timeline whose movie was already delivered (crash between the two moves) is left alone.
    @Test func anOrphanTimelineIsLeftAlone() {
        let plan = TakeRecovery.plan(files: [file(c, ".timeline.jsonl", 5)], liveTakes: [], now: now)
        #expect(plan.recover.isEmpty)
        #expect(plan.delete.isEmpty)
    }

    /// Minor 2: a recovered `.mp4` is named by its timeline's creation (the take's start), not the conversion.
    @Test func aConvertedMovieTakesItsTimelinesTime() {
        let plan = TakeRecovery.plan(
            files: [file(a, ".mp4", 500), file(a, ".timeline.jsonl", 100)], liveTakes: [], now: now)
        #expect(plan.recover.first?.createdAt == Date(timeIntervalSince1970: 100))
        #expect(plan.recover.first?.movie == TakeRecovery.convertedName(take: a))
    }

    /// Minor 4: files written in the last 10 s belong to another running instance: left alone.
    @Test func recentlyModifiedFilesAreLeftAlone() {
        let plan = TakeRecovery.plan(files: [file(a, ".mov", 9_995)], liveTakes: [], now: now)
        #expect(plan.recover.isEmpty)
        #expect(plan.delete.isEmpty)
    }

    /// Minor 6: ordering by date, whatever the names; live takes untouched.
    @Test func orderedByDateAndLiveTakesUntouched() {
        let ids = [UUID(), UUID(), UUID()].sorted { $0.uuidString > $1.uuidString }
        let files = ids.enumerated().map { file($1, ".mov", Double($0) * 10) }
        let plan = TakeRecovery.plan(
            files: files + [file(a, ".mp4"), file(a, ".timeline.jsonl")], liveTakes: [a], now: now)
        #expect(plan.recover.map(\.take) == ids)
        #expect(plan.delete.isEmpty)
    }
}
