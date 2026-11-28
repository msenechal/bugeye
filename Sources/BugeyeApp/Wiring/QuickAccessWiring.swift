import BugeyeCore
import BugeyeFeatures
import QuickAccessCore
import SwiftUI

/// Quick Access's wiring (contracts K7): its module, the controller, the built-in ⋯ handlers, the Settings pane and
/// the `quickAccess.stack` debug command. Nothing here shows a window or starts a timer: the first panel and the
/// ticker wait for a `created` event.
@MainActor
enum QuickAccessWiring {
    static let modules: [any FeatureModule] = [QuickAccessModule()]

    static func install(_ context: AppContext) {
        let general = context.general
        let activity = QuickAccessActivity()
        let controller = QuickAccessController(
            bus: context.captureEvents, router: context.router, specs: context.registry.quickAccessActions,
            decorations: context.thumbnailDecorations, clipboard: context.clipboard, notifier: context.notifier,
            settingsStore: context.settingsStore, fileWriter: context.fileWriter, activity: activity,
            saveTarget: { QuickAccessSaveTarget(folder: general.folderURL, displayPath: general.displayedFolder) })

        // Plan P4: a spec is shown only while it has a handler; these run the built-ins when another module asks.
        for id in [QuickAccessActionID.reveal, QuickAccessActionID.delete] {
            context.router.onQuickAccessAction(
                id, QuickAccessActionHandler(perform: { [weak controller] in controller?.runBuiltIn($0) }))
        }

        let store = context.settingsStore
        context.settingsPanes.register(QuickAccessModule.moduleID) {
            AnyView(QuickAccessSettingsPane(model: QuickAccessPaneModel(store: store)))
        }
        #if DEBUG
            DebugQuickAccessCommands.register(controller, in: context.debugCommands)
        #endif
        context.retain(controller)
        context.retain(activity)
    }
}
