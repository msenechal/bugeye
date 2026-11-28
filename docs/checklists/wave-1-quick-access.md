# Wave 1 Quick Access manual checklist

Quick Access shows a floating thumbnail after each capture, with Copy, Save, Save As…, Reveal in Finder, Delete, drag-out and ⇧-click selection. CI already checked the logic, every string, the panel's properties, Esc, the drag URL after Save and that closed panels are freed. Only your Mac can check how it looks and feels, real focus return into your apps, real files, Finder, the Trash and the clipboard in other apps.

## Before you start

1. Quit the first build's Bugeye (menu bar icon ▸ Quit). Both use ⇧⌘3 and ⇧⌘4, and only one can have them.
2. Make sure Wave 1 Capture is installed (its wiring PR is on `main`). Get this branch and install:
   ```sh
   cd ~/path/to/bugeye
   git fetch origin && git checkout feat/wave1-quick-access-wiring && git pull
   make install
   ```
3. Screen Recording permission is granted to the new Bugeye (System Settings ▸ Privacy & Security ▸ Screen Recording), as for Capture's checklist.
4. Have Slack, Preview and a Finder window open, and TextEdit with a new empty document (for the focus tests).
5. For test G1, a USB stick you can unplug.

## Shortcuts

| Key or item | Where | Does |
|---|---|---|
| ⇧⌘3 | anywhere | captures the display under the pointer; a thumbnail appears |
| ⇧⌘4, drag | anywhere | captures an area; a thumbnail appears |
| Esc | with the pointer over a thumbnail | clears the ⇧-click selection, else dismisses that thumbnail |
| ✕ | thumbnail, top left | dismisses it |
| ⇧-click | thumbnail image | selects or deselects a screenshot |
| `Copy`, `Save` / `Save As…` | thumbnail strip | as named |
| ⋯ ▸ `Reveal in Finder`, ⋯ ▸ `Delete` | thumbnail strip, right | as named |
| Settings… (⌘,) ▸ `Quick Access` | Bugeye menu | the pane |
| Settings… ▸ `Capture` ▸ `Save to folder` | Bugeye menu | turns saving off, so captures stay temporary |

## How to check

```sh
# Saved captures, and temporary (unsaved) ones
ls -l ~/Pictures/Bugeye
ls -l ~/Library/Caches/dev.msenechal.bugeye/Captures

# A capture's identity survives Save (same id before and after) and a Save As… copy gets a new one
xattr -p dev.msenechal.bugeye.id "<file>"

# Quick Access settings
defaults read dev.msenechal.bugeye | grep quickAccess

# The log: show, dismiss <reason>, saved <name>, failed <action>
log show --last 10m --predicate 'subsystem == "dev.msenechal.bugeye" && category == "quickAccess"'
```

## Tests

### A. Look

1. Press ⇧⌘3.
   **Expected:** a 240 × 176 pt thumbnail at the bottom left of that screen, 16 pt from the edges: a dark gradient panel with 10 pt rounded corners and a faint light border; the capture fills the top part, cropped not squashed; a yellow ✕ on a dark circle at top left; a strip with `Copy` and `Save` sharing the width and a square `⋯`.
2. Click `⋯`.
   **Expected:** `Reveal in Finder`, then `Delete`, nothing else.
3. Take a capture of a dark window and one of a white page.
   **Expected:** both images read clearly inside the night chrome; text in the strip is light, legible.

### B. Stack

1. Press ⇧⌘3 five times, a second apart, on the laptop screen.
   **Expected:** four thumbnails at most on the built-in screen (it fits four), newest at the bottom; when a new one comes, the oldest fades out and the rest slide up smoothly.
2. On the external monitor, press ⇧⌘3 six times.
   **Expected:** five at most.
3. Settings… ▸ `Quick Access` ▸ `Position` ▸ `Bottom right`, then take a capture.
   **Expected:** the whole stack moves to the bottom right of that screen.
4. Move the pointer to the other display and take a capture.
   **Expected:** the whole stack moves to the display under the pointer.
5. Watch a thumbnail appear and leave.
   **Expected:** it fades in quickly (≈0.2 s) and fades out quickly; no flash, no jump.

### C. Timers

1. With `Auto-dismiss` at `5 seconds`, take a capture and don't touch it.
   **Expected:** it leaves after about 5 s.
