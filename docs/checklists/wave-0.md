# Wave 0 manual checklist

Wave 0 builds no capture feature: this pass checks that the new app installs, shows its menu, opens Settings and keeps its key in the Keychain, while the first build's app keeps running. CI already checked the code; only your Mac can check these.

## Before you start

1. Install Xcode 27 from the App Store (it needs macOS 26.6 or later; your Mac has 26.7.1) and open it once so it finishes installing its components. Then:
   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   xcodebuild -version    # Xcode 27.x
   swift --version        # Swift 6.4
   ```
2. Get the branch:
   ```sh
   cd ~/path/to/bugeye
   git fetch origin && git checkout feat/wave-0 && git pull
   ```
3. Leave the first build's Bugeye running (it lives in `/Applications/Bugeye.app`). The new one installs to `~/Applications/Bugeye.app`, so both run side by side and both show a Bugeye icon in the menu bar. The new one's menu has only three items.
4. Optional, for test 4: an Anthropic API key from console.anthropic.com. Test 4 sends two tiny requests (a fraction of a cent).

## Shortcuts

| Key or item | Where | Does |
|---|---|---|
| Settings… (⌘,) | the new Bugeye menu | opens "Bugeye Settings" |
| Quit Bugeye (⌘Q) | the new Bugeye menu | quits the new app only |
| Save (or Return) | next to the "Anthropic API key" field | saves the key |

## How to check

```sh
# The signing identity and the installed app's signature
security find-identity -p codesigning ~/Library/Keychains/bugeye-signing.keychain-db
codesign -d -r- ~/Applications/Bugeye.app          # designated requirement names "Bugeye Dev" and dev.msenechal.bugeye

# Both apps running
pgrep -fl 'Bugeye.app/Contents/MacOS/Bugeye'        # one line for /Applications, one for ~/Applications

# The key: in the Keychain, never in UserDefaults
security find-generic-password -s dev.msenechal.bugeye -a anthropic-api-key   # the item's attributes, not the key
defaults read dev.msenechal.bugeye                  # settings only: no "sk-ant" anywhere

# The save folder
ls -ld ~/Pictures/Bugeye

# The app's log
log show --last 10m --predicate 'subsystem == "dev.msenechal.bugeye"'
```

## Tests

### 1. Install

1. Run `make cert`.
   **Expected:** it ends with `Created "Bugeye Dev". Next: make install` (or says `"Bugeye Dev" already exists` on a second run). It may ask for your login password once.
2. Run `make install`.
   **Expected:** it ends with `Installed and launched /Users/<you>/Applications/Bugeye.app`, and `/Applications/Bugeye.app` (the old app) is untouched.

### 2. Menu bar

1. Find the new Bugeye icon in the menu bar (the bug between corner brackets) and click it.
   **Expected:** exactly these items, top to bottom: `About Bugeye`, a separator, `Settings…` showing ⌘,, a separator, `Quit Bugeye` showing ⌘Q.
2. Choose **About Bugeye**.
   **Expected:** the standard About window shows the Bugeye icon, "Bugeye" and "Version 0.1.0 (1)".
3. Check the Dock and ⌘Tab.
   **Expected:** no Bugeye icon in the Dock and none in the ⌘Tab switcher, before or after opening Settings.

### 3. Settings: General

1. Choose **Settings…** in the new Bugeye menu.
   **Expected:** a window titled `Bugeye Settings` with two tabs, `General` and `AI`, General selected.
2. Look at the General tab.
   **Expected:** `Save captures to` followed by `~/Pictures/Bugeye/` and a `Choose…` button; `ls -ld ~/Pictures/Bugeye` shows the folder exists.
3. Click **Choose…**, pick another folder (for example Desktop), click Open.
   **Expected:** the line shows that folder, as `~/Desktop/`.
4. Click **Choose…** again and pick `~/Pictures/Bugeye`.
   **Expected:** the line shows `~/Pictures/Bugeye/` again.

### 4. Settings: AI

1. Click the **AI** tab.
   **Expected:** an `Anthropic API key` field with a `Save` button beside it, a `Test key` button that is greyed out, the line `No key saved.`, and below them `Bugeye only sends data to Claude for features you turn on. Each one is off until you enable it.`
2. Click **Save** with the field empty.
   **Expected:** nothing changes: still `No key saved.`
3. Optional, only if you have a key: click into the field, press ⌘V to paste it, and click **Save** (Return does the same).
   **Expected:** ⌘V pastes the key (shown as dots); then `Key saved. Not tested yet.`, and `Test key` becomes clickable.
4. Click **Test key**.
   **Expected:** after a second or two, `Key works.` (If you see `Key works, but Anthropic refused the request. Check your plan and the model in Settings.`, the key is fine but the account can't use the model or the fallback beta: note it in your report.) The `security find-generic-password` command above finds the item; `defaults read dev.msenechal.bugeye` shows no key.
5. Optional: turn Wi-Fi off, click **Test key**, then turn Wi-Fi back on.
   **Expected:** `Couldn't reach Anthropic. Check your connection.` (after a few seconds of retries).
6. With the Settings window in front, press ⌘W.
   **Expected:** the window closes; **Settings…** opens it again.

### 5. Side by side

1. Use the old app as you normally do: take an area capture with ⇧⌘4.
   **Expected:** the old app captures as before; the new app does nothing (it registers no hotkeys yet).
2. Choose **Quit Bugeye** in the new app's menu.
   **Expected:** the new icon disappears; the old app's icon stays and still works.

### 6. Relaunch

1. Run `open ~/Applications/Bugeye.app`, open Settings.
   **Expected:** General still shows the folder you left; AI shows `Key saved. Not tested yet.` if you saved a key in test 4, else `No key saved.` No permission or Keychain prompt appears.

When you're done, say "all good", or list the numbers that failed with what you saw.
