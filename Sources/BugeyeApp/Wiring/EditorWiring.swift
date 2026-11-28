import BugeyeCore
import BugeyeFeatures
import EditorCore
import Foundation

/// The editor's registration (E2, K7): the module, the Quick Access Edit action (button and double-click),
/// Open Last Capture, the screenshot opener and the quit prompt.
@MainActor
enum EditorWiring {
    static let modules: [any FeatureModule] = [EditorModule()]

    static func install(_ context: AppContext) {
        let manager = EditorManager(
            environment: EditorManager.environment(
                bus: context.captureEvents, documentWindows: context.documentWindows, writer: context.fileWriter,
                clipboard: context.clipboard, notifier: context.notifier,
                saveFolder: { [weak context] in context?.general.folderURL ?? URL(fileURLWithPath: NSHomeDirectory()) }
            ))
        let lastCapture = LastCapture(bus: context.captureEvents, router: context.router)
        context.retain(manager)
        context.retain(lastCapture)

        context.router.onQuickAccessAction(
            EditorModule.editActionID,
            QuickAccessActionHandler(perform: { [weak manager] action in
                guard let item = action.items.first, item.kind == .screenshot else { return }
                manager?.open(item)
            }))
        context.router.onMenuItem(
            EditorModule.openLastCaptureID, isEnabled: { [weak lastCapture] in lastCapture?.isEnabled ?? false },
            perform: { [weak lastCapture] in lastCapture?.open() })
        context.router.onOpen(.screenshot) { [weak manager] item in manager?.open(item) }
        context.termination.addAsk { [weak manager] in await manager?.sessions.shouldTerminate() ?? true }
    }
}
