# Wave 1 Capture manual checklist

Capture brings back ⇧⌘3, ⌥⇧⌘3, ⇧⌘4 (with Space for a window and Return for the last area), the selection overlay, output (save, copy, announce), the Screen Recording alert and the Shortcuts pane. CI checked the logic on Linux and the AppKit code on a hosted Mac; only your Mac can check real capture, the overlay's look and feel, permissions and the keys against the old app. Quick Access isn't on `main` yet, so no thumbnail appears after a capture: check the files and the clipboard instead.

## Before you start

1. Get the wiring branch and install it (it signs with "Bugeye Dev", so the permission survives reinstalls):
   ```sh
   cd ~/path/to/bugeye
   git fetch origin && git checkout feat/wave1-capture-wiring && git pull
   make install
   ```
2. **Quit the old Bugeye** (`/Applications/Bugeye.app`) for every section except I.4: it holds ⇧⌘3 and ⇧⌘4.
3. Grant Screen Recording to the new Bugeye: System Settings → Privacy & Security → Screen & System Audio Recording → turn on Bugeye (the one in `~/Applications`), then relaunch it. Section H resets this on purpose.
4. Plug in the 1× external monitor beside the Retina screen. Open a few windows (Finder, Safari) on both displays.
5. In System Settings → Keyboard → Keyboard Shortcuts → Screenshots, note which macOS shortcuts are on (I.3 uses this).

## Shortcuts

| Key or item | Does |
|---|---|
| ⇧⌘3 / menu **Capture Fullscreen** | PNG of the display under the pointer |
| ⌥⇧⌘3 | One PNG per display, same timestamp |
| ⇧⌘4 / menu **Capture Area** | The area overlay on every display |
| menu **Capture Window** | The overlay, already in window mode |
| Space (overlay up) | Toggles window mode |
| Return or keypad Enter (overlay up) | Recaptures the last area |
| ⇧ while dragging | Locks the axis that moved less |
| ⌥ while dragging | Resizes from the centre |
| Esc, right-click | Cancels |
| Settings… (⌘,) → **Capture**, **Shortcuts** | The two new panes |

## How to check

```sh
ls -lt ~/Pictures/Bugeye | head                                  # saved captures, newest first
ls -lt ~/Library/Caches/dev.msenechal.bugeye/Captures | head     # temp captures (saving off, folder unplugged)
xattr -p dev.msenechal.bugeye.id ~/Pictures/Bugeye/<file>.png   # every capture has an id
sips -g pixelWidth -g pixelHeight ~/Pictures/Bugeye/<file>.png   # pixel size
defaults read dev.msenechal.bugeye | grep capture               # capture.* settings, capture.lastArea
log show --last 10m --predicate 'subsystem == "dev.msenechal.bugeye"'   # begin/finish, freeze ms, saved, hotkeys
```

If an overlay ever stays stuck on screen, run the `log show` line **before** killing the app, and send it.

## Tests

### A. Full screen and every display

1. Move the pointer onto the Retina display and press ⇧⌘3.
   **Expected:** a new `Screenshot YYYY-MM-DD at HH.MM.SS.png` in `~/Pictures/Bugeye`, at the Retina display's full pixel size (`sips`). Pasting in Preview (File → New from Clipboard) shows the same image. No Bugeye window appears in it.
2. Move the pointer onto the external display and press ⇧⌘3.
   **Expected:** a PNG at the external display's size (1×).
3. Press ⌥⇧⌘3.
   **Expected:** two files with the **same** time: `… HH.MM.SS.png` (the Retina display, the primary) and `… HH.MM.SS (2).png` (the external). The log shows `freeze 2 displays in <n> ms` once.

### B. Area overlay: freeze, dim, crosshair, loupe, readout, ⇧, ⌥

1. Play a video in Safari, then press ⇧⌘4.
   **Expected:** the video stops moving on every display (frozen); the crosshair cursor, two thin white lines across the display and the round loupe appear at the pointer **before** you move it.
