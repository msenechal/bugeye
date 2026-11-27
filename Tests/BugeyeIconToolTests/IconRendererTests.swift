import Foundation
import Testing

@testable import BugeyeIconTool

@Suite struct IconRendererTests {
    /// The RGBA bytes at (x, y), y counted from the top row.
    func pixel(_ pixels: [UInt8], side: Int, x: Int, y: Int) -> [UInt8] {
        let i = (y * side + x) * 4
        return Array(pixels[i..<(i + 4)])
    }

    @Test func iconCornersAreTransparentAndItsMiddleIsOpaque() throws {
        let side = 256
        let pixels = try IconRenderer.iconPixels(side: side)
        #expect(pixel(pixels, side: side, x: 0, y: 0)[3] == 0)
        #expect(pixel(pixels, side: side, x: side / 2, y: side / 2)[3] == 255)
    }

    @Test func theBugIsYellow() throws {
        let side = 256
        let pixels = try IconRenderer.iconPixels(side: side)
        // Below the eye, inside the body: x = 0.45 s, y = 0.30 s from the bottom → 0.70 s from the top.
        let p = pixel(pixels, side: side, x: Int(0.45 * Double(side)), y: Int(0.70 * Double(side)))
        #expect(p[0] > 200 && p[1] > 150 && p[2] < 120)
    }

    @Test func theGlyphIsBlackOnTransparentWithTheEyeCutOut() throws {
        let side = 36
        let pixels = try IconRenderer.glyphPixels(side: side)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            #expect(pixels[i] == 0 && pixels[i + 1] == 0 && pixels[i + 2] == 0)
        }
        #expect(pixels.enumerated().contains { $0.offset % 4 == 3 && $0.element == 255 })
        // The ring around the lens is clear near its left edge (x = 0.43 s; the eye's centre is 0.46 s from the
        // bottom, so 0.54 s from the top).
        let ring = pixel(pixels, side: side, x: Int(0.43 * Double(side)), y: Int(0.54 * Double(side)))
        #expect(ring[3] == 0)
    }

    @Test func everyIconsetSizeEncodesAsPNG() throws {
        for (_, side) in IconRenderer.iconsetFiles where side <= 64 {
            let png = try IconRenderer.png(side: side, glyph: false)
            #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        }
        #expect(IconRenderer.iconsetFiles.count == 10)
    }
}
