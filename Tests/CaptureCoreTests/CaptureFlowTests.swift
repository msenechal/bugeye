import BugeyeCore
import CaptureCore
import Foundation
import Testing

// Two displays: a 2× primary 1440 × 900 at the origin and a 1× 1920 × 1080 to its left, top 180 pt higher.
let primary = DisplayInfo(id: DisplayID(1), frame: Rect2D(x: 0, y: 0, width: 1440, height: 900), scale: 2)
let external = DisplayInfo(id: DisplayID(2), frame: Rect2D(x: -1920, y: 0, width: 1920, height: 1080), scale: 1)
let freezeTime = Date(timeIntervalSince1970: 1_795_784_592)

func frame(_ display: DisplayInfo) -> FrameInfo {
    FrameInfo(
        display: display, pixelWidth: Int(display.frame.width * display.scale),
        pixelHeight: Int(display.frame.height * display.scale), time: freezeTime)
}

let ownPID: Int32 = 99
// A window on the primary display (Quartz 100,100 400×300) and Bugeye's own window above it.
let otherWindow = WindowInfo(
    id: WindowID(7), ownerPID: 10, bounds: Rect2D(x: 100, y: 100, width: 400, height: 300), layer: 0, alpha: 1)
let ownWindow = WindowInfo(
    id: WindowID(8), ownerPID: ownPID, bounds: Rect2D(x: 0, y: 0, width: 1440, height: 50), layer: 0, alpha: 1)
// Mostly off every display: its centre is left of the external display.
let offWindow = WindowInfo(
    id: WindowID(9), ownerPID: 10, bounds: Rect2D(x: -2400, y: 500, width: 600, height: 200), layer: 0, alpha: 1)

let noMods = Modifiers()
let pointerOnPrimary = CocoaPoint(x: 700, y: 450)

/// Drives a flow and keeps every effect.
struct Driver {
    var flow = CaptureFlow(ownPID: ownPID)
    var effects: [FlowEffect] = []

    @discardableResult
    mutating func send(_ event: FlowEvent) -> [FlowEffect] {
        let out = flow.handle(event)
        effects += out
        return out
    }

    var session: SessionID { flow.session! }

    /// Starts a screenshot request and answers its freeze.
    mutating func open(
        _ kind: CaptureRequestKind = .area, lastArea: StoredArea? = nil,
        windows: [WindowInfo] = [ownWindow, otherWindow, offWindow]
    ) {
        send(.request(kind, permitted: true, activityAllows: true, pointer: pointerOnPrimary, lastArea: lastArea))
        send(.frozen(session, [frame(primary), frame(external)], windows: windows, pointer: pointerOnPrimary))
    }

    mutating func openSelector(_ request: SelectionRequest, ticket: Int = 1) {
        send(.select(SelectionTicket(ticket), request))
        send(
            .frozen(
                session, [frame(primary), frame(external)], windows: [ownWindow, otherWindow, offWindow],
                pointer: pointerOnPrimary))
    }

    /// A drag on the primary display from display-local `from` to `to` (points, top-left).
    @discardableResult
    mutating func drag(from: DisplayPoint, to: DisplayPoint, on display: DisplayInfo = primary) -> [FlowEffect] {
        let h = display.frame.height
        send(.mouseDown(session, display.id, from.viewPoint(displayHeight: h), noMods))
        send(.mouseDragged(session, display.id, to.viewPoint(displayHeight: h), noMods))
        return send(.mouseUp(session, display.id, to.viewPoint(displayHeight: h)))
    }
}

func leaveEffects(_ session: SessionID, _ outcome: SelectionOutcome) -> [FlowEffect] {
    [
        .closeOverlays(session), .unregisterEscape(session), .reactivatePreviousApp,
        .logSelectionFinish(session, outcome),
    ]
}

@Suite struct CaptureFlowRequestTests {
    @Test func aRefusedActivityDropsTheRequestAndLogsBusy() {
        var d = Driver()
        let out = d.send(
            .request(.area, permitted: true, activityAllows: false, pointer: pointerOnPrimary, lastArea: nil))
        #expect(out == [.log(.capture, "busy: dropped area")])
        #expect(d.flow.phase == .idle)
    }