2. Move the pointer around, including to the right and bottom edges.
   **Expected:** the loupe sits below-right of the pointer, flips to the other side near the edges, never leaves the screen; it shows sharp (unsmoothed) pixels with a red square on the pointer's pixel. Moving feels smooth on both displays.
3. Drag a selection.
   **Expected:** everything outside is dimmed, a thin white border surrounds it, and a `W × H` readout in points follows its bottom-right corner, staying on screen.
4. During a drag, hold ⇧ and keep moving mostly sideways; then release ⇧.
   **Expected:** the height stops changing while ⇧ is held, and follows the pointer again after.
5. During a drag, hold ⌥.
   **Expected:** the selection grows from its centre.
6. Release on a selection of at least 4 × 4 pt.
   **Expected:** the overlay closes at once; a PNG of exactly that area (the frozen frame, video still) is saved and on the clipboard.
7. Press ⇧⌘4 and click once without dragging, then drag a 2 × 2 pt selection.
   **Expected:** nothing happens; the overlay stays. Press Esc to leave.

### C. Multi-display drags and keys

1. Press ⇧⌘4, start a drag on the Retina display and move onto the external display.
   **Expected:** the selection stays clipped to the Retina display; ⇧ and ⌥ still work while the pointer is over the other display.
2. Press ⇧⌘4, move the pointer to the external display (no button down) and press Space.
   **Expected:** window mode toggles there (the external display received the key).

### D. Window mode and shadow

1. Menu **Capture Window**, hover windows on both displays.
   **Expected:** the whole display is dimmed; the hovered window shows undimmed with a light blue fill and a blue border; no crosshair or loupe; Bugeye's own windows are never highlighted.
2. Click empty desktop.
   **Expected:** a beep; the overlay stays. Press Esc.
3. Capture a window on the Retina display, then one on the external display.
   **Expected:** each PNG has the window with its shadow on a transparent background (open in Preview, which shows transparency as a checkerboard), sharp at the display's full scale, not soft.

### E. Return on each display, after a relaunch

1. Press ⇧⌘4 and capture an area on the external display.
2. Quit Bugeye and open it again. Press ⇧⌘4, then Return.
   **Expected:** the same area on the external display is captured again from the new frozen frame.
3. Press ⇧⌘4, then keypad Enter.
   **Expected:** the same again.
4. Unplug the external monitor, press ⇧⌘4, then Return.
   **Expected:** a beep; the overlay stays. Press Esc and plug the monitor back in.

### F. Esc, right-click, display unplugged

1. Press ⇧⌘4, then Esc.
   **Expected:** the overlay closes; focus goes back to the app you were in (type to check).
2. Press ⇧⌘4, then right-click.
   **Expected:** the overlay closes.
3. Press ⇧⌘4, click into another app's window on the other display is impossible (the overlay covers it); instead, unplug the external monitor while the overlay is up.
   **Expected:** the overlay closes on every display (`finish cancelled` in the log).
4. After all of the above, run the `log show` line.
   **Expected:** every `begin screenshot overlays [...]` has a matching `finish ... overlays [...]` with the same numbers; no `closing a leftover overlay`.

### G. Output: names, save off, folder unplugged, downscale, pasting

1. Press ⇧⌘3 twice within one second.
   **Expected:** the second file is named `… (2).png`; the first is untouched.
2. Settings… → **Capture** → turn off **Save to folder**; press ⇧⌘3.
   **Expected:** nothing new in `~/Pictures/Bugeye`; the file is in `~/Library/Caches/dev.msenechal.bugeye/Captures`; the clipboard has the image. Turn **Save to folder** back on.
3. Settings… → **General** → choose a folder on a USB stick, then unplug the stick and press ⇧⌘3.
   **Expected:** a banner `Couldn't save to folder` / `/Volumes/<name>/… is unavailable. The capture is kept temporarily; use Save in Quick Access.`; the file is in the temp folder. Choose `~/Pictures/Bugeye` again.
