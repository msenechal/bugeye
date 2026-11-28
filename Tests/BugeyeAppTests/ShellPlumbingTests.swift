import AppKit
import BugeyeCore
import BugeyeFeatures
import BugeyeTestSupport
import Foundation
import SwiftUI
import Testing

@testable import BugeyeApp

/// The contracts PR's shell tests, with test-only modules (K20).
@MainActor @Suite struct ShellPlumbingTests {
    final class RecordingDisplay: StatusItemDisplay {
        var log: [String] = []
        var menu: NSMenu?
        func showGlyph() { log.append("glyph") }
        func showBadge(_ badge: StatusItemOverride.Badge) { log.append("badge \(badge)") }
        func setAccessibilityLabel(_ label: String) { log.append("label \(label)") }
        func setMenu(_ menu: NSMenu) { self.menu = menu }
    }

    struct CaptureLike: FeatureModule {
        var id: String { "testcapture" }
        func menuItems() -> [MenuItemSpec] {
            [
                MenuItemSpec(id: "t.area", title: "Area", slot: MenuSlot(.capture, order: 0), hotkeyID: "t.area"),
                MenuItemSpec(id: "t.window", title: "Window", slot: MenuSlot(.capture, order: 10)),
            ]
        }
        func hotkeys() -> [HotkeySpec] {
            [
                HotkeySpec(
                    id: "t.area", title: "Area", defaultKey: KeyCombo("4", [.shift, .command]), settingKey: "t.area")
            ]
        }
    }

    func makeController(settings: InMemorySettingsStore = .init(), display: RecordingDisplay) throws -> (
        MenuBarController, AppContext
    ) {
        let context = AppContext.testing(
            home: "/tmp/none", settings: settings, modules: [GeneralModule(), CaptureLike()])
        let controller = MenuBarController(
            registry: context.registry, settings: settings, router: context.router, hotkeyStatus: context.hotkeyStatus,
            statusItemState: context.statusItem, display: display)
        return (controller, context)
    }

    func item(_ menu: NSMenu, _ id: String) -> NSMenuItem? {
        menu.items.first { $0.identifier?.rawValue == id }
    }

    @Test func theStatusMenuShowsTheCurrentBinding() throws {
        let settings = InMemorySettingsStore()
        let display = RecordingDisplay()
        let (controller, _) = try makeController(settings: settings, display: display)
        controller.menuNeedsUpdate(controller.moduleMenu)
        let area = try #require(item(controller.moduleMenu, "t.area"))
        #expect(area.keyEquivalent == "4" && area.keyEquivalentModifierMask == [.shift, .command])
        settings.setValue(.string("⌃⌥A"), forKey: "t.area")
        controller.menuNeedsUpdate(controller.moduleMenu)
        #expect(area.keyEquivalent == "a" && area.keyEquivalentModifierMask == [.control, .option])
        settings.setValue(.string("none"), forKey: "t.area")
        controller.menuNeedsUpdate(controller.moduleMenu)
        #expect(area.keyEquivalent == "")
    }

    @Test func noKeyIsShownForAnUnregisteredHotkey() throws {
        let display = RecordingDisplay()
        let (controller, context) = try makeController(display: display)
        context.hotkeyStatus.setRegistered("t.area", false)
        controller.menuNeedsUpdate(controller.moduleMenu)
        #expect(item(controller.moduleMenu, "t.area")?.keyEquivalent == "")
    }

    @Test func aModuleItemWithoutAHandlerIsDisabled() throws {
        let display = RecordingDisplay()
        let (controller, context) = try makeController(display: display)
        var enabled = true
        context.router.onMenuItem("t.area", isEnabled: { enabled }, perform: {})
        controller.menuNeedsUpdate(controller.moduleMenu)
        #expect(item(controller.moduleMenu, "t.area")?.isEnabled == true)
        #expect(item(controller.moduleMenu, "t.window")?.isEnabled == false)
        #expect(item(controller.moduleMenu, StatusMenu.settingsID)?.isEnabled == true)
        enabled = false
        controller.menuNeedsUpdate(controller.moduleMenu)
        #expect(item(controller.moduleMenu, "t.area")?.isEnabled == false)
        #expect(controller.moduleMenu.autoenablesItems == false)
    }