    @Test func noPermissionShowsTheAlertAndCapturesNothing() {
        var d = Driver()
        let out = d.send(
            .request(.fullscreen, permitted: false, activityAllows: true, pointer: pointerOnPrimary, lastArea: nil))
        #expect(out == [.showPermissionAlert])
        #expect(d.flow.phase == .idle)
    }

    @Test func fullscreenFreezesTheDisplayUnderThePointer() {
        var d = Driver()
        let out = d.send(
            .request(.fullscreen, permitted: true, activityAllows: true, pointer: pointerOnPrimary, lastArea: nil))
        #expect(out == [.freeze(d.session, .underPointer(pointerOnPrimary))])
        #expect(d.flow.phase == .freezing)
    }

    @Test func allDisplaysFreezesEveryDisplay() {
        var d = Driver()
        let out = d.send(
            .request(.allDisplays, permitted: true, activityAllows: true, pointer: pointerOnPrimary, lastArea: nil))
        #expect(out == [.freeze(d.session, .all)])
    }

    @Test func areaAndWindowReadTheWindowListAndFreezeEverything() {
        for kind in [CaptureRequestKind.area, .window] {
            var d = Driver()
            let out = d.send(
                .request(kind, permitted: true, activityAllows: true, pointer: pointerOnPrimary, lastArea: nil))
            #expect(out == [.readWindowList(d.session), .freeze(d.session, .all)])
        }
    }

    @Test func aRequestWhileBusyIsDroppedAndLogged() {
        var d = Driver()
        d.open()
        let out = d.send(
            .request(.fullscreen, permitted: true, activityAllows: true, pointer: pointerOnPrimary, lastArea: nil))
        #expect(out == [.log(.capture, "busy: dropped fullscreen")])
        #expect(d.flow.phase == .selecting)
    }

    @Test func fullScreenFramesAreDeliveredInDisplayOrderPrimaryFirst() {
        var d = Driver()
        d.send(.request(.allDisplays, permitted: true, activityAllows: true, pointer: pointerOnPrimary, lastArea: nil))
        let s = d.session
        let out = d.send(.frozen(s, [frame(external), frame(primary)], windows: [], pointer: pointerOnPrimary))
        #expect(
            out == [
                .deliver(
                    s,
                    [
                        Delivery(source: .frame(DisplayID(1), crop: nil), scale: 2, time: freezeTime),
                        Delivery(source: .frame(DisplayID(2), crop: nil), scale: 1, time: freezeTime),
                    ])
            ])
        #expect(d.flow.phase == .finishing)
        let done = d.send(.delivered(s, notices: [Notice(title: "a", body: "b")]))
        #expect(done == [.notify(title: "a", body: "b")])
        #expect(d.flow.phase == .idle)
    }

    @Test func aFreezeFailureForPermissionShowsTheAlert() {
        var d = Driver()
        d.send(.request(.area, permitted: true, activityAllows: true, pointer: pointerOnPrimary, lastArea: nil))
        let out = d.send(.freezeFailed(d.session, .permissionDenied))
        #expect(out == [.showPermissionAlert])
        #expect(d.flow.phase == .idle)
    }

    @Test func otherFreezeFailuresPostCaptureFailedWithTheirBody() {
        let cases: [(ScreenSourceError, String)] = [
            (.displayNotFound, "The display was disconnected."),
            (.windowNotFound, "The window closed before it could be captured."),
            (.failed("The stream stopped."), "The stream stopped."),
        ]
        for (error, body) in cases {
            var d = Driver()
            d.send(
                .request(.fullscreen, permitted: true, activityAllows: true, pointer: pointerOnPrimary, lastArea: nil))
            let out = d.send(.freezeFailed(d.session, error))
            #expect(
                out == [.log(.capture, "failed fullscreen: \(body)"), .notify(title: "Capture failed", body: body)])
            #expect(d.flow.phase == .idle)
        }
    }

    @Test func frozenForAreaOpensTheOverlaysAndKeysThePointersDisplay() {
        var d = Driver()
        d.send(.request(.area, permitted: true, activityAllows: true, pointer: pointerOnPrimary, lastArea: nil))
        let s = d.session
        let out = d.send(
            .frozen(s, [frame(external), frame(primary)], windows: [], pointer: CocoaPoint(x: -100, y: 10)))
        #expect(
            out == [
                .sweepLeftovers, .showOverlays(s, displays: [DisplayID(2), DisplayID(1)], mode: .area),
                .registerEscape(s),
                .activateBugeye, .makeKey(s, DisplayID(2)), .logSelectionBegin(s, .screenshot),
            ])
        #expect(d.flow.phase == .selecting)
        #expect(d.flow.overlay(for: DisplayID(1))?.mode == .area)
    }

    @Test func captureWindowOpensInWindowMode() {
        var d = Driver()
        d.open(.window)
        #expect(d.flow.overlay(for: DisplayID(1))?.mode == .window)
        #expect(d.effects.contains(.showOverlays(d.session, displays: [DisplayID(1), DisplayID(2)], mode: .window)))
    }
}

