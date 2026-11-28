import AppKit
import BugeyeCore
import BugeyeTestSupport
import SwiftUI

struct FixtureView: View {
    @State private var text = ""
    @State private var password = ""
    @State private var checked = [false, false]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            List(FixtureContent.lines, id: \.self) { line in
                Text(line)
            }
            .frame(width: 220)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ForEach(FixtureContent.buttons, id: \.self) { title in
                        Button(title) {}
                    }
                    // Recording's Mac batch checks that a click sound reaches system audio (Recording §9.4.2).
                    Button(FixtureContent.playClickButton) { NSSound(named: "Tink")?.play() }
                }
                ForEach(FixtureContent.checkboxes.indices, id: \.self) { index in
                    Toggle(FixtureContent.checkboxes[index], isOn: $checked[index])
                        .toggleStyle(.checkbox)
                }
                TextField(FixtureContent.textFieldPlaceholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                // Typed text here must never reach a recording's timeline (Recording §9.4.5).
                SecureField(FixtureContent.passwordPlaceholder, text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)

                GroupBox(FixtureContent.secretsTitle) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(FixtureContent.secrets, id: \.label) { secret in
                            HStack {
                                Text(secret.label + ":")
                                Text(secret.value)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    ForEach(FixtureContent.swatches, id: \.name) { swatch in
                        Rectangle()
                            .fill(swatchColor(swatch.color))
                            .frame(width: 64, height: 64)
                            .accessibilityLabel(swatch.name)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 600)
    }

    /// Exact sRGB, so pixel checks can compare against `FixtureContent.swatches`.
    private func swatchColor(_ c: RGBA8) -> SwiftUI.Color {
        SwiftUI.Color(
            .sRGB, red: Double(c.red) / 255, green: Double(c.green) / 255, blue: Double(c.blue) / 255,
            opacity: Double(c.alpha) / 255)
    }
}
