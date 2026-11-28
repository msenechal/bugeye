import BugeyeCore
import BugeyeFeatures
import Testing

/// MainMenu, DocumentWindows, StatusItemOverride, TerminationGate, the Settings layout (contracts §4.2.5–4.2.9).
@MainActor @Suite struct ShellContractTests {
    func rows(_ entries: [MainMenuEntry]) -> [String] {
        entries.map { entry in
            switch entry {
            case .separator: "—"
            case .item(let spec): "\(spec.title)|\(spec.key?.description ?? "")|\(spec.action)"
            }
        }
    }

    // MARK: MainMenu (§4.2.5)

    @Test func theShellMenuMatchesTheTable() throws {
        let entries = MainMenu.entries(for: try FeatureRegistry([GeneralModule()]))
        #expect(Set(entries.keys) == Set(MainMenuGroup.allCases))
        #expect(rows(entries[.app]!) == ["Quit Bugeye|⌘Q|terminate:"])
        #expect(
            rows(entries[.file]!) == [
                "Save|⌘S|saveDocument:", "Save As…|⇧⌘S|saveDocumentAs:", "—", "Close|⌘W|performClose:",
            ])
        #expect(
            rows(entries[.edit]!) == [
                "Undo|⌘Z|undo:", "Redo|⇧⌘Z|redo:", "—", "Cut|⌘X|cut:", "Copy|⌘C|copy:", "Paste|⌘V|paste:",
                "Delete||delete:", "Select All|⌘A|selectAll:",
            ])
        #expect(
            rows(entries[.view]!) == [
                "Zoom In|⌘=|zoomIn:", "Zoom Out|⌘-|zoomOut:", "Actual Size|⌘1|zoomToActualSize:",
                "Zoom to Fit|⌘0|zoomToFit:",
            ])
        #expect(MainMenuGroup.allCases.map(MainMenu.title(of:)) == ["Bugeye", "File", "Edit", "View"])
    }

    @Test func moduleItemsArePlacedByGroupAndOrder() throws {
        let copyText = MainMenuItemSpec(
            id: "editor.copyText", title: "Copy Text", key: KeyCombo("c", [.shift, .command]), group: .edit, order: 80,
            action: "copyText:")
        let export = MainMenuItemSpec(
            id: "editor.export", title: "Export…", key: nil, group: .file, order: 20, action: "export:")
        let entries = MainMenu.entries(
            for: try FeatureRegistry([GeneralModule(), StubModule(id: "editor", mainMenu: [copyText, export])]))
        #expect(rows(entries[.edit]!).last == "Copy Text|⇧⌘C|copyText:")
        // On a tie with the shell's separator (order 20), the shell's entry comes first (plan P8).
        #expect(
            rows(entries[.file]!) == [
                "Save|⌘S|saveDocument:", "Save As…|⇧⌘S|saveDocumentAs:", "—", "Export…||export:",
                "Close|⌘W|performClose:",
            ])
    }

    // MARK: DocumentWindows (§4.2.6)

    @Test func onlyTheFirstOpenAndLastCloseChangeThePolicy() {
        var applied: [ActivationPolicy] = []
        let windows = DocumentWindows { applied.append($0) }
        windows.opened()
        windows.opened()
        #expect(windows.openCount == 2 && applied == [.regular])
        windows.closed()
        #expect(applied == [.regular])
        windows.closed()
        #expect(windows.openCount == 0 && applied == [.regular, .accessory])
    }

    @Test func closingBelowZeroCountsAnUnderflow() {
        var applied: [ActivationPolicy] = []
        var reported = 0
        let windows = DocumentWindows(apply: { applied.append($0) }, onUnderflow: { reported += 1 })
        windows.closed()
        #expect(windows.openCount == 0 && windows.underflows == 1 && applied == [] && reported == 1)
        windows.opened()
        #expect(windows.openCount == 1 && applied == [.regular])
    }

    // MARK: StatusItemOverride (§4.2.7)

    @Test func overrideEntriesDefaultToEnabledAndSeparatorsHaveNoID() {
        let entry = StatusItemOverride.Entry(id: "recording.stop", title: "Stop")
        #expect(entry.isEnabled && entry.shownKey == nil)
        #expect(StatusItemOverride.Entry.separator.id == nil)
        let override = StatusItemOverride(
            badge: .recording(elapsed: "0:42"), accessibilityLabel: "Recording", menu: [entry, .separator])
        #expect(override.menu.count == 2)
    }

    // MARK: TerminationGate (§4.2.8)

    @Test func withNoParticipantsQuitIsAllowed() async {
        #expect(await TerminationGate().shouldTerminate())
    }

    @Test func asksRunInOrderAndTheFirstNoStops() async {
        let gate = TerminationGate()
        var log: [String] = []
        gate.addAsk {
            log.append("a1")
            return true
        }
        gate.addFinish { log.append("f1") }
        gate.addAsk {
            log.append("a2")
            return false
        }
        gate.addAsk {
            log.append("a3")
            return true
        }
        #expect(await gate.shouldTerminate() == false)
        #expect(log == ["a1", "a2"])
    }

    @Test func finishesRunInOrderOnlyAfterEveryAskAgreed() async {
        let gate = TerminationGate()
        var log: [String] = []
        gate.addFinish { log.append("f1") }
        gate.addAsk {
            log.append("a1")
            return true
        }
        gate.addFinish {
            await Task.yield()
            log.append("f2")
        }
        gate.addAsk {
            log.append("a2")
            return true
        }
        #expect(await gate.shouldTerminate())
        #expect(log == ["a1", "a2", "f1", "f2"])
    }

    @Test func aSecondCallWhileOneRunsSharesItsAnswer() async {
        let gate = TerminationGate()
        var asked = 0
        var release: CheckedContinuation<Void, Never>?
        gate.addAsk {
            asked += 1
            await withCheckedContinuation { release = $0 }
            return false
        }
        let first = Task { await gate.shouldTerminate() }
        while release == nil { await Task.yield() }
        let second = Task { await gate.shouldTerminate() }
        for _ in 0..<10 { await Task.yield() }
        release?.resume()
        #expect(await first.value == false)
        #expect(await second.value == false)
        #expect(asked == 1)
        // Once finished, a new call asks again.
        let third = Task { await gate.shouldTerminate() }
        while asked < 2 { await Task.yield() }
        release?.resume()
        #expect(await third.value == false)
    }

    // MARK: Settings layout (§4.2.9)

    @Test func panesAreModulesThenShortcutsThenAI() throws {
        let registry = try FeatureRegistry([
            GeneralModule(),
            StubModule(id: "rec", section: SettingsSectionSpec(id: "recording", title: "Recording", order: 30)),
        ])
        #expect(SettingsLayout.panes(for: registry).map(\.id) == ["general", "recording", "shortcuts", "ai"])
        #expect(SettingsLayout.shortcutsPane == SettingsSectionSpec(id: "shortcuts", title: "Shortcuts", order: 900))
        #expect(ShellStrings.shortcutsPane == "Shortcuts")
    }
}
