import BugeyeCore
import Foundation
import MacAdapters
import Testing

@Suite struct UserDefaultsSettingsStoreTests {
    /// A private defaults domain per test; removed afterwards.
    func withStore(_ body: (UserDefaultsSettingsStore, UserDefaults) throws -> Void) throws {
        let suite = "dev.msenechal.bugeye.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(UserDefaultsSettingsStore(defaults: defaults), defaults)
    }

    @Test func everyValueTypeRoundTrips() throws {
        try withStore { store, _ in
            store.setValue(.string("~/Pictures/Bugeye/"), forKey: "s")
            store.setValue(.bool(true), forKey: "b")
            store.setValue(.int(30_000), forKey: "i")
            store.setValue(.double(0.03), forKey: "d")
            #expect(store.value(forKey: "s") == .string("~/Pictures/Bugeye/"))
            #expect(store.value(forKey: "b") == .bool(true))
            #expect(store.value(forKey: "i") == .int(30_000))
            #expect(store.value(forKey: "d") == .double(0.03))
        }
    }

    @Test func nilRemovesAndMissingIsNil() throws {
        try withStore { store, _ in
            store.setValue(.int(1), forKey: "k")
            store.setValue(nil, forKey: "k")
            #expect(store.value(forKey: "k") == nil)
        }
    }

    @Test func unsupportedTypesReadAsNil() throws {
        try withStore { store, defaults in
            defaults.set(["a"], forKey: "array")
            #expect(store.value(forKey: "array") == nil)
        }
    }

    @Test func appSettingsLoadAndSaveThroughIt() throws {
        try withStore { store, _ in
            var settings = AppSettings.load(from: store)
            #expect(settings == AppSettings())
            let old = settings
            settings.saveFolder = "/Volumes/Shots/"
            settings.save(to: store, comparedTo: old)
            #expect(AppSettings.load(from: store).saveFolder == "/Volumes/Shots/")
        }
    }
}
