# Wave 1 Editor manual checklist

This pass covers the annotation editor: opening, the eleven tools, text, options, the frame, undo, zoom and output. CI already checked the model, the undo rules, the display lists, the blur maths, the save and xattr rules, and the window plumbing. Only your Mac can check the feel, the real menus and Dock, the real clipboard and drag targets, and speed on a big capture.

Run it on the Editor wiring PR's build (`feat/wave1-editor-wiring`), once Capture's and Quick Access's wiring PRs are on `main` (contracts §9).

## Before you start

1. Quit the old Bugeye and the Wave 0 build, if either is running.
2. Get the branch, rebased on `main`, and install it:
   ```sh
   cd ~/path/to/bugeye
   git fetch origin && git checkout feat/wave1-editor-wiring && git pull
   make install
   ```
3. Have Screen Recording permission for the new Bugeye, and macOS's own ⇧⌘3 / ⇧⌘4 screenshot shortcuts turned off (Capture's checklist sets both up).
4. Prepare:
   - a window with some text on screen (Safari on any article);
   - a 5K display, or a capture of a full Retina screen, for test J;
   - Slack open for tests H3 and H5.

## Shortcuts

| Key or item | Where | Does |
|---|---|---|
| ⇧⌘4 | anywhere | Capture Area (Capture) |
| ⇧⌘4, then Space | anywhere | Capture Window (Capture) |
| ⇧⌘3 | anywhere | Capture Fullscreen (Capture) |
| Edit, or a double-click | Quick Access thumbnail | opens the editor |
| Open Last Capture | Bugeye status menu | opens the newest capture |
| V C A R O L T P H B N | the canvas | Select, Crop, Arrow, Rectangle, Ellipse, Line, Text, Pen, Highlighter, Blur / Pixelate, Numbered step |
| ⇧ while dragging | the canvas | square, circle, 45° |
| Esc | the canvas | cancels a drag, else deselects; cancels typing |
| ⌫ or ⌦ | the canvas | deletes the selection |
| Return / ⌥Return | text | commits / new line |
| ⌘Z / ⇧⌘Z | anywhere in the editor | Undo / Redo |
| ⌘= ⌘− ⌘1 ⌘0 | View menu | Zoom In, Zoom Out, Actual Size, Zoom to Fit |
| ⌘C, ⌘S, ⇧⌘S, ⌘W | Edit and File menus | Copy, Save, Save As…, Close |
| ⌘Q | Bugeye menu | quit |

## How to check

```sh
ls -l ~/Pictures/Bugeye
xattr -l ~/Pictures/Bugeye/<file>.png          # dev.msenechal.bugeye.id and the other attributes
log show --last 10m --predicate 'subsystem == "dev.msenechal.bugeye"'   # category "editor": open, saved … in N ms, close
```

## Tests

### A. Opening

1. Capture an area with ⇧⌘4, then click **Edit** on the Quick Access thumbnail.
   **Expected:** a window titled with the file name (for example `Screenshot 2026-11-28 at 10.12.03.png`), with Arrow selected. A Dock icon and a menu bar (Bugeye, File, Edit, View) appear. The thumbnail stays up and doesn't auto-dismiss.
2. Close the editor, then double-click the thumbnail.
   **Expected:** the editor opens again.
3. With the editor open, double-click the thumbnail again.
   **Expected:** the same window comes forward; no second window opens.
4. Close it, then choose **Open Last Capture** in the status menu.
   **Expected:** the newest capture opens.
5. With its thumbnail still up, move the newest capture to the Trash in Finder, then click **Edit** on the thumbnail.
   **Expected:** no window, and the notice `Couldn't open capture` / `<name> is missing or unreadable.`
6. Open the status menu.
   **Expected:** Open Last Capture is disabled.
7. Close every editor.
   **Expected:** the Dock icon and the menu bar go away.

### B. Tools

1. Press each letter key (V C A R O L T P H B N) and draw with each tool.
   **Expected:** the button highlights; the cursor is an arrow for Select, an I-beam for Text and a crosshair for the rest; each shape appears where you drew it.
2. Hold ⇧ while drawing a rectangle, an ellipse, an arrow and a line.
   **Expected:** a square, a circle, and 45° steps.
3. Open a fresh capture. Click once, without dragging, with Arrow, Rectangle, Ellipse, Line, Pen, Highlighter and Blur / Pixelate.
   **Expected:** nothing is added, and Undo stays disabled.
4. Add three numbered steps, then select step 2 and press ⌫.
   **Expected:** the old step 3 now shows 2; ⌘Z brings back 1 2 3.