4. Turn on **Downscale Retina captures to 1×**; press ⇧⌘3 on the Retina display.
   **Expected:** the PNG is half the pixel size, with colours that look the same as before. Turn it off.
5. Turn off **Copy to clipboard**, press ⇧⌘3, and paste in TextEdit.
   **Expected:** the previous clipboard content, not the new capture. Turn it back on.
6. After a ⇧⌘4 area capture, paste into Slack, into a Finder window (⌘V) and into Preview (File → New from Clipboard).
   **Expected:** Slack shows the image; Finder makes a copy of the file; Preview opens the image.

### H. Permission alert

1. Run `tccutil reset ScreenCapture dev.msenechal.bugeye`, then press ⇧⌘4.
   **Expected:** no overlay; the alert `Screen Recording permission needed` / `Enable Bugeye under Privacy & Security → Screen & System Audio Recording, then relaunch the app.` with `Open System Settings`, `Relaunch`, `Cancel`.
2. Click **Open System Settings**.
   **Expected:** Bugeye appears in the Screen & System Audio Recording list, and that pane opens. Turn Bugeye on.
3. Press ⇧⌘4 again and click **Relaunch** in the alert (or the one macOS shows).
   **Expected:** Bugeye quits and starts again by itself (the one in `~/Applications`, not the old one); ⇧⌘4 then works.

### I. Shortcuts pane: change, clear, duplicate, macOS conflict, Restore Defaults

1. Settings… → **Shortcuts**.
   **Expected:** rows `Capture Fullscreen` ⇧⌘3, `Capture All Displays` ⌥⇧⌘3, `Capture Area` ⇧⌘4 (and Recording's row once Recording is on `main`), the footer `Click a shortcut, then type the new keys. Delete clears it; Esc keeps the old one.` and **Restore Defaults**.
2. Click the Capture Area field; it shows `Type a shortcut`. Press ⌃⌥X. Then press ⌃⌥X anywhere.
   **Expected:** the field shows `⌃⌥X` and the area overlay opens; the status menu's Capture Area shows ⌃⌥X. Press Esc.
3. Click the field again and press Esc; click again and press Delete.
   **Expected:** Esc keeps `⌃⌥X`; Delete shows `None`, and the menu shows no key for Capture Area.
4. Click the field and press ⇧⌘3.
   **Expected:** `⇧⌘3 is already used by Capture Fullscreen.` in orange; nothing saved. Then press ⇧4 in the field: `Use a letter or digit with at least one of ⌘, ⌥ or ⌃.`
5. If a macOS screenshot shortcut is on for ⇧⌘3 or ⇧⌘4 (Before you start, step 5), relaunch Bugeye.
   **Expected:** a banner `macOS screenshot shortcuts are still on` / `Disable ⇧⌘3 and ⇧⌘4 in System Settings → Keyboard → Keyboard Shortcuts → Screenshots, so Bugeye receives them.` (only the keys that are on), and the row says `macOS also uses ⇧⌘3 for its own screenshots and gets it first. …` with **Keyboard Shortcuts…**, which opens that settings page.
6. Click **Restore Defaults**.
   **Expected:** all three rows back to ⇧⌘3, ⌥⇧⌘3, ⇧⌘4, all working.
7. Start the old Bugeye, then quit and reopen the new one.
   **Expected:** a banner `Some Bugeye shortcuts are taken` / `⇧⌘3, ⌥⇧⌘3 and ⇧⌘4 are taken by other apps. Choose others in Bugeye Settings → Shortcuts.` (the keys the old app holds); those rows show `None` with `⇧⌘4 is taken by another app, so this action has no shortcut. Quit that app and press Try Again, or choose another shortcut.` and **Try Again**; the status menu shows no keys for them. Quit the old app, press **Try Again** on each row.
   **Expected:** the keys show again and work.

When you're done, say "all good", or list the numbers that failed (e.g. "B.2, G.4").