@Suite struct CaptureFlowAreaTests {
    @Test func aDragDeliversTheCropOfTheFrozenFrameAndStoresTheLastArea() {
        var d = Driver()
        d.open()
        let s = d.session
        let out = d.drag(from: DisplayPoint(x: 100, y: 50), to: DisplayPoint(x: 300, y: 150))
        let area = StoredArea(
            display: DisplayID(1), rect: Rect2D(x: 100, y: 50, width: 200, height: 100),
            displaySize: Size2D(width: 1440, height: 900))
        #expect(
            out
                == [.storeLastArea(area)] + leaveEffects(s, .area) + [
                    .deliver(
                        s,
                        [
                            Delivery(
                                source: .frame(DisplayID(1), crop: PixelRect(x: 200, y: 100, width: 400, height: 200)),
                                scale: 2, time: freezeTime)
                        ])
                ])
        #expect(d.flow.phase == .finishing)
        #expect(d.flow.overlay(for: DisplayID(1)) == nil)
    }

    @Test func dragsRedrawOnlyTheOldAndNewSelection() {
        var d = Driver()
        d.open()
        let s = d.session
        let h = primary.frame.height
        d.send(.mouseDown(s, DisplayID(1), DisplayPoint(x: 100, y: 100).viewPoint(displayHeight: h), noMods))
        let first = d.send(
            .mouseDragged(s, DisplayID(1), DisplayPoint(x: 200, y: 150).viewPoint(displayHeight: h), noMods))
        #expect(first == [.redraw(s, DisplayID(1), damage: DisplayRect(x: 99, y: 99, width: 102, height: 52))])
        let second = d.send(
            .mouseDragged(s, DisplayID(1), DisplayPoint(x: 150, y: 300).viewPoint(displayHeight: h), noMods))
        #expect(second == [.redraw(s, DisplayID(1), damage: DisplayRect(x: 99, y: 99, width: 102, height: 202))])
        #expect(d.flow.overlay(for: DisplayID(1))?.selection == DisplayRect(x: 100, y: 100, width: 50, height: 200))
        #expect(d.flow.overlay(for: DisplayID(2))?.selection == nil)
    }

    @Test func aClickWithoutADragOrATinySelectionLeavesTheOverlayUp() {
        var d = Driver()
        d.open()
        let tiny = d.drag(from: DisplayPoint(x: 100, y: 100), to: DisplayPoint(x: 103, y: 120))
        #expect(!tiny.contains { if case .deliver = $0 { true } else { false } })
        #expect(d.flow.phase == .selecting)
        #expect(d.flow.overlay(for: DisplayID(1))?.selection == nil)
        let click = d.drag(from: DisplayPoint(x: 100, y: 100), to: DisplayPoint(x: 100, y: 100))
        #expect(!click.contains(.closeOverlays(d.session)))
        #expect(d.flow.phase == .selecting)
    }

    @Test func aSelectionStaysOnTheDisplayWhereTheDragStarted() {
        var d = Driver()
        d.open()
        let s = d.session
        let h = primary.frame.height
        d.send(.mouseDown(s, DisplayID(1), DisplayPoint(x: 1400, y: 800).viewPoint(displayHeight: h), noMods))
        // The pointer crosses past the right and bottom edges (view coordinates beyond the view).
        d.send(.mouseDragged(s, DisplayID(1), ViewPoint(x: 1600, y: -200), noMods))
        #expect(d.flow.overlay(for: DisplayID(1))?.selection == DisplayRect(x: 1400, y: 800, width: 40, height: 100))
    }

    @Test func modifiersAreReadFromEveryDragEvent() {
        var d = Driver()
        d.open()
        let s = d.session
        let h = primary.frame.height
        d.send(.mouseDown(s, DisplayID(1), DisplayPoint(x: 100, y: 100).viewPoint(displayHeight: h), noMods))
        d.send(
            .mouseDragged(
                s, DisplayID(1), DisplayPoint(x: 130, y: 120).viewPoint(displayHeight: h), Modifiers(option: true)))
        #expect(d.flow.overlay(for: DisplayID(1))?.selection == DisplayRect(x: 70, y: 80, width: 60, height: 40))
    }

    @Test func spaceTogglesWindowModeAndResetsTheDrag() {
        var d = Driver()
        d.open()
        let s = d.session
        let h = primary.frame.height
        d.send(.mouseDown(s, DisplayID(1), DisplayPoint(x: 100, y: 100).viewPoint(displayHeight: h), noMods))
        d.send(.mouseDragged(s, DisplayID(1), DisplayPoint(x: 200, y: 200).viewPoint(displayHeight: h), noMods))
        let out = d.send(.key(s, .space))
        #expect(out == [.redraw(s, DisplayID(1), damage: nil), .redraw(s, DisplayID(2), damage: nil)])
        #expect(
            d.flow.overlay(for: DisplayID(1)) == OverlayRender(mode: .window, selection: nil, hovered: nil, hint: nil))
        d.send(.key(s, .space))
        #expect(d.flow.overlay(for: DisplayID(1))?.mode == .area)
    }

    @Test func returnRecapturesTheLastAreaFromTheNewFrozenFrame() {
        var d = Driver()
        let area = StoredArea(
            display: DisplayID(2), rect: Rect2D(x: 10, y: 20, width: 30, height: 40),
            displaySize: Size2D(width: 1920, height: 1080))
        d.open(lastArea: area)
        let s = d.session
        let out = d.send(.key(s, .return))
        #expect(
            out
                == [.storeLastArea(area)] + leaveEffects(s, .area) + [
                    .deliver(
                        s,
                        [
                            Delivery(
                                source: .frame(DisplayID(2), crop: PixelRect(x: 10, y: 20, width: 30, height: 40)),
                                scale: 1, time: freezeTime)
                        ])
                ])
    }

    @Test func returnBeepsWithoutAUsableLastArea() {
        let size = Size2D(width: 1440, height: 900)
        let cases: [StoredArea?] = [
            nil,
            StoredArea(display: DisplayID(5), rect: Rect2D(x: 0, y: 0, width: 10, height: 10), displaySize: size),
            StoredArea(
                display: DisplayID(1), rect: Rect2D(x: 0, y: 0, width: 10, height: 10),
                displaySize: Size2D(width: 1680, height: 1050)),
            StoredArea(display: DisplayID(1), rect: Rect2D(x: 2000, y: 0, width: 10, height: 10), displaySize: size),
        ]
        for area in cases {
            var d = Driver()
            d.open(lastArea: area)
            #expect(d.send(.key(d.session, .return)) == [.beep])
            #expect(d.flow.phase == .selecting)
        }
    }

    @Test func pointerEnteredKeysThatDisplayOnlyWithNoButtonDown() {
        var d = Driver()
        d.open()
        let s = d.session
        #expect(d.send(.pointerEntered(s, DisplayID(2), buttonDown: false)) == [.makeKey(s, DisplayID(2))])
        #expect(d.send(.pointerEntered(s, DisplayID(2), buttonDown: true)) == [])
    }

    @Test func escapeRightClickGlobalEscapeAndADisplayChangeCancel() {
        let cancels: [(SessionID) -> FlowEvent] = [
            { .key($0, .escape) }, { .rightMouseDown($0) }, { _ in .globalEscape }, { _ in .displaysChanged },
        ]
        for cancel in cancels {
            var d = Driver()
            d.open()
            let s = d.session
            #expect(d.send(cancel(s)) == leaveEffects(s, .cancelled))
            #expect(d.flow.phase == .idle)
        }
    }
}