5. Draw a highlighter stroke that crosses itself.
   **Expected:** an even wash, no darker crossing.
6. Draw a Blur, then a Pixelate, over text.
   **Expected:** the text under it is unreadable. In Select mode, the selection shows a dashed outline and eight handles.

### C. Text

1. Press T, click, type `Hello`, press Return.
   **Expected:** the text stays exactly where it was typed (no jump).
2. Type `one`, press ⌥Return, type `two`, press Return.
   **Expected:** two lines.
3. Start typing, then press Esc.
   **Expected:** nothing is added.
4. Start typing, then click elsewhere on the canvas.
   **Expected:** the text is committed and nothing else happens.
5. Click an existing text (Text tool, or double-click it with Select) and edit it.
   **Expected:** it keeps its size and colour. Deleting all of its text removes it.
6. While typing, press ⌘Z.
   **Expected:** only the typing is undone.
7. Type `é` with ⌥E then E, and type in an input method (for example Japanese).
   **Expected:** both work.

### D. Options

1. Select a rectangle.
   **Expected:** the strip shows its colour, width, Filled and Shadow.
2. Change its colour from swatches, then drag around in the colour panel (the colour well, tooltip `Custom colour`).
   **Expected:** one ⌘Z undoes the whole panel drag.
3. Hover each control.
   **Expected:** the tooltips read `Red`, `Orange`, `Yellow`, `Green`, `Blue`, `Black`, `Custom colour`.

### E. Frame

1. Click **Frame**, then turn on `Background frame`.
   **Expected:** padding 48 pt, the indigo-to-pink gradient, radius 10 pt, Shadow on.
2. Try each fill, and drag each slider.
   **Expected:** each value shows as `<n> pt`, and one slider drag is one undo.
3. Click a slider, then use the arrow keys several times, then draw a shape.
   **Expected:** ⌘Z undoes the shape; the next ⌘Z undoes the whole keyboard run.
4. Capture a window (⇧⌘4, then Space), then add the frame.
   **Expected:** the shadow follows the window's rounded corners.

### F. Undo

1. Draw, move, resize, crop, and drag a slider; press ⌘Z after each.
   **Expected:** each gesture is exactly one undo step.
2. Press ⌘Z while dragging a shape.
   **Expected:** ⌘Z is ignored.
3. Press Esc while dragging.
   **Expected:** the drag is cancelled with no undo step.

### G. Zoom

1. Use View ▸ Zoom In, Zoom Out, Actual Size and Zoom to Fit, then pinch, then double-tap with two fingers.
   **Expected:** zoom stays between 10 % and 800 %; Zoom to Fit never goes above 100 %; a small canvas stays centred.
2. Zoom out to about 25 % and click a thin line.
   **Expected:** it selects; its handles keep the same size on screen.

### H. Output

1. Edit a capture and press ⌘S.
   **Expected:** the Quick Access thumbnail shows the edit, and the log shows `saved <name> in N ms`. (CI already checks the file's attributes survive.)
2. Press ⇧⌘S and save a copy to the Desktop.
   **Expected:** the copy appears on the Desktop; the window keeps its title and still shows the edited dot.
3. Press ⌘C, then paste into Slack.
   **Expected:** the edited image is pasted.
4. Drag the hand icon into Finder.
   **Expected:** a PNG named like the capture appears.
5. Drag the hand icon into Slack.
   **Expected:** the image is attached.

### I. Gone file, closing and quitting

1. Edit, delete the file in Finder, then press ⌘S.
   **Expected:** `The original file is gone` / `“<name>” was moved or deleted since it was opened.`, with `Save As…` and `Cancel`.
2. In that alert, choose `Save As…` and save into `~/Pictures/Bugeye`.
   **Expected:** the window retitles to the new name.
3. Edit, then press ⌘W.
   **Expected:** `Save changes to “<name>”?` / `Your annotations will be lost if you don't save them.`, with `Save`, `Don't Save` and `Cancel`; Cancel keeps the window open.
4. With two edited editors open, press ⌘Q and choose Cancel at the first prompt.
   **Expected:** Bugeye keeps running.
5. Press ⌘Q again and answer both prompts.
   **Expected:** each editor comes forward in turn, then Bugeye quits.

### J. Big capture

1. Capture a full 5K (or full Retina) screen with ⇧⌘3, add a frame, and draw and move shapes.
   **Expected:** it stays smooth.
2. Add a Strong Blur over most of the image, then save.
   **Expected:** the blur appears within about a third of a second (E23: at 300 ms or more, the gaussian moves to Core Image). The log's `saved … in N ms` is reasonable.

When you're done, say **"all good"**, or list the numbers that failed (for example "C5, H5").
