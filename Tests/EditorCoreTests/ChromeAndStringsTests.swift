import BugeyeCore
import BugeyeFeatures
import EditorCore
import Testing

@Suite struct ZoomAndSizingTests {
    @Test func zoomStepsByAQuarterAndClampsTo10To800Percent() {
        #expect(ZoomModel.zoomIn(1) == 1.25)
        #expect(ZoomModel.zoomOut(1) == 0.8)
        #expect(ZoomModel.zoomIn(7) == 8)
        #expect(ZoomModel.zoomOut(0.11) == 0.1)
        #expect(ZoomModel.clamp(20) == 8)
        #expect(ZoomModel.actualSize == 1)
    }

    @Test func zoomToFitLeaves20PointsEachWayAndNeverExceeds100Percent() {
        #expect(
            ZoomModel.fit(viewport: Size2D(width: 1040, height: 840), canvas: Size2D(width: 2000, height: 1000)) == 0.5)
        #expect(
            ZoomModel.fit(viewport: Size2D(width: 1040, height: 440), canvas: Size2D(width: 2000, height: 1000)) == 0.4)
        #expect(ZoomModel.fit(viewport: Size2D(width: 1040, height: 840), canvas: Size2D(width: 100, height: 100)) == 1)
        #expect(
            ZoomModel.fit(viewport: Size2D(width: 60, height: 60), canvas: Size2D(width: 4000, height: 4000)) == 0.1)
    }

    @Test func theWindowFitsTheCanvasPlusChromeWithinTheScreen() {
        let screen = Size2D(width: 1600, height: 1000)
        #expect(WindowSizing.chromeHeight == 78)
        #expect(
            WindowSizing.initialContentSize(canvasPoints: Size2D(width: 800, height: 500), screenVisible: screen)
                == Size2D(width: 840, height: 618))
        #expect(
            WindowSizing.initialContentSize(canvasPoints: Size2D(width: 3000, height: 2000), screenVisible: screen)
                == Size2D(width: 1360, height: 850))
        #expect(
            WindowSizing.initialContentSize(canvasPoints: Size2D(width: 100, height: 80), screenVisible: screen)
                == Size2D(width: 640, height: 420))
        #expect(WindowSizing.minimumContentSize == Size2D(width: 640, height: 420))
    }
}

@Suite struct ChromeTests {
    @Test func theToolbarInOrderWithTheReservedSlotsAbsent() {
        #expect(
            EditorToolbar.items(slots: EditorSlots())
                == EditorTool.allCases.map { .tool($0) } + [
                    .divider, .frame, .spacer, .undo, .redo, .copy, .save, .dragHandle,
                ])
        #expect(
            EditorToolbar.items(slots: EditorSlots(copyText: true, copyForAI: true, sourceChip: true)).suffix(6)
                == [.copyText, .copyForAI, .copy, .save, .dragHandle, .sourceChip])
    }

    @Test func barsReserveTheirHeightWhenShown() {
        #expect(EditorSlots().barsHeight == 0)
        #expect(EditorSlots(findBar: true, sweepBar: true).barsHeight == 68)
        #expect(EditorServices().textReader == nil)
        #expect(EditorServices().faceFinder == nil)
        #expect(EditorServices().rectangleFinder == nil)
    }

    @Test func theOptionsStripFollowsTheToolOrTheSelection() {
        #expect(EditorOptionsStrip.rows(tool: .rectangle, selectedTool: nil) == [.color, .width, .filled, .shadow])
        #expect(EditorOptionsStrip.rows(tool: .text, selectedTool: nil) == [.color, .shadow, .size])
        #expect(EditorOptionsStrip.rows(tool: .blur, selectedTool: nil) == [.blur])
        #expect(EditorOptionsStrip.rows(tool: .select, selectedTool: nil) == [.selectHint])
        #expect(EditorOptionsStrip.rows(tool: .select, selectedTool: .ellipse) == [.color, .width, .filled, .shadow])
        #expect(EditorOptionsStrip.rows(tool: .crop, selectedTool: nil) == [.crop])
    }

    @Test func theCropLabel() {
        #expect(EditorStrings.cropLabel(nil) == "Drag to crop")
        #expect(EditorStrings.cropLabel(Rect2D(x: 3, y: 4, width: 640, height: 480)) == "640 \u{D7} 480 px")
    }
}

