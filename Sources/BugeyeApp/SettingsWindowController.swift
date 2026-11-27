import AICore
import AppKit
import BugeyeFeatures
import SwiftUI

/// The "Bugeye Settings" window: one tab per pane, General then AI.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(panes: [SettingsSectionSpec], general: GeneralSettings, ai: AIKeySettings) {
        let host = NSHostingController(rootView: SettingsView(panes: panes, general: general, ai: ai))
        window = NSWindow(contentViewController: host)
        window.title = ShellStrings.settingsWindowTitle
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        // Size the window before it is first shown: a zero-size window crashed table layout once (design/11 §6).
        let size = host.view.fittingSize
        window.contentMinSize = NSSize(width: max(size.width, 480), height: max(size.height, 260))
        window.setContentSize(window.contentMinSize)
        window.center()
        window.setFrameAutosaveName("BugeyeSettings")
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    let panes: [SettingsSectionSpec]
    let general: GeneralSettings
    let ai: AIKeySettings

    var body: some View {
        TabView {
            ForEach(panes, id: \.id) { pane in
                paneView(pane).tabItem { Text(pane.title) }
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 260)
    }

    @ViewBuilder
    private func paneView(_ pane: SettingsSectionSpec) -> some View {
        switch pane.id {
        case "general": GeneralPane(model: general)
        case "ai": AIPane(model: ai)
        default: EmptyView()
        }
    }
}

struct GeneralPane: View {
    let model: GeneralSettings

    var body: some View {
        Form {
            LabeledContent(ShellStrings.saveCapturesTo) {
                HStack {
                    Text(model.displayedFolder).textSelection(.enabled)
                    Button(ShellStrings.choose) { chooseFolder() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.folderURL
        if panel.runModal() == .OK, let url = panel.url {
            model.choose(url)
        }
    }
}

struct AIPane: View {
    let model: AIKeySettings
    /// What the user typed. Save (or Return) stores it; the field never shows the stored key. Saving an
    /// empty field changes nothing (plan ruling P6).
    @State private var typedKey = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    SecureField(ShellStrings.apiKeyField, text: $typedKey)
                        .onSubmit { save() }
                    Button(ShellStrings.saveKey) { save() }
                }
                HStack {
                    Button(ShellStrings.testKey) {
                        Task { await model.testKey() }
                    }
                    .disabled(model.isTesting || model.status == .noKey)
                    if model.isTesting { ProgressView().controlSize(.small) }
                }
                Text(model.status.message)
            } footer: {
                Text(ShellStrings.aiPrivacyNote)
            }
        }
        .formStyle(.grouped)
    }

    /// The Keychain write runs off the main actor inside `AIKeySettings.save`.
    private func save() {
        let typed = typedKey
        Task { await model.save(typed) }
    }
}