@Suite struct CaptureFlowWindowTests {
    func windowMode() -> Driver {
        var d = Driver()
        d.open(.window)
        return d
    }

    @Test func hoverPicksTheFrontmostOtherAppsWindowAndRedrawsOnlyOnChange() {
        var d = windowMode()
        let s = d.session
        let h = primary.frame.height
        // Over Bugeye's own bar and the other window: the other window wins.
        let over = DisplayPoint(x: 150, y: 120).viewPoint(displayHeight: h)
        #expect(
            d.send(.pointerMoved(s, DisplayID(1), over)) == [
                .redraw(s, DisplayID(1), damage: nil), .redraw(s, DisplayID(2), damage: nil),
            ])
        #expect(d.flow.overlay(for: DisplayID(1))?.hovered == DisplayRect(x: 100, y: 100, width: 400, height: 300))
        #expect(d.send(.pointerMoved(s, DisplayID(1), DisplayPoint(x: 160, y: 130).viewPoint(displayHeight: h))) == [])
        // Each display gets the window in its own display-local space; the view clips it.
        #expect(d.flow.overlay(for: DisplayID(2))?.hovered == DisplayRect(x: 2020, y: 280, width: 400, height: 300))
    }

    @Test func aClickOnNothingBeeps() {
        var d = windowMode()
        let s = d.session
        let out = d.send(
            .mouseDown(s, DisplayID(1), DisplayPoint(x: 1000, y: 800).viewPoint(displayHeight: 900), noMods))
        #expect(out == [.beep])
        #expect(d.flow.phase == .selecting)
    }

    @Test func aClickOnAWindowClosesTheOverlayAndCapturesItLiveAtItsDisplaysScale() {
        var d = windowMode()
        let s = d.session
        let out = d.send(
            .mouseDown(s, DisplayID(1), DisplayPoint(x: 200, y: 200).viewPoint(displayHeight: 900), noMods))
        #expect(
            out == leaveEffects(s, .window) + [
                .captureWindow(s, WindowID(7), windowSize: Size2D(width: 400, height: 300), scale: 2)
            ])
        #expect(d.flow.phase == .finishing)
        let delivered = d.send(.windowCaptured(s, time: freezeTime.addingTimeInterval(1)))
        #expect(
            delivered == [.deliver(s, [Delivery(source: .window, scale: 2, time: freezeTime.addingTimeInterval(1))])])
        #expect(d.send(.delivered(s, notices: [])) == [])
        #expect(d.flow.phase == .idle)
    }

    @Test func aWindowWhoseCentreIsOnNoDisplayUsesTheFirstFrozenScale() {
        var d = windowMode()
        let s = d.session
        // offWindow's visible part is on the external display (display-local x 0…120 at y 680…880).
        let out = d.send(
            .mouseDown(s, DisplayID(2), DisplayPoint(x: 50, y: 750).viewPoint(displayHeight: 1080), noMods))
        #expect(out.last == .captureWindow(s, WindowID(9), windowSize: Size2D(width: 600, height: 200), scale: 2))
    }

    @Test func aWindowCaptureFailureNotifiesAndReturnsToIdle() {
        var d = windowMode()
        let s = d.session
        d.send(.mouseDown(s, DisplayID(1), DisplayPoint(x: 200, y: 200).viewPoint(displayHeight: 900), noMods))
        let out = d.send(.windowCaptureFailed(s, .windowNotFound))
        #expect(
            out == [
                .log(.capture, "failed window: The window closed before it could be captured."),
                .notify(title: "Capture failed", body: "The window closed before it could be captured."),
            ])
        #expect(d.flow.phase == .idle)
    }

    @Test func aWindowCaptureDeniedShowsTheAlert() {
        var d = windowMode()
        let s = d.session
        d.send(.mouseDown(s, DisplayID(1), DisplayPoint(x: 200, y: 200).viewPoint(displayHeight: 900), noMods))
        #expect(d.send(.windowCaptureFailed(s, .permissionDenied)) == [.showPermissionAlert])
        #expect(d.flow.phase == .idle)
    }
}

