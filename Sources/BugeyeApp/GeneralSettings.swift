import BugeyeCore
import Foundation
import Observation
import os

/// The General pane's model: the save folder, shown as `~/…`, stored through `SettingsStore`.
@MainActor @Observable
final class GeneralSettings {
    private(set) var settings: AppSettings
    @ObservationIgnored private let store: any SettingsStore
    @ObservationIgnored private let home: String

    init(store: any SettingsStore, home: String) {
        self.store = store
        self.home = home
        settings = AppSettings.load(from: store)
    }

    /// What "Save captures to" shows.
    var displayedFolder: String {
        FolderPath.abbreviatingHome(FolderPath.expandingTilde(settings.saveFolder, home: home), home: home)
    }

    var folderURL: URL {
        URL(fileURLWithPath: FolderPath.expandingTilde(settings.saveFolder, home: home), isDirectory: true)
    }

    /// Stores a folder the user chose, as `~/…` when it's inside the home folder.
    func choose(_ folder: URL) {
        var path = folder.standardizedFileURL.path
        if !path.hasSuffix("/") { path += "/" }
        let old = settings
        settings.saveFolder = FolderPath.abbreviatingHome(path, home: home)
        settings.save(to: store, comparedTo: old)
        ensureFolderExists()
    }

    /// Creates the save folder if it's missing (first launch, or a folder deleted since).
    func ensureFolderExists() {
        do {
            try SaveFolder.ensureExists(at: folderURL)
        } catch {
            Logger(subsystem: "dev.msenechal.bugeye", category: "app")
                .error("Couldn't create the save folder: \(String(describing: error), privacy: .public)")
        }
    }
}
