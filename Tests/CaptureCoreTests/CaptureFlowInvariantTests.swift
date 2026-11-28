import BugeyeCore
import CaptureCore
import Foundation
import Testing

/// A seeded generator, so a failing sequence can be replayed from its seed.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Checks I1–I9 (Capture §6) over random event sequences.
struct InvariantChecker {
    var flow = CaptureFlow(ownPID: ownPID)
    var rng: SplitMix64
    var nextTicket = 1
    var sessionsSeen: [SessionID] = []
    var returnedToIdle: [SessionID] = []
    var escapeHeld: Set<SessionID> = []
    var overlaysUp: Set<SessionID> = []
    var closes: [SessionID: Int] = [:]
    var unregisters: [SessionID: Int] = [:]
    var begins: [SessionID: Int] = [:]
    var finishes: [SessionID: Int] = [:]
    var selectingSessions: Set<SessionID> = []
    var tickets: [SelectionTicket] = []
    var answers: [SelectionTicket: Int] = [:]
    var failures: [String] = []

    init(seed: UInt64) { rng = SplitMix64(seed: seed) }

    mutating func fail(_ message: String) { failures.append(message) }

    func randomPoint(_ rng: inout SplitMix64) -> ViewPoint {
        ViewPoint(x: Double.random(in: -200...2200, using: &rng), y: Double.random(in: -200...1300, using: &rng))
    }

    mutating func randomEvent() -> FlowEvent {
        let live = flow.session ?? SessionID(0)
        let stale = SessionID(Int.random(in: 0...max(1, sessionsSeen.count), using: &rng))
        let session = Bool.random(using: &rng) || Int.random(in: 0..<4, using: &rng) > 0 ? live : stale
        let display = [primary.id, external.id, DisplayID(5)].randomElement(using: &rng)!
        let mods = Modifiers(shift: Bool.random(using: &rng), option: Bool.random(using: &rng))
        let frames = [[frame(primary), frame(external)], [frame(external)], [frame(primary)], []].randomElement(
            using: &rng)!
        let error = [ScreenSourceError.permissionDenied, .displayNotFound, .windowNotFound, .failed("x")]
            .randomElement(using: &rng)!
        switch Int.random(in: 0..<20, using: &rng) {
        case 0:
            return .request(
                CaptureRequestKind.allCases.randomElement(using: &rng)!,
                permitted: Int.random(in: 0..<5, using: &rng) > 0,
                activityAllows: Int.random(in: 0..<5, using: &rng) > 0, pointer: pointerOnPrimary,
                lastArea: Bool.random(using: &rng)
                    ? StoredArea(
                        display: primary.id, rect: Rect2D(x: 10, y: 10, width: 50, height: 50),
                        displaySize: primary.pointSize) : nil)
        case 1:
            let ticket = SelectionTicket(nextTicket)
            nextTicket += 1
            tickets.append(ticket)
            return .select(
                ticket,
                SelectionRequest(
                    purpose: .recording, startInWindowMode: Bool.random(using: &rng),
                    clickSelectsDisplay: Bool.random(using: &rng), windowNeedsDisplayCentre: Bool.random(using: &rng),
                    lastArea: Bool.random(using: &rng)
                        ? StoredArea(
                            display: external.id, rect: Rect2D(x: 0, y: 0, width: 9, height: 9),
                            displaySize: external.pointSize)
                        : nil))
        case 2: return .externalCancel(Bool.random(using: &rng) ? .recording : .screenshot)
        case 3, 4:
            return .frozen(session, frames, windows: [ownWindow, otherWindow, offWindow], pointer: pointerOnPrimary)
        case 5: return .freezeFailed(session, error)
        case 6: return .pointerMoved(session, display, randomPoint(&rng))
        case 7: return .pointerEntered(session, display, buttonDown: Bool.random(using: &rng))
        case 8, 9: return .mouseDown(session, display, randomPoint(&rng), mods)
        case 10, 11: return .mouseDragged(session, display, randomPoint(&rng), mods)
        case 12, 13: return .mouseUp(session, display, randomPoint(&rng))
        case 14: return .rightMouseDown(session)
        case 15: return .key(session, [KeyPress.escape, .space, .return].randomElement(using: &rng)!)
        case 16: return Bool.random(using: &rng) ? .globalEscape : .displaysChanged
        case 17: return .windowCaptured(session, time: freezeTime)
        case 18: return .windowCaptureFailed(session, error)
        default: return .delivered(session, notices: [])
        }
    }