/// The first build's regression tests, by name (design/02 §3.1).
@Suite struct CaptureFlowRegressionTests {
    @Test func aFinishedSelectionsOverlayIsNotBroughtBackByTheMouseEntering() {
        var d = Driver()
        d.open()
        let s = d.session
        d.drag(from: DisplayPoint(x: 100, y: 100), to: DisplayPoint(x: 300, y: 300))
        // The late mouseEntered arrives while the capture finishes, and again after it.
        #expect(d.send(.pointerEntered(s, DisplayID(1), buttonDown: false)) == [])
        d.send(.delivered(s, notices: []))
        #expect(d.send(.pointerEntered(s, DisplayID(1), buttonDown: false)) == [.sweepLeftovers])
        #expect(d.effects.filter { $0 == .makeKey(s, DisplayID(1)) }.count == 1)
    }

    @Test func leftoverOverlaysAreClosedWhenASelectionBeginsOrEnds() {
        var d = Driver()
        d.open()
        let s = d.session
        #expect(d.effects.contains(.sweepLeftovers))
        let out = d.send(.key(s, .escape))
        #expect(out.first == .closeOverlays(s))
    }

    @Test func escapeHotkeyIsHeldWhileTheOverlayIsUpAndCancels() {
        var d = Driver()
        d.open()
        let s = d.session
        #expect(d.effects.filter { $0 == .registerEscape(s) }.count == 1)
        #expect(d.send(.globalEscape) == leaveEffects(s, .cancelled))
        #expect(d.effects.filter { $0 == .unregisterEscape(s) }.count == 1)
    }

