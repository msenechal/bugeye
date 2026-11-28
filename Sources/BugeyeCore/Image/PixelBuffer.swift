/// One RGBA8 pixel.
public struct RGBA8: Hashable, Codable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

/// An image as plain bytes: the only way images cross the core boundary (`design/13` §2).
/// Rows are top to bottom; each row is `bytesPerRow` long and starts with `width` RGBA8 pixels.
/// RGBA8 with premultiplied alpha, sRGB unless the producer documents otherwise. There is no colour-space field
/// (Capture C7, OCR T8).
public struct PixelBuffer: Hashable, Sendable {
    public enum Error: Swift.Error, Equatable {
        case emptySize(width: Int, height: Int)
        case rowTooShort(bytesPerRow: Int, minimum: Int)
        case wrongByteCount(actual: Int, expected: Int)
    }

    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let bytes: [UInt8]

    public init(width: Int, height: Int, bytesPerRow: Int, bytes: [UInt8]) throws(PixelBuffer.Error) {
        guard width > 0, height > 0 else { throw .emptySize(width: width, height: height) }
        let (minimumRow, rowOverflow) = width.multipliedReportingOverflow(by: 4)
        guard !rowOverflow, bytesPerRow >= minimumRow else {
            throw .rowTooShort(bytesPerRow: bytesPerRow, minimum: minimumRow)
        }
        let (expected, overflow) = bytesPerRow.multipliedReportingOverflow(by: height)
        guard !overflow, bytes.count == expected else {
            throw .wrongByteCount(actual: bytes.count, expected: overflow ? Int.max : expected)
        }
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.bytes = bytes
    }

    /// A tightly packed buffer filled with one colour.
    public init(width: Int, height: Int, fill: RGBA8) throws(PixelBuffer.Error) {
        guard width > 0, height > 0 else { throw .emptySize(width: width, height: height) }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(width * height * 4)
        for _ in 0..<(width * height) {
            bytes += [fill.red, fill.green, fill.blue, fill.alpha]
        }
        try self.init(width: width, height: height, bytesPerRow: width * 4, bytes: bytes)
    }

    /// The pixel at (x, y), or nil outside the image. Row padding is never read.
    public func pixel(x: Int, y: Int) -> RGBA8? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let i = y * bytesPerRow + x * 4
        return RGBA8(red: bytes[i], green: bytes[i + 1], blue: bytes[i + 2], alpha: bytes[i + 3])
    }
}
