import BugeyeFeatures
import EditorCore
import Testing

@Suite struct EditorToolTests {
    @Test func theElevenToolsInToolbarOrderWithTheirKeysSymbolsAndTooltips() {
        #expect(EditorTool.allCases.map(\.key) == ["V", "C", "A", "R", "O", "L", "T", "P", "H", "B", "N"])
        #expect(
            EditorTool.allCases.map(\.symbol) == [
                "cursorarrow", "crop", "arrow.up.right", "rectangle", "circle", "line.diagonal", "textformat",
                "pencil.tip", "highlighter", "square.grid.3x3", "1.circle",
            ])
        #expect(
            EditorTool.allCases.map(\.tooltip) == [
                "Select (V)", "Crop (C)", "Arrow (A)", "Rectangle (R)", "Ellipse (O)", "Line (L)", "Text (T)",
                "Pen (P)", "Highlighter (H)", "Blur / Pixelate (B)", "Numbered step (N)",
            ])
        #expect(EditorTool.default == .arrow)
    }

    @Test func eachToolShowsItsOptions() {
        let colour = EditorTool.allCases.filter { $0.options.contains(.color) }
        #expect(colour == [.arrow, .rectangle, .ellipse, .line, .text, .pen, .highlighter, .step])
        let width = EditorTool.allCases.filter { $0.options.contains(.width) }
        #expect(width == [.arrow, .rectangle, .ellipse, .line, .pen, .highlighter, .step])
        #expect(EditorTool.allCases.filter { $0.options.contains(.filled) } == [.rectangle, .ellipse])
        let shadow = EditorTool.allCases.filter { $0.options.contains(.shadow) }
        #expect(shadow == [.arrow, .rectangle, .ellipse, .line, .text, .pen, .step])
        #expect(EditorTool.allCases.filter { $0.options.contains(.size) } == [.text])
        #expect(EditorTool.allCases.filter { $0.options.contains(.blur) } == [.blur])
        #expect(EditorTool.allCases.filter { $0.options.contains(.crop) } == [.crop])
        #expect(EditorTool.allCases.filter { $0.options.contains(.selectHint) } == [.select])
    }

    @Test func cursorsAreArrowIBeamOrCrosshair() {
        #expect(EditorTool.select.cursor == .arrow)
        #expect(EditorTool.text.cursor == .iBeam)
        for tool in EditorTool.allCases where tool != .select && tool != .text {
            #expect(tool.cursor == .crosshair)
        }
    }

    @Test func plainLettersSwitchToolsInEitherCase() {
        #expect(EditorShortcuts.action(keyCode: 9, characters: "v", modifiers: []) == .tool(.select))
        #expect(EditorShortcuts.action(keyCode: 9, characters: "V", modifiers: []) == .tool(.select))
        #expect(EditorShortcuts.action(keyCode: 45, characters: "n", modifiers: []) == .tool(.step))
        #expect(EditorShortcuts.action(keyCode: 31, characters: "o", modifiers: []) == .tool(.ellipse))
    }

    @Test func anyModifierIncludingShiftPassesTheKeyOn() {
        #expect(EditorShortcuts.action(keyCode: 9, characters: "V", modifiers: [.shift]) == nil)
        #expect(EditorShortcuts.action(keyCode: 9, characters: "v", modifiers: [.command]) == nil)
        #expect(EditorShortcuts.action(keyCode: 9, characters: "v", modifiers: [.option]) == nil)
        #expect(EditorShortcuts.action(keyCode: 9, characters: "v", modifiers: [.control]) == nil)
    }

    @Test func escapeAndBothDeleteKeysAreCanvasKeysEverythingElsePassesOn() {
        #expect(EditorShortcuts.action(keyCode: 53, characters: "\u{1B}", modifiers: []) == .escape)
        #expect(EditorShortcuts.action(keyCode: 51, characters: "\u{7F}", modifiers: []) == .delete)
        #expect(EditorShortcuts.action(keyCode: 117, characters: "\u{F728}", modifiers: []) == .delete)
        #expect(EditorShortcuts.action(keyCode: 7, characters: "x", modifiers: []) == nil)
        #expect(EditorShortcuts.action(keyCode: 18, characters: "1", modifiers: []) == nil)
        #expect(EditorShortcuts.action(keyCode: 36, characters: "\r", modifiers: []) == nil)
    }
}
