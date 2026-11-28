import BugeyeCore
import Observation
import QuickAccessCore
import SwiftUI

/// The Quick Access pane's model: two settings, written through `SettingsStore` as soon as they change (spec §5.4).
/// A duration change applies to thumbnails shown afterwards, a position change at the next layout (Q8).
@MainActor @Observable
final class QuickAccessPaneModel {
    @ObservationIgnored private let store: any SettingsStore

    var autoDismissSeconds: Int {
        didSet { QuickAccessSettings.store(autoDismissSeconds: autoDismissSeconds, in: store) }
    }
    var position: QuickAccessPosition {
        didSet { QuickAccessSettings.store(position: position, in: store) }
    }

    init(store: any SettingsStore) {
        self.store = store
        let settings = QuickAccessSettings.load(from: store)
        autoDismissSeconds = settings.autoDismissSeconds
        position = settings.position
    }
}

struct QuickAccessSettingsPane: View {
    @Bindable var model: QuickAccessPaneModel

    var body: some View {
        Form {
            Picker(QuickAccessStrings.autoDismissLabel, selection: $model.autoDismissSeconds) {
                ForEach(QuickAccessSettings.autoDismissOptions, id: \.seconds) { option in
                    Text(option.title).tag(option.seconds)
                }
            }
            Picker(QuickAccessStrings.positionLabel, selection: $model.position) {
                ForEach(QuickAccessSettings.positionOptions, id: \.position) { option in
                    Text(option.title).tag(option.position)
                }
            }
        }
        .formStyle(.grouped)
    }
}
