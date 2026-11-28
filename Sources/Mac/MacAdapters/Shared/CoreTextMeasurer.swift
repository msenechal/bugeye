import AppKit
import BugeyeCore
import CoreText

/// The one `FontDescriptor` → font mapping; the display-list executor uses it too (contracts §4.4, K10).
public enum CoreTextFonts {
    /// `system` → the system UI font at `size`, weight 0.4 (or more) bold, 0.3 semibold, else regular; any other
    /// name → that font, else the system font.
    public static func font(for descriptor: FontDescriptor) -> CTFont {
        let size = CGFloat(descriptor.size)
        if descriptor.name != FontDescriptor.systemFontName, let named = NSFont(name: descriptor.name, size: size) {
            return named as CTFont
        }
        let weight: NSFont.Weight =
            descriptor.weight >= 0.4 ? .bold : descriptor.weight >= 0.3 ? .semibold : .regular
        return NSFont.systemFont(ofSize: size, weight: weight) as CTFont
    }
}

/// Measures one line with `CTLine` typographic bounds, in pixels at `font.size` (contracts §4.4, K38).
public struct CoreTextMeasurer: TextMeasuring {
    public init() {}

    public func measure(_ line: String, font: FontDescriptor) -> TextLineMetrics {
        let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): CoreTextFonts.font(for: font)]
        let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading)
        return TextLineMetrics(width: Double(width), ascent: Double(ascent), descent: Double(descent))
    }
}
