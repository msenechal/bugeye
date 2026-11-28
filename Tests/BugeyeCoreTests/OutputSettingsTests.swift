import BugeyeCore
import BugeyeTestSupport
import Testing

@Suite struct OutputSettingsTests {
    @Test func keysAreCapturesOwn() {
        #expect(OutputSettings.Key.copyToClipboard == "capture.copyToClipboard")
        #expect(OutputSettings.Key.saveToFolder == "capture.saveToFolder")
    }

    @Test func missingValuesFallBackToTheDefaults() {
        #expect(OutputSettings.load(from: InMemorySettingsStore()) == OutputSettings())
        #expect(OutputSettings() == OutputSettings(copyToClipboard: true, saveToFolder: true))
    }

    @Test func storedBoolsAreRead() {
        let store = InMemorySettingsStore([
            "capture.copyToClipboard": .bool(false), "capture.saveToFolder": .bool(false),
        ])
        #expect(OutputSettings.load(from: store) == OutputSettings(copyToClipboard: false, saveToFolder: false))
    }

    @Test func nonBoolValuesFallBackToTheDefaults() {
        let store = InMemorySettingsStore([
            "capture.copyToClipboard": .string("no"), "capture.saveToFolder": .int(0),
        ])
        #expect(OutputSettings.load(from: store) == OutputSettings())
    }

    @Test func theFolderNoticeIsSettled() {
        #expect(OutputStrings.folderUnavailableTitle == "Couldn't save to folder")
        #expect(
            OutputStrings.folderUnavailableBody(path: "~/Pictures/Bugeye/")
                == "~/Pictures/Bugeye/ is unavailable. The capture is kept temporarily; use Save in Quick Access.")
    }
}
