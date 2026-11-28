import BugeyeCore
import EditorCore
import Testing

@Suite struct RegionEffectsTests {
    /// A buffer from one grey value per pixel (r = g = b = value, alpha 255), row by row.
    static func grey(_ width: Int, _ height: Int, _ values: [UInt8]) throws -> PixelBuffer {
        var bytes: [UInt8] = []
        for v in values { bytes += [v, v, v, 255] }
        return try PixelBuffer(width: width, height: height, bytesPerRow: width * 4, bytes: bytes)
    }

    static func reds(_ buffer: PixelBuffer) -> [UInt8] {
        (0..<buffer.height).flatMap { y in (0..<buffer.width).map { x in buffer.pixel(x: x, y: y)!.red } }
    }

    @Test func pixelateAveragesEachCellWithTheGridAnchoredAtTheOrigin() throws {
        let buffer = try Self.grey(3, 3, [0, 10, 100, 20, 30, 200, 7, 8, 9])
        let out = RegionEffects.pixelate(buffer, cellSize: 2)
        // cells: (0,0) 2×2 → (0+10+20+30)/4 = 15; (2,0) 1×2 → (100+200)/2 = 150; (0,2) 2×1 → 7.5 → 8; (2,2) → 9
        #expect(Self.reds(out) == [15, 15, 150, 15, 15, 150, 8, 8, 9])
        #expect(out.pixel(x: 0, y: 0)?.alpha == 255)
        #expect(out.width == 3 && out.height == 3 && out.bytesPerRow == 12)
    }

    @Test func pixelateRoundsTheCellSizeAndCellOneIsTheIdentity() throws {
        let buffer = try Self.grey(3, 1, [1, 2, 3])
        #expect(Self.reds(RegionEffects.pixelate(buffer, cellSize: 0.4)) == [1, 2, 3])
        #expect(Self.reds(RegionEffects.pixelate(buffer, cellSize: 2.6)) == [2, 2, 2])
    }

    @Test func pixelateAveragesEveryChannelIncludingAlpha() throws {
        let buffer = try PixelBuffer(width: 2, height: 1, bytesPerRow: 8, bytes: [10, 20, 30, 0, 11, 21, 31, 255])
        let out = RegionEffects.pixelate(buffer, cellSize: 2)
        #expect(out.pixel(x: 0, y: 0) == RGBA8(red: 11, green: 21, blue: 31, alpha: 128))
    }

    @Test func theThreeBoxesApproximateTheGaussian() {
        #expect(RegionEffects.boxSizes(sigma: 5) == [9, 9, 11])
        #expect(RegionEffects.boxSizes(sigma: 10) == [19, 19, 21])
        #expect(RegionEffects.boxSizes(sigma: 0.3) == [1, 1, 1])
    }

    @Test func gaussianOfAConstantIsConstantAndRadiusZeroIsTheIdentity() throws {
        let flat = try Self.grey(6, 5, Array(repeating: 77, count: 30))
        #expect(RegionEffects.gaussianBlur(flat, radius: 10) == flat)
        let varied = try Self.grey(3, 1, [0, 128, 255])
        #expect(RegionEffects.gaussianBlur(varied, radius: 0) == varied)
    }

    @Test func edgesAreClampedSoTheBorderDoesNotFade() throws {
        let buffer = try Self.grey(8, 2, [255, 255, 255, 255, 0, 0, 0, 0, 255, 255, 255, 255, 0, 0, 0, 0])
        let out = RegionEffects.gaussianBlur(buffer, radius: 1)
        #expect(out.pixel(x: 0, y: 0)?.red == 255)
        #expect(out.pixel(x: 7, y: 1)?.red == 0)
        #expect(out.pixel(x: 0, y: 0)?.alpha == 255)
    }

    @Test func aBrightPixelSpreadsSymmetrically() throws {
        var values = [UInt8](repeating: 0, count: 81)
        values[40] = 255
        let out = RegionEffects.gaussianBlur(try Self.grey(9, 9, values), radius: 1.5)
        let reds = Self.reds(out)
        for k in 1...3 {
            #expect(reds[40 - k] == reds[40 + k])
            #expect(reds[40 - 9 * k] == reds[40 + 9 * k])
        }
        #expect(reds[40] < 255 && reds[40] > reds[41])
    }

    @Test func gaussianMatchesThreeNaiveBoxPassesByteForByte() throws {
        let values: [UInt8] = (0..<35).map { UInt8(($0 * 53 + 11) % 256) }
        let buffer = try Self.grey(7, 5, values)
        let out = RegionEffects.gaussianBlur(buffer, radius: 2)
        // Reference: each box (sizes for σ = 2) horizontally then vertically, clamped, round half up.
        var grid = (0..<5).map { y in (0..<7).map { x in Int(values[y * 7 + x]) } }
        for size in RegionEffects.boxSizes(sigma: 2) {
            let r = (size - 1) / 2
            grid = grid.map { row in
                (0..<7).map { x in
                    let sum = (-r...r).reduce(0) { $0 + row[min(6, max(0, x + $1))] }
                    return (sum + size / 2) / size
                }
            }
            let columns = (0..<7).map { x in (0..<5).map { y in grid[y][x] } }
            let blurred = columns.map { column in
                (0..<5).map { y in
                    let sum = (-r...r).reduce(0) { $0 + column[min(4, max(0, y + $1))] }
                    return (sum + size / 2) / size
                }
            }
            grid = (0..<5).map { y in (0..<7).map { x in blurred[x][y] } }
        }
        #expect(Self.reds(out) == grid.flatMap { $0.map(UInt8.init) })
    }

    @Test func rowPaddingIsIgnored() throws {
        let buffer = try PixelBuffer(
            width: 1, height: 2, bytesPerRow: 8,
            bytes: [10, 10, 10, 255, 99, 99, 99, 99, 30, 30, 30, 255, 99, 99, 99, 99])
        let out = RegionEffects.pixelate(buffer, cellSize: 2)
        #expect(Self.reds(out) == [20, 20])
        #expect(out.bytesPerRow == 4)
    }
}
