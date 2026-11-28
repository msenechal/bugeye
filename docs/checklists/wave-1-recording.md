# Wave 1 Recording manual checklist

This pass checks the screen recorder on your Mac: ⇧⌘5, the options bar, the countdown, the recording itself, the overlays, window recording, the result and its thumbnail, and the gating with screenshots. CI already checked the state machine, the timeline and its privacy rules, the writer, the converter and the window properties; the Mac batch checked sizes, colour tags, audio sync and the timeline's timing. Only your eyes and hands can check what follows.

## Before you start

1. Quit the first build's Bugeye (`/Applications/Bugeye.app`), so ⇧⌘5 reaches the new one.
2. Turn off macOS's own ⇧⌘5: System Settings → Keyboard → Keyboard Shortcuts… → Screenshots → untick "Screenshot and recording options".
3. Build and install the wiring branch once Capture's and Quick Access's wiring PRs have landed on `main` and been merged into it (until then ⇧⌘5 can't open a selection):
   ```sh
   cd ~/path/to/bugeye
   git fetch origin && git checkout feat/wave1-recording-wiring && git pull
   make install
   ```
4. Screen Recording: System Settings → Privacy & Security → Screen & System Audio Recording → turn on Bugeye (the new one, in `~/Applications`). Relaunch Bugeye if asked.
5. Leave Microphone, Camera and Accessibility undecided for now: test B asks for them.
6. Have a second display connected if you can (test A4, G2), and some music or a video ready to play (test D5).

## Shortcuts

| Key or item | Where | Does |
|---|---|---|
| ⇧⌘5 | anywhere | starts a recording selection; while recording, stops |
| Record Screen | the Bugeye menu | the same as ⇧⌘5 |
| drag | the selection overlay | selects an area |
| click | the selection overlay | selects the whole display under the pointer |
| Return | the selection overlay | the last recording area |
| Space | the selection overlay | window mode (click a window) |
| Esc, right-click, ⇧⌘5 | the selection overlay, the bar, the countdown | cancels |
| ● Record (or Return) | the options bar | starts the 3 · 2 · 1 countdown |
| ✕ (or Esc) | the options bar | cancels |
| Pause / Resume, Stop, Restart, Discard | the ● menu (the Bugeye menu while recording) | as named |
| ⇧⌘3, ⇧⌘4 | anywhere | Capture's screenshots |
| ⌘Q | the Bugeye menu (Quit Bugeye) | quits; waits for a recording to be saved |

## How to check

```sh
ls -l ~/Pictures/Bugeye                                        # delivered recordings
ls -l ~/Library/Caches/dev.msenechal.bugeye/Recordings         # takes in progress (empty when idle)
ls -l ~/Library/Caches/dev.msenechal.bugeye/Captures           # the temp folder (Save to folder off)
ls -l ~/Library/Application\ Support/dev.msenechal.bugeye/Timelines   # one .timeline.jsonl per recording
xattr -p dev.msenechal.bugeye.id ~/Pictures/Bugeye/Recording*.mp4     # each recording's capture ID
log show --last 10m --predicate 'subsystem == "dev.msenechal.bugeye"' --info   # recording and timeline lines
```

## Tests

### A. Starting

1. Press ⇧⌘5. Drag an area over part of the screen.
   **Expected:** the hint at the top reads "Drag an area · Click to record this display · Space: pick a window · Esc to cancel"; after the drag a white dashed border surrounds the area and the options bar opens 12 pt under it.
2. Press Esc. Press ⇧⌘5 again and click once anywhere.
   **Expected:** the bar disappears on Esc; the click selects the whole display: the border sits just inside the display's edges and the bar sits inside its bottom edge.
3. Press Esc. Press ⇧⌘5, then Return.
   **Expected:** the area from test A1 is selected again.
4. Press Esc. Press ⇧⌘5, then Space, then click a window (on your second display if you have one).
   **Expected:** window mode highlights windows; the click selects that window and the border surrounds it.
5. Cancel each way once: Esc on the overlay, right-click on the overlay, ⇧⌘5 on the overlay, ✕ on the bar, Esc on the bar after clicking one of its toggles.
   **Expected:** each one closes everything; nothing is left on screen; no file appears in `~/Pictures/Bugeye`.

### B. The bar

1. Start a selection. Turn on Mic.
   **Expected:** macOS asks for microphone access. Allow it: a picker appears beside Mic with "Default" and your microphones.
2. Turn on Cam.
   **Expected:** macOS asks for camera access. Allow it: a round, mirrored bubble with a white border appears at the bottom-right of the area, 24 pt in.
3. Turn on Keys.
   **Expected:** macOS shows the Accessibility prompt. Hovering Keys shows "Needs Accessibility: allow Bugeye in System Settings → Privacy & Security → Accessibility, then try again." The bar reads permissions when it opens: after allowing, press Esc and start a new selection to see Keys enabled.
4. Hover each control.
   **Expected:** "Start recording (Return)", "Record your voice", "Record the sound your Mac plays", "Show your camera in a bubble", "Show the shortcuts you press", "Highlight mouse clicks", "Recording options", "Cancel (Esc)".
5. Open ⚙ and Cam's ⌄.
   **Expected:** ⚙ has "Frame rate" ▸ "30 fps" / "60 fps" and "Quality" ▸ "Standard" / "High"; ⌄ has "Size" ▸ "Small" / "Medium" / "Large" (and "Camera" ▸ names with more than one camera). No MP4/GIF control.
6. Make the bar wider (turn Mic on) with an area near the bottom of the screen.
   **Expected:** the bar moves above the area when it doesn't fit under it, and stays centred as it widens.
7. Quit Bugeye, reset the permissions, relaunch, and deny them this time:
   ```sh
   tccutil reset Microphone dev.msenechal.bugeye; tccutil reset Camera dev.msenechal.bugeye
   ```
   **Expected:** after denying, Mic and Cam are greyed out with "Microphone access is off. Turn it on in System Settings → Privacy & Security → Microphone." and "Camera access is off. Turn it on in System Settings → Privacy & Security → Camera." (Turn both back on in System Settings afterwards.)

### C. The countdown

1. Select an area and press Record.
   **Expected:** the bar closes; a dark 140 × 140 pt square in the middle of the area shows 3, 2, 1 in yellow, one second each; the microphone indicator (if Mic is on) lights during it.
2. Start again and press Esc during the countdown; then again and press ⇧⌘5 during it.
   **Expected:** both cancel: no border, no file, the menu bar shows the normal Bugeye icon.

### D. Recording

1. Record an area for about 15 s.
   **Expected:** when 1 runs out the border turns solid red and the menu bar shows a red "● 00:00" counting up in steady digits.
2. Open the ● menu and leave it open for 5 s.
   **Expected:** "Pause", "Stop ⇧⌘5", a separator, "Restart", "Discard"; the timer keeps counting while the menu is open.
3. Choose Pause, wait 5 s, choose Resume.
   **Expected:** "❙❙ mm:ss" with the time frozen while paused; the five seconds are missing from the result.
4. Open the ● menu and choose Stop.
   **Expected:** the border, rings, badge and bubble disappear at once; an hourglass shows in the menu bar, its menu reads "Finishing…" then "Finishing… <n> %"; then a Quick Access thumbnail appears with "▶ 00:10" (or the length you recorded).
5. Record again with Mic and System audio on, speak and play music, then press ⇧⌘5 to stop.
   **Expected:** recording stops the same way; the file plays in QuickTime with your voice and the music on one track.
6. Record, then press ⌘Q while it is finishing.
   **Expected:** Bugeye waits, delivers the recording (it is in `~/Pictures/Bugeye`), then quits.

### E. Restart and Discard

1. Record 5 s, choose Restart.
   **Expected:** no question; a new 3 · 2 · 1 countdown; the first take leaves no file.
2. Record 15 s, choose Restart.
   **Expected:** Bugeye asks "Restart this recording?" / "What you've recorded so far will be thrown away." with "Restart" and "Cancel". Cancel keeps recording; Restart starts a new countdown.
3. Record 5 s, choose Discard; then record 15 s and choose Discard.
   **Expected:** under 10 s it stops at once and saves nothing; over 10 s it asks "Discard this recording?" / "Nothing will be saved." with "Discard" and "Cancel".

### F. Overlays

1. Record with Clicks on; left-click and right-click inside the area.
   **Expected:** in the video, a yellow ring for each left click and a pink one for each right click, growing and fading in half a second. Clicks on the bubble don't ring.
2. Record with Keys on and "Show all keystrokes (not just shortcuts)" off (Settings → Recording); press ⌘S, ⇧⌘3, type a word, then ⌘Z three times quickly.
   **Expected:** in the video, a dark badge 40 pt above the bottom of the area shows "⌘ S", "⇧ ⌘ 3" and "⌘ Z ×3"; the typed word never appears.
3. Turn "Show all keystrokes (not just shortcuts)" on and type a word while recording.
   **Expected:** each letter shows in the badge.
4. With Cam on: drag the bubble to the top-left, release it, double-click it three times, switch camera in ⌄ (if you have two).
   **Expected:** it snaps to the nearest corner; double-click cycles Medium → Large → Small → Medium (it starts at Medium) and the next recording starts at the size you left; switching camera keeps the corner; the bubble is in the video.
5. Open the ● menu and a Quick Access thumbnail while recording.
   **Expected:** neither is in the video; the border, bar and countdown never are.

### G. Window recording

1. Record a window (⇧⌘5, Space, click it). Move the window around, open one of its menus, and open a sheet (e.g. a Save dialog).
   **Expected:** the video follows the window at its starting size; the menu is visible in the video; tell me whether the sheet is (a known limit of the window server).
2. Move the window to your other display while recording.
   **Expected:** the border follows; the video shows nothing new once the window has left the recorded display.

### H. The result

1. Look in `~/Pictures/Bugeye`.
   **Expected:** files named like "Recording 2026-11-28 at 14.03.12.mp4" (your date and time).
2. Turn off Settings → Capture → "Save to folder", record, then look in the temp folder.
   **Expected:** the recording is in `~/Library/Caches/dev.msenechal.bugeye/Captures`, and Quick Access's Save moves it.
3. With "Copy to clipboard" on, record, then paste into a Finder window and into Slack.
   **Expected:** the movie file is pasted in both.
4. Optional: fill the disk until less than 50 MB is free beyond the movie's size (or ask me for a debug switch), record and stop.
   **Expected:** "Recording saved as a QuickTime movie" / "There wasn't enough space (or a problem) to convert it to MP4. The .mov plays in QuickTime." and a `.mov` with its thumbnail.

### I. Gating

1. Press ⇧⌘5 and, while the overlay or the bar is up, press ⇧⌘4.
   **Expected:** nothing happens: no crosshair, no screenshot, and the recording overlay or bar stays as it was.
2. While recording, press ⇧⌘4 and take a screenshot.
   **Expected:** the screenshot works, and its overlay isn't in the recording.

### J. The Recording pane

1. Open Settings → Recording.
   **Expected:** "Video format" with "H.264 (plays everywhere)" and "HEVC (smaller, full 5K/6K resolution)", the note "H.264 recordings of displays larger than 4K are scaled down to 4096 × 2304."; "Show all keystrokes (not just shortcuts)" with the note "Off: only presses with ⌘ or ⌃ appear, so what you type (including ⌥ symbols) stays private."
2. Choose HEVC, record, and check the file in QuickTime's Movie Inspector (⌘I).
   **Expected:** the codec is HEVC.

## When you're done

Say "all good", or list the test numbers that failed (for example "D3, F2: the badge showed the typed word").
