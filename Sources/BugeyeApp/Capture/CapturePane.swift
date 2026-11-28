import BugeyeCore
import CaptureCore
import Observation
import SwiftUI

/// The Capture pane's model: three toggles stored through `SettingsStore` (Capture §5.7).
@MainActor @Observable
final class CapturePaneModel {
    @ObservationIgnored private let store: any SettingsStore
    private(set) var settings: CaptureSettings

    init(store: any SettingsStore) {
        self.store = store
        settings = CaptureSettings.load(from: store)
    }

    var copyToClipboard: Bool {
        get { settings.copyToClipboard }
        set { set(newValue, CaptureSettings.Key.copyToClipboard) }
    }

    var saveToFolder: Bool {
        get { settings.saveToFolder }
        set { set(newValue, CaptureSettings.Key.saveToFolder) }
    }

    var downscaleToPoints: Bool {
        get { settings.downscaleToPoints }
        set { set(newValue, CaptureSettings.Key.downscaleToPoints) }
    }

    private func set(_ value: Bool, _ key: String) {
        store.setValue(.bool(value), forKey: key)
        settings = CaptureSettings.load(from: store)
    }
}

/// Pane `Capture`: one section, `After capture`, with three toggles. The folder stays in General.
struct CapturePane: View {
    @Bindable var model: CapturePaneModel

    var body: some View {
        Form {
            Section(CaptureStrings.afterCapture) {
                Toggle(CaptureStrings.copyToClipboard, isOn: $model.copyToClipboard)
                Toggle(CaptureStrings.saveToFolder, isOn: $model.saveToFolder)
                Toggle(CaptureStrings.downscale, isOn: $model.downscaleToPoints)
            }
        }
        .formStyle(.grouped)
    }
}
