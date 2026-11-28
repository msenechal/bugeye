import AppKit
import BugeyeCore
import BugeyeFeatures
import Observation
import SwiftUI

/// The pane's observable wrapper around `ShortcutsModel` (Capture §5.6, C5).
@MainActor @Observable
final class ShortcutsPaneModel {
    @ObservationIgnored let model: ShortcutsModel
    private(set) var rows: [ShortcutsModel.Row]

    init(model: ShortcutsModel) {
        self.model = model
        rows = model.rows
        let previous = model.onChange
        model.onChange = { [weak self] in
            previous?()
            self?.rows = model.rows
        }
    }

    func fieldText(_ row: ShortcutsModel.Row) -> String { model.fieldText(row) }

    func handle(_ input: ShortcutKeyInput, for id: String) {
        switch input {
        case .escape: model.escapeTyped(id)
        case .delete: model.deleteTyped(id)
        case .combo(let combo): model.typed(combo, for: id)
        case .ignored: break
        }
    }
}

/// A key typed into a recording shortcut field.
enum ShortcutKeyInput: Equatable {
    case escape, delete, ignored
    case combo(KeyCombo)

    /// 53 Esc keeps the old combo; 51 Delete and 117 Forward Delete clear it; anything else is a combo (validated by
    /// the model); a key with no character is ignored.
    static func from(keyCode: UInt16, characters: String?, flags: NSEvent.ModifierFlags) -> ShortcutKeyInput {
        switch keyCode {
        case 53: return .escape
        case 51, 117: return .delete
        default: break
        }
        guard let characters, characters.count == 1, let first = characters.first, !first.isWhitespace else {
            return .ignored
        }
        var modifiers: Set<KeyModifier> = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return .combo(KeyCombo(String(first).lowercased(), modifiers))
    }
}

struct ShortcutsPane: View {
    let model: ShortcutsPaneModel

    var body: some View {
        Form {
            Section {
                ForEach(model.rows, id: \.spec.id) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(row.spec.title) {
                            ShortcutField(
                                text: model.fieldText(row), isRecording: row.isRecording,
                                onClick: { model.model.startRecording(row.spec.id) },
                                onKey: { model.handle($0, for: row.spec.id) }
                            )
                            .frame(width: 140, height: 22)
                        }
                        if let message = row.message {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\u{26A0} " + message.text).foregroundStyle(.orange).font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let button = message.button {
                                    Button(
                                        button == .tryAgain
                                            ? ShortcutStrings.tryAgain : ShortcutStrings.keyboardShortcuts
                                    ) {
                                        switch button {
                                        case .tryAgain: model.model.tryAgain(row.spec.id)
                                        case .keyboardShortcuts:
                                            if let url = URL(string: ShortcutStrings.keyboardSettingsURL) {
                                                NSWorkspace.shared.open(url)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(ShortcutStrings.footer)
                    Button(ShortcutStrings.restoreDefaults) { model.model.restoreDefaults() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// A clickable field that records the next key while `isRecording`.
struct ShortcutField: NSViewRepresentable {
    let text: String
    let isRecording: Bool
    let onClick: () -> Void
    let onKey: (ShortcutKeyInput) -> Void

    func makeNSView(context: Context) -> ShortcutFieldButton {
        let button = ShortcutFieldButton(title: text, target: nil, action: nil)
        button.bezelStyle = .push
        return button
    }

    func updateNSView(_ button: ShortcutFieldButton, context: Context) {
        button.title = text
        button.isRecording = isRecording
        button.onClick = onClick
        button.onKey = onKey
        if isRecording, button.window?.firstResponder !== button {
            DispatchQueue.main.async { button.window?.makeFirstResponder(button) }
        }
    }
}

@MainActor
final class ShortcutFieldButton: NSButton {
    var isRecording = false
    var onClick: () -> Void = {}
    var onKey: (ShortcutKeyInput) -> Void = { _ in }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        onKey(
            ShortcutKeyInput.from(
                keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, flags: event.modifierFlags))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // While recording, ⌘-combos come here first; take them as the shortcut.
        guard isRecording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
}
