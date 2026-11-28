# Wave 1 Capture ledger

Plan: `docs/plans/2026-11-28-wave-1-capture.md` · Spec: `docs/specs/2026-11-27-wave-1-capture.md` · Branches: `feat/wave1-capture-<slice>`

Trust this file and `git log` over memory.

## Tasks

| Task | Status | Commit | CI / notes |
|---|---|---|---|
| 1 | done | 8aef1be | draft PR #6 (`feat/wave1-capture-core`) |
| 2 | done | c899f0d | fakes' self-tests seen failing on the missing port names |
| 3 | done | d49a562 | |
| 4 | done | 0f21bd7 | |
| 5–6 | done | e1c55e8 | one test had a wrong expected display (its window centre was on the other display); test fixed |
| 7 | done | 1a3777d | 46 flow tests; the invariant checker was seen failing on two deliberate mutations (Esc not released on leave; `frozen` ignoring its session) before being kept |

## Rulings

Plan rulings P1–P11 are in the plan. Every later deviation is recorded here as `Ruling: <what and why> (cost if wrong: …)`.

- Ruling: `ScreenSource` keeps `displays()` beside the new `freeze(displays:)` and `captureWindow(_:pixelSize:)` (C8): full screen needs the display under the pointer before it freezes. `ScreenSourceError` is the port's error type (`permissionDenied`, `displayNotFound`, `windowNotFound`, `failed(String)`); the adapter maps ScreenCaptureKit errors into it. (cost if wrong: none.)
- Ruling: `CaptureStrings` starts in slice 1 with the six `Capture failed` texts, because `CaptureFlow` posts them; slice 2 adds the rest. (cost if wrong: none.)
- Ruling: in window mode every display's overlay gets the hovered window's rect in its own display-local space (the view clips it), and redraws all displays when the hovered window changes, so a window spanning two displays is highlighted on both. (cost if wrong: none.)
- Ruling: a freeze that answers no frames counts as `displayNotFound` (`Capture failed` / `The display was disconnected.`); a selector request then answers `.cancelled`. (cost if wrong: low; unreachable with a connected display.)
- Ruling: a click on a window whose centre is on no display, for a selector request without `windowNeedsDisplayCentre`, answers `.window` with the clicked display. (cost if wrong: low; Recording always sets the flag.)

## Waiting on user

## Backlog:
