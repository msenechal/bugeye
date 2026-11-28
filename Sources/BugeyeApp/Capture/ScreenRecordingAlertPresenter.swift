import AppKit
import BugeyeCore
import CaptureCore
import Foundation

/// Capture §5.5's alert, installed as `AppContext.screenRecordingAlert.presenter` so Recording shows it too.
@MainActor
enum ScreenRecordingAlertPresenter {
    enum Choice: Equatable { case openSystemSettings, relaunch, cancel }

    static func present(permission: any ScreenCapturePermission) {
        let alert = NSAlert()
        alert.messageText = CaptureStrings.permissionTitle
        alert.informativeText = CaptureStrings.permissionText
        alert.addButton(withTitle: CaptureStrings.openSystemSettings)
        alert.addButton(withTitle: CaptureStrings.relaunch)
        alert.addButton(withTitle: CaptureStrings.cancel)
        NSApp.activate()
        let choice: Choice =
            switch alert.runModal() {
            case .alertFirstButtonReturn: .openSystemSettings
            case .alertSecondButtonReturn: .relaunch
            default: .cancel
            }
        handle(choice, permission: permission)
    }

    static func handle(
        _ choice: Choice, permission: any ScreenCapturePermission,
        open: (URL) -> Void = { NSWorkspace.shared.open($0) }, relaunch: () -> Void = { Self.relaunch() }
    ) {
        switch choice {
        case .openSystemSettings:
            // Adds Bugeye to the list (prompting at most once), then opens the pane.
            permission.requestAccess()
            if let url = URL(string: CaptureStrings.screenRecordingSettingsURL) { open(url) }
        case .relaunch:
            relaunch()
        case .cancel:
            break
        }
    }

    /// The shell script that waits for `pid` to exit (polling every 0.1 s for at most 5 s), then opens `path`.
    /// The pid and path go in as `$1` and `$2`, never into the script text.
    static let relaunchScript =
        "i=0; while kill -0 \"$1\" 2>/dev/null && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done; open \"$2\""

    static func relaunchArguments(pid: Int32, bundlePath: String) -> [String] {
        ["-c", relaunchScript, "sh", String(pid), bundlePath]
    }

    /// Relaunches by Bugeye's own bundle path, so the old app in /Applications stays out of it.
    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = relaunchArguments(
            pid: ProcessInfo.processInfo.processIdentifier, bundlePath: Bundle.main.bundlePath)
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            NSSound.beep()
        }
    }
}
