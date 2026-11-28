import SwiftUI

/// The night chrome every floating panel shares (`design/01` §2.15, values from Quick Access §4): Quick Access's
/// thumbnails, Recording's options bar and countdown.
enum NightChrome {
    /// sRGB, 0xRRGGBB.
    static let gradientTopHex: UInt32 = 0x2B3242
    static let gradientBottomHex: UInt32 = 0x1B1F29
    static let textHex: UInt32 = 0xE8EAF0
    static let accentHex: UInt32 = 0xFFC93C
    static let accentHoverHex: UInt32 = 0xFFD666
    static let textOnAccentHex: UInt32 = 0x1F2430
    /// White at these opacities.
    static let innerBorderOpacity = 0.08
    static let controlFillOpacity = 0.07
    static let controlHoverOpacity = 0.12

    static func color(_ hex: UInt32) -> SwiftUI.Color {
        SwiftUI.Color(
            .sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, opacity: 1)
    }

    static var gradient: LinearGradient {
        LinearGradient(
            colors: [color(gradientTopHex), color(gradientBottomHex)], startPoint: .top, endPoint: .bottom)
    }
}

/// A night panel: the gradient, a 1 px inner border of white 8 %, light text, dark appearance.
struct NightPanel: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .foregroundStyle(NightChrome.color(NightChrome.textHex))
            .background(NightChrome.gradient, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(SwiftUI.Color.white.opacity(NightChrome.innerBorderOpacity), lineWidth: 1)
            )
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    /// Default corner radius 10 pt.
    func nightPanel(cornerRadius: CGFloat = 10) -> some View {
        modifier(NightPanel(cornerRadius: cornerRadius))
    }
}

/// A night button: white 7 % fill (12 % on hover), or the yellow accent (hover `#FFD666`) with dark text.
struct NightButtonStyle: ButtonStyle {
    var accent: Bool

    init(accent: Bool = false) {
        self.accent = accent
    }

    func makeBody(configuration: Configuration) -> some View {
        NightButton(label: configuration.label, isPressed: configuration.isPressed, accent: accent)
    }
}

private struct NightButton<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let accent: Bool
    @State private var hovering = false

    var body: some View {
        label
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(NightChrome.color(accent ? NightChrome.textOnAccentHex : NightChrome.textHex))
            .background(fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(isPressed ? 0.8 : 1)
            .onHover { hovering = $0 }
    }

    private var fill: SwiftUI.Color {
        if accent { return NightChrome.color(hovering ? NightChrome.accentHoverHex : NightChrome.accentHex) }
        return SwiftUI.Color.white.opacity(hovering ? NightChrome.controlHoverOpacity : NightChrome.controlFillOpacity)
    }
}
