import AppKit
import BugeyeFeatures
import Testing

@testable import BugeyeApp

@MainActor @Suite struct MenuBuilderTests {
    final class Target: NSObject {
        @objc func chosen(_ sender: NSMenuItem) {}
    }

    @Test func theMenuMatchesSpecSection5_3() throws {
        // K20: the shell's own menu, never the live module list, so an epic filling its wiring breaks nothing here.
        let registry = try FeatureRegistry([GeneralModule()])
        let target = Target()
        let menu = MenuBuilder.menu(
            StatusMenu.entries(for: registry), target: target, action: #selector(Target.chosen(_:)))

        #expect(
            menu.items.map { $0.isSeparatorItem ? "—" : $0.title } == [
                "About Bugeye", "—", "Settings\u{2026}", "—", "Quit Bugeye",
            ])
        let settings = menu.items[2]
        #expect(settings.keyEquivalent == ",")
        #expect(settings.keyEquivalentModifierMask == .command)
        let quit = menu.items[4]
        #expect(quit.keyEquivalent == "q")
        #expect(quit.keyEquivalentModifierMask == .command)
        #expect(menu.items[0].keyEquivalent == "")
        #expect(menu.items.compactMap { $0.identifier?.rawValue } == ["app.about", "app.settings", "app.quit"])
    }

    @Test func modifiersMapToAppKitFlags() {
        #expect(MenuBuilder.modifierFlags([.shift, .command]) == [.shift, .command])
        #expect(MenuBuilder.modifierFlags([]) == [])
    }
}
