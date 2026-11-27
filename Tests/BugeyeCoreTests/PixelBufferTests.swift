import BugeyeCore
import Testing

@Suite struct PixelBufferTests {
    @Test func rejectsEmptySizes() {
        #expect(throws: PixelBuffer.Error.emptySize(width: 0, height: 2)) {
            try PixelBuffer(width: 0, height: 2, bytesPerRow: 0, bytes: [])
        }
    }

    @Test func rejectsRowsShorterThanTheWidth() {
        #expect(throws: PixelBuffer.Error.rowTooShort(bytesPerRow: 7, minimum: 8)) {
            try PixelBuffer(width: 2, height: 1, bytesPerRow: 7, bytes: Array(repeating: 0, count: 7))
        }
    }

    @Test func rejectsTheWrongByteCount() {
        #expect(throws: PixelBuffer.Error.wrongByteCount(actual: 15, expected: 16)) {
            try PixelBuffer(width: 2, height: 2, bytesPerRow: 8, bytes: Array(repeating: 0, count: 15))
        }
    }

    @Test func readsPixelsAcrossRowPadding() throws {
        // 1×2 image, 8 bytes per row: 4 bytes of pixel, 4 bytes of padding per row.
        let bytes: [UInt8] = [1, 2, 3, 4, 9, 9, 9, 9, 5, 6, 7, 8, 9, 9, 9, 9]
        let buffer = try PixelBuffer(width: 1, height: 2, bytesPerRow: 8, bytes: bytes)
        #expect(buffer.pixel(x: 0, y: 0) == RGBA8(red: 1, green: 2, blue: 3, alpha: 4))
        #expect(buffer.pixel(x: 0, y: 1) == RGBA8(red: 5, green: 6, blue: 7, alpha: 8))
    }

    @Test func pixelOutsideTheImageIsNil() throws {
        let buffer = try PixelBuffer(width: 2, height: 2, fill: RGBA8(red: 255, green: 0, blue: 0))
        #expect(buffer.pixel(x: 2, y: 0) == nil)
        #expect(buffer.pixel(x: 0, y: -1) == nil)
        #expect(buffer.pixel(x: 1, y: 1) == RGBA8(red: 255, green: 0, blue: 0, alpha: 255))
    }
}
