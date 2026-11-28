import BugeyeCore
import BugeyeFeatures
import BugeyeTestSupport
import CaptureCore
import Foundation
import Testing

@Suite struct CaptureSettingsTests {
    @Test func defaultsAreCopySaveAndNoDownscale() {
        let settings = CaptureSettings.load(from: InMemorySettingsStore())
        #expect(settings == CaptureSettings(copyToClipboard: true, saveToFolder: true, downscaleToPoints: false))
    }

    @Test func storedValuesAreReadAndBadOnesFallBack() {
        let store = InMemorySettingsStore([
            "capture.copyToClipboard": .bool(false), "capture.saveToFolder": .string("no"),
            "capture.downscaleToPoints": .bool(true),
        ])
        #expect(
            CaptureSettings.load(from: store)
                == CaptureSettings(copyToClipboard: false, saveToFolder: true, downscaleToPoints: true))
    }

    @Test func theKeysAreTheSpecs() {
        #expect(CaptureSettings.Key.copyToClipboard == "capture.copyToClipboard")
        #expect(CaptureSettings.Key.saveToFolder == "capture.saveToFolder")
        #expect(CaptureSettings.Key.downscaleToPoints == "capture.downscaleToPoints")
        #expect(CaptureSettings.Key.lastArea == "capture.lastArea")
    }
}

@Suite struct LastAreaStoreTests {
    let area = StoredArea(
        display: DisplayID(69_733_382), rect: Rect2D(x: 10.5, y: 20, width: 300, height: 200),
        displaySize: Size2D(width: 1512, height: 982))

    @Test func anAreaRoundTripsAsJSONUnderTheSpecsKey() throws {
        let store = InMemorySettingsStore()
        LastAreaStore.save(area, to: store)
        guard case .string(let json)? = store.value(forKey: "capture.lastArea") else {
            Issue.record("not stored as a string")
            return
        }
        #expect(json.contains("\"displaySize\""))
        #expect(LastAreaStore.load(from: store) == area)
    }

    @Test func missingEmptyOrBadValuesLoadNothing() {
        #expect(LastAreaStore.load(from: InMemorySettingsStore()) == nil)
        #expect(LastAreaStore.load(from: InMemorySettingsStore(["capture.lastArea": .string("")])) == nil)
        #expect(LastAreaStore.load(from: InMemorySettingsStore(["capture.lastArea": .string("{oops")])) == nil)
        #expect(LastAreaStore.load(from: InMemorySettingsStore(["capture.lastArea": .bool(true)])) == nil)
    }
}

@Suite struct CaptureModuleTests {
    let module = CaptureModule()

    @Test func itIsTheCaptureModule() {
        #expect(module.id == "capture")
    }

    @Test func menuItemsHaveTheSpecsIdsTitlesSlotsAndHotkeys() {
        #expect(
            module.menuItems() == [
                MenuItemSpec(
                    id: "capture.area", title: "Capture Area", slot: MenuSlot(.capture, order: 0),
                    hotkeyID: "capture.area"),
                MenuItemSpec(id: "capture.window", title: "Capture Window", slot: MenuSlot(.capture, order: 30)),
                MenuItemSpec(
                    id: "capture.fullscreen", title: "Capture Fullscreen", slot: MenuSlot(.capture, order: 40),
                    hotkeyID: "capture.fullscreen"),
            ])
    }

    @Test func hotkeysHaveTheSpecsIdsTitlesDefaultsAndKeys() {
        #expect(
            module.hotkeys() == [
                HotkeySpec(
                    id: "capture.fullscreen", title: "Capture Fullscreen",
                    defaultKey: KeyCombo("3", [.shift, .command]),
                    settingKey: "capture.hotkey.fullscreen"),
                HotkeySpec(
                    id: "capture.allDisplays", title: "Capture All Displays",
                    defaultKey: KeyCombo("3", [.option, .shift, .command]), settingKey: "capture.hotkey.allDisplays"),
                HotkeySpec(
                    id: "capture.area", title: "Capture Area", defaultKey: KeyCombo("4", [.shift, .command]),
                    settingKey: "capture.hotkey.area"),
            ])
        #expect(module.hotkeys().map(\.defaultKey.description) == ["⇧⌘3", "⌥⇧⌘3", "⇧⌘4"])
    }

    @Test func thePaneIsCaptureAfterGeneral() {
        #expect(module.settingsSection() == SettingsSectionSpec(id: "capture", title: "Capture", order: 10))
    }

    @Test func itRegistersWithoutConflicts() throws {
        _ = try FeatureRegistry([GeneralModule(), module])
    }
}

@Suite struct CaptureStringsTests {
    @Test func everyStringIsTheSpecs() {
        #expect(CaptureStrings.captureFailedTitle == "Capture failed")
        #expect(CaptureStrings.encodeFailed == "Could not encode PNG.")
        #expect(CaptureStrings.writeFailedCopied == "Couldn't write the file. The image is on the clipboard.")
        #expect(CaptureStrings.writeFailed == "Couldn't write the file.")
        #expect(CaptureStrings.windowClosed == "The window closed before it could be captured.")
        #expect(CaptureStrings.displayDisconnected == "The display was disconnected.")
        #expect(CaptureStrings.permissionTitle == "Screen Recording permission needed")
        #expect(
            CaptureStrings.permissionText
                == "Enable Bugeye under Privacy & Security \u{2192} Screen & System Audio Recording, then relaunch the app."
        )
        #expect(CaptureStrings.openSystemSettings == "Open System Settings")
        #expect(CaptureStrings.relaunch == "Relaunch")
        #expect(CaptureStrings.cancel == "Cancel")
        #expect(
            CaptureStrings.screenRecordingSettingsURL
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        #expect(CaptureStrings.paneTitle == "Capture")
        #expect(CaptureStrings.afterCapture == "After capture")
        #expect(CaptureStrings.copyToClipboard == "Copy to clipboard")
        #expect(CaptureStrings.saveToFolder == "Save to folder")
        #expect(CaptureStrings.downscale == "Downscale Retina captures to 1\u{00D7}")
        #expect(CaptureStrings.captureArea == "Capture Area")
        #expect(CaptureStrings.captureWindow == "Capture Window")
        #expect(CaptureStrings.captureFullscreen == "Capture Fullscreen")
        #expect(CaptureStrings.captureAllDisplays == "Capture All Displays")
        #expect(OutputStrings.folderUnavailableTitle == "Couldn't save to folder")
    }
}