2. Set `Never`, take a capture, wait a minute.
   **Expected:** it stays.
3. Set `60 seconds`, take a capture.
   **Expected:** it leaves after about a minute.
4. Back at `5 seconds`: take a capture and keep the pointer over it for 20 s, then move away.
   **Expected:** it stays while hovered and leaves a few seconds after you move away (the time left when you arrived).
5. Take two captures, ⇧-click the first one's image, wait 20 s, then click either image without ⇧.
   **Expected:** nothing leaves while the selection exists; after the plain click both get a full 5 s again.

### D. Hover and keys

1. In TextEdit, start typing. Take a capture with ⇧⌘3, move the pointer over the thumbnail, press Esc.
   **Expected:** the thumbnail fades out and the rest close the gap; TextEdit still shows its insertion point.
2. Take a capture, move the pointer over it, then away, and type without clicking.
   **Expected:** the letters go into TextEdit.

### E. Actions

1. Take a capture, click `Copy`, paste into Slack's message box, into a Finder window (⌘V) and into Preview (File ▸ New from Clipboard).
   **Expected:** Slack shows the image; Finder pastes the file; Preview opens the image.
2. Settings… ▸ `Capture` ▸ turn off `Save to folder`. Take a capture.
   **Expected:** the file is in `~/Library/Caches/dev.msenechal.bugeye/Captures`, not in `~/Pictures/Bugeye`; the strip says `Save`.
3. Click `Save`.
   **Expected:** the file moves to `~/Pictures/Bugeye` with the same name and the same `dev.msenechal.bugeye.id`; the button now says `Save As…`.
4. Click `Save As…`, pick the Desktop, keep the name, click Save.
   **Expected:** a copy on the Desktop with a different `dev.msenechal.bugeye.id`; no new thumbnail appears.
5. ⋯ ▸ `Reveal in Finder`.
   **Expected:** Finder opens with the file selected.
6. ⋯ ▸ `Delete` on a saved capture.
   **Expected:** the thumbnail leaves at once and the file is in the Trash. No confirmation.
7. With saving off, take a capture and ⋯ ▸ `Delete`.
   **Expected:** the temp file is gone (not in the Trash).
8. Drag a thumbnail's image to a Finder window, then into a Slack message.
   **Expected:** Finder gets a copy of the file; Slack attaches it. The thumbnail stays.
9. Save a capture, then drag it to Finder.
   **Expected:** the copy comes from the saved file (`~/Pictures/Bugeye`), not the temp one.

### F. Selection

1. Take three captures. ⇧-click the first and the third.
   **Expected:** each gets a 2 pt yellow border and a ✓ at top right; the strips stay `Copy` · `Save` (Combine comes in a later wave).
2. Press Esc with the pointer over one of them.
   **Expected:** the selection clears; no thumbnail leaves.
3. ⇧-click one again, then click an image without ⇧.
   **Expected:** the selection clears.
4. ⇧-click a screenshot, then click its ✕ and a strip button on another one.
   **Expected:** ✕ dismisses it; strip clicks do their action and never change the selection.

### G. Failures

1. Settings… ▸ General ▸ choose a folder on the USB stick; turn off `Save to folder`; take a capture; unplug the stick; click `Save`.
   **Expected:** a notification `Couldn't save to folder` / `/Volumes/<stick>/… is unavailable. The capture stays in the temporary folder.`; the thumbnail and its timer are unchanged.
2. Take a capture with saving off, delete its file in Finder (from the Captures folder), then click `Copy`.
   **Expected:** a notification `Couldn't copy` / `<file name> is missing or unreadable.`
3. Then ⋯ ▸ `Delete` on the same thumbnail.
   **Expected:** the thumbnail leaves, no notification.
4. Set General back to `~/Pictures/Bugeye/`.

### H. Settings pane

1. Settings… ▸ `Quick Access`.
   **Expected:** the tab comes after `Capture`; two pickers: `Auto-dismiss` (`Never`, `5 seconds`, `10 seconds`, `30 seconds`, `60 seconds`) and `Position` (`Bottom left`, `Bottom right`).
2. Change both, quit Bugeye, relaunch, reopen the pane.
   **Expected:** both choices are kept (`defaults read dev.msenechal.bugeye | grep quickAccess` shows them).

## When you're done

Say "all good", or list the numbers that failed (for example "C4, E8") with what you saw.
