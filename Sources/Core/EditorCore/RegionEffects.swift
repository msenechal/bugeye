import BugeyeCore

/// Blur and pixelate on `PixelBuffer`, portable and byte-exact (E5, §7). The shell extracts the source rect from
/// the original capture in its own colour space, runs these, and wraps the result back with the same space.
/// Results are tightly packed and in the input's colour space (no conversion).
public enum RegionEffects {
    /// Averages each `cellSize` × `cellSize` cell (rounded, at least 1), the grid anchored at the buffer's top-left,
    /// partial cells at the right and bottom edges; every channel, round half up (plan P12).
    public static func pixelate(_ buffer: PixelBuffer, cellSize: Double) -> PixelBuffer {
        let cell = max(1, Int(cellSize.rounded()))
        let width = buffer.width
        let height = buffer.height
        var out = [UInt8](repeating: 0, count: width * height * 4)
        buffer.bytes.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                var y0 = 0
                while y0 < height {
                    let y1 = min(height, y0 + cell)
                    var x0 = 0
                    while x0 < width {
                        let x1 = min(width, x0 + cell)
                        var sums = (0, 0, 0, 0)
                        for y in y0..<y1 {
                            var i = y * buffer.bytesPerRow + x0 * 4
                            for _ in x0..<x1 {
                                sums.0 += Int(src[i])
                                sums.1 += Int(src[i + 1])
                                sums.2 += Int(src[i + 2])
                                sums.3 += Int(src[i + 3])
                                i += 4
                            }
                        }
                        let n = (y1 - y0) * (x1 - x0)
                        let half = n / 2
                        let value = (
                            UInt8((sums.0 + half) / n), UInt8((sums.1 + half) / n), UInt8((sums.2 + half) / n),
                            UInt8((sums.3 + half) / n)
                        )
                        for y in y0..<y1 {
                            var i = (y * width + x0) * 4
                            for _ in x0..<x1 {
                                dst[i] = value.0
                                dst[i + 1] = value.1
                                dst[i + 2] = value.2
                                dst[i + 3] = value.3
                                i += 4
                            }
                        }
                        x0 = x1
                    }
                    y0 = y1
                }
            }
        }
        return packed(width, height, out)
    }

    /// The widths (odd) of the three boxes whose successive passes approximate a gaussian of `sigma`
    /// (W. Jarosz, "Fast image convolutions").
    public static func boxSizes(sigma: Double) -> [Int] {
        let n = 3.0
        let ideal = (12 * sigma * sigma / n + 1).squareRoot()
        var lower = Int(ideal.rounded(.down))
        if lower % 2 == 0 { lower -= 1 }
        lower = max(1, lower)
        let upper = lower + 2
        let l = Double(lower)
        let mIdeal = (12 * sigma * sigma - n * l * l - 4 * n * l - 3 * n) / (-4 * l - 4)
        let m = Int(mIdeal.rounded())
        return (0..<3).map { $0 < m ? lower : upper }
    }

    /// Three box passes per axis with the sizes of `boxSizes(sigma: radius)`, edges clamped (as Core Image's
    /// `clampedToExtent()`), integer running sums, round half up. Radius 0 returns the input unchanged.
    public static func gaussianBlur(_ buffer: PixelBuffer, radius: Double) -> PixelBuffer {
        let width = buffer.width
        let height = buffer.height
        var a = [UInt8](repeating: 0, count: width * height * 4)
        buffer.bytes.withUnsafeBufferPointer { src in
            a.withUnsafeMutableBufferPointer { dst in
                for y in 0..<height {
                    let s = y * buffer.bytesPerRow
                    let d = y * width * 4
                    for i in 0..<(width * 4) { dst[d + i] = src[s + i] }
                }
            }
        }
        guard radius > 0 else { return packed(width, height, a) }
        var b = a
        for size in boxSizes(sigma: radius) where size > 1 {
            horizontalPass(from: a, into: &b, width: width, height: height, radius: (size - 1) / 2)
            verticalPass(from: b, into: &a, width: width, height: height, radius: (size - 1) / 2)
        }
        return packed(width, height, a)
    }

    /// `(sum + size / 2) / size` without a division: exact for sums up to 256 × size (see the test against
    /// naive passes).
    @inline(__always) private static func average(_ sum: UInt64, _ half: UInt64, _ inverse: UInt64) -> UInt8 {
        UInt8(truncatingIfNeeded: ((sum + half) &* inverse) >> 32)
    }

    private static func horizontalPass(
        from source: [UInt8], into target: inout [UInt8], width: Int, height: Int, radius r: Int
    ) {
        let size = 2 * r + 1
        let half = UInt64(size / 2)
        let inverse = ((UInt64(1) << 32) + UInt64(size) - 1) / UInt64(size)
        let last = width - 1
        source.withUnsafeBufferPointer { src in
            target.withUnsafeMutableBufferPointer { dst in
                for y in 0..<height {
                    let row = y * width * 4
                    var s0: UInt64 = 0
                    var s1: UInt64 = 0
                    var s2: UInt64 = 0
                    var s3: UInt64 = 0
                    for k in -r...r {
                        let i = row + min(last, max(0, k)) * 4
                        s0 += UInt64(src[i])
                        s1 += UInt64(src[i + 1])
                        s2 += UInt64(src[i + 2])
                        s3 += UInt64(src[i + 3])
                    }
                    for x in 0..<width {
                        let o = row + x * 4
                        dst[o] = average(s0, half, inverse)
                        dst[o + 1] = average(s1, half, inverse)
                        dst[o + 2] = average(s2, half, inverse)
                        dst[o + 3] = average(s3, half, inverse)
                        let add = row + min(last, x + r + 1) * 4
                        let sub = row + max(0, x - r) * 4
                        s0 = s0 + UInt64(src[add]) - UInt64(src[sub])
                        s1 = s1 + UInt64(src[add + 1]) - UInt64(src[sub + 1])
                        s2 = s2 + UInt64(src[add + 2]) - UInt64(src[sub + 2])
                        s3 = s3 + UInt64(src[add + 3]) - UInt64(src[sub + 3])
                    }
                }
            }
        }
    }

    /// Column sums kept for a whole row at once, so every loop walks memory in order.
    private static func verticalPass(
        from source: [UInt8], into target: inout [UInt8], width: Int, height: Int, radius r: Int
    ) {
        let size = 2 * r + 1
        let half = UInt64(size / 2)
        let inverse = ((UInt64(1) << 32) + UInt64(size) - 1) / UInt64(size)
        let rowBytes = width * 4
        let last = height - 1
        var sums = [UInt64](repeating: 0, count: rowBytes)
        source.withUnsafeBufferPointer { src in
            target.withUnsafeMutableBufferPointer { dst in
                sums.withUnsafeMutableBufferPointer { sum in
                    for k in -r...r {
                        let row = min(last, max(0, k)) * rowBytes
                        for i in 0..<rowBytes { sum[i] += UInt64(src[row + i]) }
                    }
                    for y in 0..<height {
                        let out = y * rowBytes
                        let add = min(last, y + r + 1) * rowBytes
                        let sub = max(0, y - r) * rowBytes
                        for i in 0..<rowBytes {
                            dst[out + i] = average(sum[i], half, inverse)
                            sum[i] = sum[i] + UInt64(src[add + i]) - UInt64(src[sub + i])
                        }
                    }
                }
            }
        }
    }

    private static func packed(_ width: Int, _ height: Int, _ bytes: [UInt8]) -> PixelBuffer {
        // The sizes come from a valid buffer, so this can't throw.
        try! PixelBuffer(width: width, height: height, bytesPerRow: width * 4, bytes: bytes)
    }
}
