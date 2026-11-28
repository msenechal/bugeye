import BugeyeCore
import BugeyeTestSupport
import QuickAccessCore
import Testing

@Suite struct QuickAccessSettingsTests {
    @Test func keysMatchSpecSection5_4() {
        #expect(QuickAccessSettings.Key.autoDismissSeconds == "quickAccess.autoDismissSeconds")
        #expect(QuickAccessSettings.Key.position == "quickAccess.position")
        #expect(QuickAccessPosition.bottomLeft.rawValue == "bottomLeft")
        #expect(QuickAccessPosition.bottomRight.rawValue == "bottomRight")
    }

    @Test func missingValuesGiveTheDefaults() {
        let settings = QuickAccessSettings.load(from: InMemorySettingsStore())
        #expect(settings == QuickAccessSettings(autoDismissSeconds: 5, position: .bottomLeft))
        #expect(settings.duration == 5)
    }

    @Test func validValuesAreRead() {
        for seconds in [0, 5, 10, 30, 60] {
            let store = InMemorySettingsStore([
                QuickAccessSettings.Key.autoDismissSeconds: .int(seconds),
                QuickAccessSettings.Key.position: .string("bottomRight"),
            ])
            let settings = QuickAccessSettings.load(from: store)
            #expect(settings.autoDismissSeconds == seconds)
            #expect(settings.position == .bottomRight)
        }
    }

    @Test func neverMeansNoDuration() {
        let store = InMemorySettingsStore([QuickAccessSettings.Key.autoDismissSeconds: .int(0)])
        #expect(QuickAccessSettings.load(from: store).duration == nil)
    }

    @Test(arguments: [SettingValue.int(7), .int(-5), .int(3600), .string("5"), .bool(true), .double(5)])
    func invalidDurationsFallBackToFiveSeconds(_ value: SettingValue) {
        let store = InMemorySettingsStore([QuickAccessSettings.Key.autoDismissSeconds: value])
        #expect(QuickAccessSettings.load(from: store).autoDismissSeconds == 5)
    }

    @Test(arguments: [SettingValue.string("topLeft"), .string("BottomRight"), .string(""), .int(1), .bool(false)])
    func invalidPositionsFallBackToBottomLeft(_ value: SettingValue) {
        let store = InMemorySettingsStore([QuickAccessSettings.Key.position: value])
        #expect(QuickAccessSettings.load(from: store).position == .bottomLeft)
    }

    @Test func storingWritesOnlyThatKey() {
        let store = InMemorySettingsStore()
        QuickAccessSettings.store(autoDismissSeconds: 30, in: store)
        #expect(store.all == [QuickAccessSettings.Key.autoDismissSeconds: .int(30)])
        QuickAccessSettings.store(position: .bottomRight, in: store)
        #expect(store.all[QuickAccessSettings.Key.position] == .string("bottomRight"))
        #expect(
            QuickAccessSettings.load(from: store) == QuickAccessSettings(autoDismissSeconds: 30, position: .bottomRight)
        )
    }

    @Test func paneOptionsAreInSpecOrder() {
        #expect(QuickAccessSettings.autoDismissOptions.map(\.seconds) == [0, 5, 10, 30, 60])
        #expect(
            QuickAccessSettings.autoDismissOptions.map(\.title) == [
                "Never", "5 seconds", "10 seconds", "30 seconds", "60 seconds",
            ])
        #expect(QuickAccessSettings.positionOptions.map(\.position) == [.bottomLeft, .bottomRight])
        #expect(QuickAccessSettings.positionOptions.map(\.title) == ["Bottom left", "Bottom right"])
    }
}
