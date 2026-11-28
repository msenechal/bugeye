import BugeyeCore

/// Portable pixel work for reading (OCR §5.2).
public enum PixelResample {
    /// Rows `range` of `buffer` (clamped to it), as a tightly packed copy. Throws `emptySize` when no row is left.
    public static func rows(_ buffer: PixelBuffer, _ range: Range<Int>) throws(PixelBuffer.Error) -> PixelBuffer {
        let range = range.clamped(to: 0..<buffer.height)
        let rowBytes = buffer.width * 4
        var bytes: [UInt8] = []
        bytes.reserveCapacity(rowBytes * range.count)
        for y in range {
            let start = y * buffer.bytesPerRow
            bytes.append(contentsOf: buffer.bytes[start..<(start + rowBytes)])
        }
        return try PixelBuffer(width: buffer.width, height: range.count, bytesPerRow: rowBytes, bytes: bytes)
    }

    /// `2W × 2H`: output pixel (x, y) samples the source at ((x + 0.5)/2 − 0.5, (y + 0.5)/2 − 0.5), clamped to the
    /// image, each channel interpolated bilinearly and rounded half up. The sample points fall on quarter pixels, so
    /// the weights are exact quarters and the arithmetic is done in sixteenths.
    public static func enlarged2x(_ buffer: PixelBuffer) -> PixelBuffer {
        let width = buffer.width * 2
        let height = buffer.height * 2
        let columns = taps(count: width, source: buffer.width)
        let rowTaps = taps(count: height, source: buffer.height)
        let source = buffer.bytes
        let stride = buffer.bytesPerRow
        var out = [UInt8](repeating: 0, count: width * height * 4)
        out.withUnsafeMutableBufferPointer { out in
            source.withUnsafeBufferPointer { src in
                var o = 0
                for row in rowTaps {
                    let r0 = row.first * stride
                    let r1 = row.second * stride
                    let wy0 = 4 - row.weight
                    let wy1 = row.weight
                    for column in columns {
                        let c0 = column.first * 4
                        let c1 = column.second * 4
                        let w00 = (4 - column.weight) * wy0
                        let w01 = column.weight * wy0
                        let w10 = (4 - column.weight) * wy1
                        let w11 = column.weight * wy1
                        for channel in 0..<4 {
                            let sum =
                                w00 * Int(src[r0 + c0 + channel]) + w01 * Int(src[r0 + c1 + channel])
                                + w10 * Int(src[r1 + c0 + channel]) + w11 * Int(src[r1 + c1 + channel])
                            out[o + channel] = UInt8((sum + 8) >> 4)
                        }
                        o += 4
                    }
                }
            }
        }
        // The sizes come from a valid buffer, so this never falls back.
        return (try? PixelBuffer(width: width, height: height, bytesPerRow: width * 4, bytes: out)) ?? buffer
    }

    /// For each output index: the two source indexes and the second one's weight in quarters.
    private static func taps(count: Int, source: Int) -> [(first: Int, second: Int, weight: Int)] {
        (0..<count).map { i in
            // 4 × ((i + 0.5)/2 − 0.5) = 2i − 1, clamped to 0…4(source − 1).
            let quarters = min(max(2 * i - 1, 0), 4 * (source - 1))
            let first = quarters / 4
            return (first, min(first + 1, source - 1), quarters - 4 * first)
        }
    }
}
