import BugeyeCore
import Foundation

/// Window captures at full scale (design/02 §2.5). ScreenCaptureKit fits the window **and its shadow** into the
/// requested size, so the body comes out squeezed; the body is found by opacity and the window captured again larger.
public enum WindowShadow {
    /// The opacity of a window body: the shadow stays well under half.
    public static let bodyAlpha: UInt8 = 128
    /// How far the three measurements of one edge may disagree.
    public static let edgeTolerance = 2

    /// The window's own pixels: each edge measured along the rows or columns at ¼, ½ and ¾; nil when any of them
    /// finds nothing opaque or they disagree by more than 2 px (a rounded corner, a translucent toolbar).
    public static func body(in image: PixelBuffer) -> PixelRect? {
        let rows = [image.height / 4, image.height / 2, image.height * 3 / 4]
        let columns = [image.width / 4, image.width / 2, image.width * 3 / 4]
        func opaque(_ x: Int, _ y: Int) -> Bool { (image.pixel(x: x, y: y)?.alpha ?? 0) >= bodyAlpha }

        var lefts: [Int] = []
        var rights: [Int] = []
        for y in rows {
            guard let left = (0..<image.width).first(where: { opaque($0, y) }),
                let right = (0..<image.width).last(where: { opaque($0, y) })
            else { return nil }
            lefts.append(left)
            rights.append(right)
        }
        var tops: [Int] = []
        var bottoms: [Int] = []
        for x in columns {
            guard let top = (0..<image.height).first(where: { opaque(x, $0) }),
                let bottom = (0..<image.height).last(where: { opaque(x, $0) })
            else { return nil }
            tops.append(top)
            bottoms.append(bottom)
        }
        for edge in [lefts, rights, tops, bottoms] where edge.max()! - edge.min()! > edgeTolerance {
            return nil
        }
        let left = lefts.min()!
        let top = tops.min()!
        return PixelRect(
            x: Double(left), y: Double(top), width: Double(rights.max()! - left + 1),
            height: Double(bottoms.max()! - top + 1))
    }

    /// Captures at `windowSize × scale`; when the body came out narrower than `scale × 0.99` pixels per point,
    /// captures once more at `size × scale / got`. Without a body, the first image is kept.
    public static func atFullScale(
        windowSize: Size2D, scale: Double, capture: (Size2D) async throws -> CapturedImage,
        measure: (CapturedImage) -> PixelBuffer?
    ) async throws -> CapturedImage {
        let size = Size2D(width: (windowSize.width * scale).rounded(), height: (windowSize.height * scale).rounded())
        let first = try await capture(size)
        guard windowSize.width > 0, let pixels = measure(first), let body = body(in: pixels) else { return first }
        let got = body.raw.width / windowSize.width
        guard got > 0, got < scale * 0.99 else { return first }
        let larger = Size2D(
            width: (size.width * scale / got).rounded(), height: (size.height * scale / got).rounded())
        return try await capture(larger)
    }
}