    @Test func theOverrideIsAppliedAndRestored() throws {
        let display = RecordingDisplay()
        let (controller, context) = try makeController(display: display)
        #expect(display.log == ["glyph", "label Bugeye"])
        #expect(display.menu === controller.moduleMenu)
        var stopped = 0
        context.router.onMenuItem("recording.stop") { stopped += 1 }
        let override = StatusItemOverride(
            badge: .recording(elapsed: "0:42"), accessibilityLabel: "Recording, 0:42",
            menu: [
                .init(id: "recording.stop", title: "Stop", shownKey: KeyCombo("5", [.shift, .command])), .separator,
                .init(id: "recording.discard", title: "Discard", isEnabled: false),
            ])
        context.statusItem.setOverride(override, owner: "recording")
        #expect(display.log.suffix(2) == ["badge recording(elapsed: \"0:42\")", "label Recording, 0:42"])
        let menu = try #require(display.menu)
        #expect(menu !== controller.moduleMenu)
        #expect(menu.items.map { $0.isSeparatorItem ? "—" : $0.title } == ["Stop", "—", "Discard"])
        #expect(menu.items[0].isEnabled && !menu.items[2].isEnabled)
        #expect(menu.items[0].keyEquivalent == "5")
        menu.performActionForItem(at: 0)
        #expect(stopped == 1)

        context.statusItem.setOverride(nil, owner: "someoneElse")
        #expect(display.menu === menu)
        context.statusItem.setOverride(nil, owner: "recording")
        #expect(display.log.suffix(2) == ["glyph", "label Bugeye"])
        #expect(display.menu === controller.moduleMenu)
    }

    @Test func badgesAreDrawnAsSpecified() {
        #expect(StatusBadge.title(.recording(elapsed: "0:42"))?.string == "\u{25CF} 0:42")
        #expect(StatusBadge.title(.paused(elapsed: "1:05"))?.string == "\u{2759}\u{2759} 1:05")
        #expect(StatusBadge.title(.finishing) == nil)
        #expect(StatusBadge.symbolName(.finishing) == "hourglass")
        #expect(StatusBadge.symbolName(.recording(elapsed: "0")) == nil)
        let dot = StatusBadge.title(.recording(elapsed: "0:42"))
        #expect(dot?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .systemRed)
    }

    @Test func settingsShowsARegisteredPaneAndHidesAnUnregisteredOne() throws {
        let panes = SettingsPanes()
        let layout = SettingsLayout.panes(
            for: try FeatureRegistry([
                GeneralModule(),
                StubPaneModule(id: "rec", pane: "recording"), StubPaneModule(id: "qa", pane: "quickAccess"),
            ]))
        #expect(SettingsView.visiblePanes(layout, settingsPanes: panes).map(\.id) == ["general", "ai"])
        panes.register("recording") { AnyView(Text("Recording")) }
        panes.register("shortcuts") { AnyView(Text("Shortcuts")) }
        #expect(
            SettingsView.visiblePanes(layout, settingsPanes: panes).map(\.id) == [
                "general", "recording", "shortcuts", "ai",
            ])
    }

    struct StubPaneModule: FeatureModule {
        var id: String
        var pane: String
        func settingsSection() -> SettingsSectionSpec? { SettingsSectionSpec(id: pane, title: pane, order: 10) }
    }

    @Test func regularInstallsTheMainMenuAndAccessoryKeepsIt() throws {
        let menu = MainMenuInstaller.menu(for: try FeatureRegistry([GeneralModule()]))
        var log: [String] = []
        let apply = MainMenuInstaller.applier(
            menu: menu, setPolicy: { log.append($0 == .regular ? "regular" : "accessory") },
            setMainMenu: { log.append($0 === menu ? "menu" : "other menu") }, activate: { log.append("activate") })
        apply(.regular)
        #expect(log == ["menu", "regular", "activate"])
        apply(.accessory)
        #expect(log == ["menu", "regular", "activate", "accessory"])
    }

    @Test func quitWaitsForTheGateAndRepliesWithItsAnswer() async {
        let gate = TerminationGate()
        gate.addAsk { false }
        var replies: [Bool] = []
        #expect(AppDelegate.terminationReply(gate: gate) { replies.append($0) } == .terminateLater)
        while replies.isEmpty { await Task.yield() }
        #expect(replies == [false])
    }

    @Test func infoPlistHoldsBothUsageStrings() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Info.plist")
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        #expect(
            plist["NSMicrophoneUsageDescription"] as? String
                == "Bugeye records your microphone only when you turn on Mic for a recording.")
        #expect(
            plist["NSCameraUsageDescription"] as? String
                == "Bugeye shows your camera only when you turn on Cam for a recording.")
        #expect(plist["LSUIElement"] as? Bool == true)
    }

    @Test func nightChromeTokensMatchQuickAccess() {
        #expect(NightChrome.gradientTopHex == 0x2B3242 && NightChrome.gradientBottomHex == 0x1B1F29)
        #expect(NightChrome.textHex == 0xE8EAF0)
        #expect(NightChrome.accentHex == 0xFFC93C && NightChrome.accentHoverHex == 0xFFD666)
        #expect(NightChrome.textOnAccentHex == 0x1F2430)
        #expect(NightChrome.innerBorderOpacity == 0.08)
        #expect(NightChrome.controlFillOpacity == 0.07 && NightChrome.controlHoverOpacity == 0.12)
    }
}
