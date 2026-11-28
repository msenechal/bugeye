import BugeyeCore
import BugeyeFeatures
import Foundation
import Testing

@MainActor @Suite struct ActionRouterTests {
    let router = ActionRouter()

    func item(_ kind: CaptureKind) -> CaptureItem {
        CaptureItem(
            id: CaptureID(), fileURL: URL(fileURLWithPath: "/tmp/a"), isSaved: true, kind: kind, createdAt: Date(),
            pixelsPerPoint: 2)
    }

    @Test func unregisteredIDsAnswerFalseOrNil() {
        #expect(!router.performMenuItem("capture.area"))
        #expect(!router.isMenuItemEnabled("capture.area"))
        #expect(!router.performHotkey("capture.area"))
        #expect(router.quickAccessHandler(for: "editor.edit") == nil)
        #expect(!router.canOpen(.screenshot))
        #expect(!router.open(item(.screenshot)))
        #expect(router.duplicates == [])
    }

    @Test func registeredHandlersRun() {
        var log: [String] = []
        router.onMenuItem("capture.area") { log.append("menu") }
        router.onHotkey("capture.area") { log.append("hotkey") }
        router.onOpen(.screenshot) { log.append("open \($0.kind.rawValue)") }
        router.onQuickAccessAction(
            "editor.edit", QuickAccessActionHandler(perform: { log.append("qa \($0.actionID)") }))
        #expect(router.performMenuItem("capture.area"))
        #expect(router.performHotkey("capture.area"))
        #expect(router.canOpen(.screenshot) && !router.canOpen(.recording))
        #expect(router.open(item(.screenshot)))
        #expect(!router.open(item(.recording)))
        let handler = try? #require(router.quickAccessHandler(for: "editor.edit"))
        handler?.perform(QuickAccessActionContext(actionID: "editor.edit", items: [], trigger: .menu))
        #expect(log == ["menu", "hotkey", "open screenshot", "qa editor.edit"])
    }

    @Test func isEnabledIsAskedEachTime() {
        var enabled = false
        var asked = 0
        router.onMenuItem(
            "recording.record",
            isEnabled: {
                asked += 1
                return enabled
            }, perform: {})
        #expect(!router.isMenuItemEnabled("recording.record"))
        enabled = true
        #expect(router.isMenuItemEnabled("recording.record"))
        #expect(asked == 2)
        router.onMenuItem("capture.area") {}
        #expect(router.isMenuItemEnabled("capture.area"))
    }

    @Test func performingAMenuItemNeverAsksIsEnabled() {
        // Override-menu entries go through performMenuItem; their own Entry.isEnabled decides (K35).
        var asked = 0
        var performed = 0
        router.onMenuItem(
            "recording.stop",
            isEnabled: {
                asked += 1
                return false
            }, perform: { performed += 1 })
        #expect(router.performMenuItem("recording.stop"))
        #expect(performed == 1 && asked == 0)
    }

    @Test func duplicatesAreRecordedAndTheFirstIsKept() {
        var log: [String] = []
        router.onMenuItem("m") { log.append("m1") }
        router.onMenuItem("m") { log.append("m2") }
        router.onHotkey("h") { log.append("h1") }
        router.onHotkey("h") { log.append("h2") }
        router.onQuickAccessAction("q", QuickAccessActionHandler(perform: { _ in log.append("q1") }))
        router.onQuickAccessAction("q", QuickAccessActionHandler(perform: { _ in log.append("q2") }))
        router.onOpen(.screenshot) { _ in log.append("o1") }
        router.onOpen(.screenshot) { _ in log.append("o2") }
        router.performMenuItem("m")
        router.performHotkey("h")
        router.quickAccessHandler(for: "q")?.perform(
            QuickAccessActionContext(actionID: "q", items: [], trigger: .strip))
        router.open(item(.screenshot))
        #expect(log == ["m1", "h1", "q1", "o1"])
        #expect(router.duplicates == ["menu:m", "hotkey:h", "quickAccess:q", "open:screenshot"])
    }

    @Test func aMenuIDAndAHotkeyIDMayMatch() {
        router.onMenuItem("capture.area") {}
        router.onHotkey("capture.area") {}
        #expect(router.duplicates == [])
    }
}