    @Test func escapeHotkeyIsReleasedWhenAnAreaIsChosen() {
        var d = Driver()
        d.open()
        let s = d.session
        let out = d.drag(from: DisplayPoint(x: 100, y: 100), to: DisplayPoint(x: 300, y: 300))
        #expect(out.contains(.unregisterEscape(s)))
        #expect(d.send(.globalEscape) == [])
    }

    @Test func rightClickCancelsTheSelection() {
        var d = Driver()
        d.open()
        let s = d.session
        #expect(d.send(.rightMouseDown(s)) == leaveEffects(s, .cancelled))
    }

    @Test func eventsFromAnotherSessionOnlySweepLeftovers() {
        var d = Driver()
        d.open()
        let old = d.session
        d.send(.key(old, .escape))
        d.open()
        let stale = d.send(.mouseDown(old, DisplayID(1), ViewPoint(x: 10, y: 10), noMods))
        #expect(stale == [.sweepLeftovers])
        #expect(d.send(.frozen(old, [frame(primary)], windows: [], pointer: pointerOnPrimary)) == [])
        #expect(d.flow.phase == .selecting)
    }
}

@Suite struct CaptureFlowSelectorTests {
    let recording = SelectionRequest(
        purpose: .recording, hint: "Drag an area · Click to record this display · Space: pick a window · Esc to cancel",
        clickSelectsDisplay: true, windowNeedsDisplayCentre: true)

    @Test func selectFreezesAndOpensWithTheHint() {
        var d = Driver()
        let out = d.send(.select(SelectionTicket(1), recording))
        #expect(out == [.readWindowList(d.session), .freeze(d.session, .all)])
        d.send(.frozen(d.session, [frame(primary)], windows: [], pointer: pointerOnPrimary))
        #expect(d.flow.overlay(for: DisplayID(1))?.hint == recording.hint)
        #expect(d.effects.contains(.logSelectionBegin(d.session, .recording)))
    }

    @Test func selectStartsInWindowModeWhenAsked() {
        var d = Driver()
        var request = recording
        request.startInWindowMode = true
        d.openSelector(request)
        #expect(d.flow.overlay(for: DisplayID(1))?.mode == .window)
    }

    @Test func selectWhileBusyAnswersBusyToThatCallerOnly() {
        var d = Driver()
        d.open()
        #expect(d.send(.select(SelectionTicket(2), recording)) == [.answer(SelectionTicket(2), .busy)])
        #expect(d.flow.phase == .selecting)
    }

    @Test func aClickSelectsTheDisplayWhenAsked() {
        var d = Driver()
        d.openSelector(recording)
        let s = d.session
        let out = d.drag(from: DisplayPoint(x: 100, y: 100), to: DisplayPoint(x: 101, y: 101), on: external)
        #expect(out == leaveEffects(s, .display) + [.answer(SelectionTicket(1), .display(DisplayID(2)))])
        #expect(d.flow.phase == .idle)
    }

    @Test func aClickDoesNothingWhenClickSelectsDisplayIsOff() {
        var d = Driver()
        d.openSelector(SelectionRequest(purpose: .recording))
        d.drag(from: DisplayPoint(x: 100, y: 100), to: DisplayPoint(x: 101, y: 101))
        #expect(d.flow.phase == .selecting)
    }

