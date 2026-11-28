import BugeyeCore
import Testing

@testable import TextCore

@Suite struct PixelResampleTests {
    func grey(_ values: [[UInt8]], padding: Int = 0) throws -> PixelBuffer {
        let width = values[0].count
        var bytes: [UInt8] = []
        for row in values {
            for v in row { bytes += [v, v, v, 255] }
            bytes += Array(repeating: 7, count: padding)
        }
        return try PixelBuffer(width: width, height: values.count, bytesPerRow: width * 4 + padding, bytes: bytes)
    }

    func reds(_ buffer: PixelBuffer) -> [[UInt8]] {
        (0..<buffer.height).map { y in (0..<buffer.width).map { x in buffer.pixel(x: x, y: y)!.red } }
    }

    @Test func twoByTwoEnlargesBilinearly() throws {
        let out = PixelResample.enlarged2x(try grey([[0, 100], [200, 40]]))
        #expect(out.width == 4)
        #expect(out.height == 4)
        // Columns sample x = 0, 0.25, 0.75, 1 (clamped); rows likewise.
        #expect(
            reds(out) == [
                [0, 25, 75, 100],
                [50, 59, 76, 85],
                [150, 126, 79, 55],
                [200, 160, 80, 40],
            ])
    }

    @Test func threeByOneEnlargesBilinearly() throws {
        let out = PixelResample.enlarged2x(try grey([[0, 10, 255]]))
        #expect(out.width == 6)
        #expect(out.height == 2)
        // x = 0, 0.25, 0.75, 1.25, 1.75, 2: 0, 2.5→3, 7.5→8, 71.25→71, 193.75→194, 255.
        #expect(reds(out) == [[0, 3, 8, 71, 194, 255], [0, 3, 8, 71, 194, 255]])
    }

    @Test func alphaIsInterpolatedToo() throws {
        let src = try PixelBuffer(width: 2, height: 1, bytesPerRow: 8, bytes: [0, 0, 0, 0, 0, 0, 0, 255])
        let out = PixelResample.enlarged2x(src)
        #expect((0..<4).map { out.pixel(x: $0, y: 0)!.alpha } == [0, 64, 191, 255])
    }

    @Test func rowsCopiesTheRowsAndDropsPadding() throws {
        let src = try grey([[1, 1], [2, 2], [3, 3], [4, 4]], padding: 4)
        let rows = try PixelResample.rows(src, 1..<3)
        #expect(rows.height == 2)
        #expect(reds(rows) == [[2, 2], [3, 3]])
        #expect(rows.bytesPerRow == 8)
    }

    @Test func noRowsLeftThrows() throws {
        let src = try grey([[1]])
        #expect(throws: PixelBuffer.Error.emptySize(width: 1, height: 0)) { try PixelResample.rows(src, 5..<9) }
    }

    @Test func enlargingAPaddedBufferIgnoresThePadding() throws {
        let out = PixelResample.enlarged2x(try grey([[10, 10]], padding: 8))
        #expect(reds(out) == [[10, 10, 10, 10], [10, 10, 10, 10]])
    }
}