@Suite struct EditorStringsTests {
    @Test func everySettledStringCharacterForCharacter() {
        #expect(EditorStrings.openFailedTitle == "Couldn't open capture")
        #expect(EditorStrings.openFailedBody(name: "Shot.png") == "Shot.png is missing or unreadable.")
        #expect(EditorStrings.frameButton == "Frame")
        #expect(EditorStrings.frameTooltip == "Background frame")
        #expect(EditorStrings.undoTooltip == "Undo (\u{2318}Z)")
        #expect(EditorStrings.redoTooltip == "Redo (\u{21E7}\u{2318}Z)")
        #expect(EditorStrings.copyButton == "Copy")
        #expect(EditorStrings.copyTooltip == "Copy the edited image (\u{2318}C)")
        #expect(EditorStrings.saveButton == "Save")
        #expect(EditorStrings.saveTooltip == "Save (\u{2318}S)")
        #expect(EditorStrings.dragTooltip == "Drag the edited image into another app")
        #expect(EditorStrings.customColourTooltip == "Custom colour")
        #expect(EditorStrings.widthNames == ["Thin", "Medium", "Thick"])
        #expect(EditorStrings.filled == "Filled")
        #expect(EditorStrings.shadow == "Shadow")
        #expect(EditorStrings.size == "Size")
        #expect(EditorStrings.fontSizeNames == ["16 pt", "24 pt", "36 pt", "48 pt"])
        #expect(EditorStrings.blurModeNames == ["Pixelate", "Blur"])
        #expect(EditorStrings.strengthNames == ["Light", "Medium", "Strong"])
        #expect(EditorStrings.resetCrop == "Reset Crop")
        #expect(
            EditorStrings.selectHint == "Click an annotation to select it \u{B7} drag to move \u{B7} Delete removes it")
        #expect(EditorStrings.frameToggle == "Background frame")
        #expect(EditorStrings.padding == "Padding")
        #expect(EditorStrings.cornerRadius == "Corner radius")
        #expect(EditorStrings.points(12) == "12 pt")
        #expect(EditorStrings.frameShadow == "Shadow")
        #expect(EditorStrings.goneTitle == "The original file is gone")
        #expect(
            EditorStrings.goneBody(name: "a.png") == "\u{201C}a.png\u{201D} was moved or deleted since it was opened.")
        #expect(EditorStrings.saveAsButton == "Save As\u{2026}")
        #expect(EditorStrings.cancelButton == "Cancel")
        #expect(EditorStrings.saveFailedTitle(name: "a.png") == "Couldn't save \u{201C}a.png\u{201D}")
        #expect(EditorStrings.okButton == "OK")
        #expect(EditorStrings.copyFailedTitle == "Couldn't copy")
        #expect(EditorStrings.renderFailed == "The image couldn't be rendered.")
        #expect(EditorStrings.copyFailedBody == "The image couldn't be put on the clipboard.")
        #expect(EditorStrings.unsavedTitle(name: "a.png") == "Save changes to \u{201C}a.png\u{201D}?")
        #expect(EditorStrings.unsavedBody == "Your annotations will be lost if you don't save them.")
        #expect(EditorStrings.saveButton == "Save")
        #expect(EditorStrings.dontSaveButton == "Don't Save")
        #expect(EditorStrings.editAction == "Edit")
        #expect(EditorStrings.openLastCapture == "Open Last Capture")
        #expect(EditorPalette.swatches.map(\.name) == ["Red", "Orange", "Yellow", "Green", "Blue", "Black"])
    }

    @Test func theLogLinesNeverCarryText() {
        #expect(EditorLog.open("a.png") == "open a.png")
        #expect(EditorLog.openFailed("a.png", reason: "missing") == "open failed a.png: missing")
        #expect(EditorLog.close("a.png") == "close a.png")
        #expect(EditorLog.saved("a.png", milliseconds: 42) == "saved a.png in 42 ms")
        #expect(EditorLog.saveFailed("a.png", error: "boom") == "save failed a.png: boom")
        #expect(EditorLog.dragFailed(error: "boom") == "drag file failed: boom")
    }
}

@Suite struct EditorModuleTests {
    @Test func theModuleDeclaresEditAndOpenLastCapture() throws {
        let module = EditorModule()
        #expect(module.id == "editor")
        #expect(
            module.quickAccessActions()
                == [
                    QuickAccessActionSpec(
                        id: "editor.edit", title: "Edit", order: 0, placement: .primary, kinds: [.screenshot])
                ])
        #expect(
            module.menuItems()
                == [
                    MenuItemSpec(
                        id: "editor.openLastCapture", title: "Open Last Capture", slot: MenuSlot(.library, order: 0))
                ])
        #expect(module.hotkeys().isEmpty)
        #expect(module.settingsSection() == nil)
        #expect(module.mainMenuItems().isEmpty)
        _ = try FeatureRegistry([GeneralModule(), module])
    }
}