    @Test func anAreaAnswersAStoredAreaWithoutStoringOrDelivering() {
        var d = Driver()
        d.openSelector(recording)
        let s = d.session
        let out = d.drag(from: DisplayPoint(x: 100, y: 50), to: DisplayPoint(x: 300, y: 150))
        let area = StoredArea(
            display: DisplayID(1), rect: Rect2D(x: 100, y: 50, width: 200, height: 100),
            displaySize: Size2D(width: 1440, height: 900))
        #expect(out == leaveEffects(s, .area) + [.answer(SelectionTicket(1), .area(area))])
        #expect(d.flow.phase == .idle)
    }

    @Test func returnAnswersTheRequestsOwnLastArea() {
        let area = StoredArea(
            display: DisplayID(1), rect: Rect2D(x: 1, y: 2, width: 30, height: 40),
            displaySize: Size2D(width: 1440, height: 900))
        var request = recording
        request.lastArea = area
        var d = Driver()
        d.openSelector(request)
        let s = d.session
        #expect(d.send(.key(s, .return)) == leaveEffects(s, .area) + [.answer(SelectionTicket(1), .area(area))])

        var e = Driver()
        e.openSelector(recording)
        #expect(e.send(.key(e.session, .return)) == [.beep])
    }

    @Test func aWindowWhoseCentreIsOnNoDisplayBeepsWhenTheRequestSaysSo() {
        var request = recording
        request.startInWindowMode = true
        var d = Driver()
        d.openSelector(request)
        let s = d.session
        #expect(
            d.send(.mouseDown(s, DisplayID(2), DisplayPoint(x: 50, y: 750).viewPoint(displayHeight: 1080), noMods)) == [
                .beep
            ])
        #expect(d.flow.phase == .selecting)
    }

    @Test func aWindowAnswersItsIdDisplayAndCocoaFrameWithoutCapturing() {
        var request = recording
        request.startInWindowMode = true
        var d = Driver()
        d.openSelector(request)
        let s = d.session
        let out = d.send(
            .mouseDown(s, DisplayID(1), DisplayPoint(x: 200, y: 200).viewPoint(displayHeight: 900), noMods))
        #expect(
            out == leaveEffects(s, .window) + [
                .answer(
                    SelectionTicket(1),
                    .window(WindowID(7), display: DisplayID(1), frame: Rect2D(x: 100, y: 500, width: 400, height: 300)))
            ])
        #expect(d.flow.phase == .idle)
    }

    @Test func anExternalCancelWhileSelectingAnswersCancelled() {
        var d = Driver()
        d.openSelector(recording)
        let s = d.session
        #expect(d.send(.externalCancel(.screenshot)) == [])
        #expect(
            d.send(.externalCancel(.recording)) == leaveEffects(s, .cancelled) + [
                .answer(SelectionTicket(1), .cancelled)
            ])
    }

    @Test func anExternalCancelWhileFreezingAnswersCancelledAndShowsNoOverlay() {
        var d = Driver()
        d.send(.select(SelectionTicket(1), recording))
        let s = d.session
        #expect(d.send(.externalCancel(.recording)) == [.answer(SelectionTicket(1), .cancelled)])
        #expect(d.flow.phase == .idle)
        #expect(d.send(.frozen(s, [frame(primary)], windows: [], pointer: pointerOnPrimary)) == [])
    }

    @Test func aFreezeFailureAnswersCancelled() {
        var d = Driver()
        d.send(.select(SelectionTicket(1), recording))
        #expect(
            d.send(.freezeFailed(d.session, .permissionDenied)) == [
                .showPermissionAlert, .answer(SelectionTicket(1), .cancelled),
            ])
        var e = Driver()
        e.send(.select(SelectionTicket(1), recording))
        #expect(
            e.send(.freezeFailed(e.session, .failed("x")))
                == [
                    .log(.capture, "failed recording: x"), .notify(title: "Capture failed", body: "x"),
                    .answer(SelectionTicket(1), .cancelled),
                ])
    }

    @Test func escapeAnswersCancelled() {
        var d = Driver()
        d.openSelector(recording)
        let s = d.session
        #expect(d.send(.key(s, .escape)) == leaveEffects(s, .cancelled) + [.answer(SelectionTicket(1), .cancelled)])
    }
}