    mutating func step(_ event: FlowEvent) {
        let before = flow.phase
        let beforeSession = flow.session
        let effects = flow.handle(event)
        let after = flow.phase
        if let s = flow.session, !sessionsSeen.contains(s) { sessionsSeen.append(s) }
        if before != .idle, after == .idle, let s = beforeSession { returnedToIdle.append(s) }
        if before == .idle, after != .idle, let s = flow.session, returnedToIdle.contains(s) {
            fail("I4: session \(s) reused")
        }
        if after == .selecting, let s = flow.session { selectingSessions.insert(s) }

        // I7: an event of a session that isn't live produces nothing but a sweep.
        if let tagged = Self.session(of: event), tagged != beforeSession,
            effects.contains(where: { $0 != .sweepLeftovers })
        {
            fail("I7: \(event) → \(effects)")
        }
        for effect in effects {
            switch effect {
            case .showOverlays(let s, _, _):
                if after != .selecting { fail("I1: showOverlays outside selecting") }
                overlaysUp.insert(s)
            case .makeKey:
                if after != .selecting { fail("I1: makeKey outside selecting") }
                if case .pointerEntered(_, _, true) = event { fail("I1: makeKey with a button down") }
            case .closeOverlays(let s):
                closes[s, default: 0] += 1
                overlaysUp.remove(s)
            case .registerEscape(let s): escapeHeld.insert(s)
            case .unregisterEscape(let s):
                unregisters[s, default: 0] += 1
                escapeHeld.remove(s)
            case .logSelectionBegin(let s, _): begins[s, default: 0] += 1
            case .logSelectionFinish(let s, _): finishes[s, default: 0] += 1
            case .answer(let ticket, _): answers[ticket, default: 0] += 1
            default: break
            }
        }
        // I1, I3: overlays and the Esc hotkey exist exactly while selecting, for the live session only.
        let live: Set<SessionID> = after == .selecting ? [flow.session!] : []
        if overlaysUp != live { fail("I1: overlays \(overlaysUp) in \(after) after \(event)") }
        if escapeHeld != live { fail("I3: escape \(escapeHeld) in \(after) after \(event)") }
        // I2: leaving selecting closes and unregisters exactly once.
        if before == .selecting, after != .selecting, let s = beforeSession {
            if closes[s] != 1 || unregisters[s] != 1 { fail("I2: session \(s) closed \(closes[s] ?? 0)×") }
        }
        // I6: the selection stays inside its display.
        for display in [primary, external] {
            if let selection = flow.overlay(for: display.id)?.selection {
                let bounds = Rect2D(x: 0, y: 0, width: display.frame.width, height: display.frame.height)
                if selection.raw.minX < 0 || selection.raw.minY < 0 || selection.raw.maxX > bounds.maxX
                    || selection.raw.maxY > bounds.maxY
                {
                    fail("I6: \(selection) outside \(display.id)")
                }
            }
        }
    }

    /// Ends whatever is running.
    mutating func drain() {
        for _ in 0..<5 {
            guard let s = flow.session else { return }
            switch flow.phase {
            case .freezing: step(.freezeFailed(s, .failed("drain")))
            case .selecting: step(.globalEscape)
            case .finishing:
                step(.windowCaptured(s, time: freezeTime))
                step(.delivered(s, notices: []))
            case .idle: return
            }
        }
    }

    mutating func checkEnd() {
        if flow.phase != .idle { fail("I4: not idle after draining") }
        if Set(returnedToIdle).count != returnedToIdle.count { fail("I4: a session returned to idle twice") }
        if Set(returnedToIdle) != Set(sessionsSeen) { fail("I4: sessions \(sessionsSeen) returned \(returnedToIdle)") }
        for s in selectingSessions where finishes[s] != 1 || begins[s] != 1 {
            fail("I5/I8: session \(s) began \(begins[s] ?? 0)× finished \(finishes[s] ?? 0)×")
        }
        for ticket in tickets where answers[ticket] != 1 {
            fail("I9: ticket \(ticket) answered \(answers[ticket] ?? 0)×")
        }
    }

    static func session(of event: FlowEvent) -> SessionID? {
        switch event {
        case .pointerMoved(let s, _, _), .pointerEntered(let s, _, _), .mouseDown(let s, _, _, _),
            .mouseDragged(let s, _, _, _), .mouseUp(let s, _, _), .rightMouseDown(let s), .key(let s, _),
            .frozen(let s, _, _, _), .freezeFailed(let s, _), .windowCaptured(let s, _), .windowCaptureFailed(let s, _),
            .delivered(let s, _):
            s
        default: nil
        }
    }
}

@Suite struct CaptureFlowInvariantTests {
    @Test(arguments: 1...200)
    func invariantsHoldOverRandomEventSequences(seed: Int) {
        var checker = InvariantChecker(seed: UInt64(seed))
        for _ in 0..<300 {
            let event = checker.randomEvent()
            checker.step(event)
        }
        checker.drain()
        checker.checkEnd()
        #expect(checker.failures.isEmpty, "seed \(seed): \(checker.failures.prefix(3))")
    }
}
