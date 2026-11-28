import BugeyeCore
import BugeyeTestSupport
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import MacAdapters
import Synchronization
import Testing
import TextCore

// The real pipeline: Vision and ImageIO through TextCore's reader (OCR §8). These live here, not in
// MacAdaptersTests, because only this test target sees TextCore (Package.swift is contract).

/// Text drawn with Core Text at test time (OCR §8: no committed binaries), with where each word landed.
struct PipelineText {
    var image: PixelBuffer
    /// Per drawn line: each whitespace-separated word's x-extent in pixels, and the line's ink top and bottom.
    var words: [[(text: String, minX: Double, maxX: Double)]]
    var lineTops: [Double]
    var lineBottoms: [Double]

    /// Black text on white; `lines` are (text, left x, top y) in top-left pixels.
    static func draw(
        _ lines: [(String, Double, Double)], width: Int, height: Int, fontSize: CGFloat = 32,
        fontName: String = "Menlo"
    ) throws -> DrawnText {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let ascent = CTFontGetAscent(font)
        var words: [[(String, Double, Double)]] = []
        var tops: [Double] = []
        var bottoms: [Double] = []
        for (text, x, top) in lines {
            let attributed = NSAttributedString(
                string: text,
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
                        red: 0, green: 0, blue: 0, alpha: 1),
                ])
            let line = CTLineCreateWithAttributedString(attributed)
            let baseline = Double(height) - top - Double(ascent)
            context.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(line, context)
            let ink = CTLineGetImageBounds(line, context)
            tops.append(Double(height) - (baseline + ink.maxY))
            bottoms.append(Double(height) - (baseline + ink.minY))
            var lineWords: [(String, Double, Double)] = []
            let utf16 = Array(text.utf16)
            var start: Int?
            for i in 0...utf16.count {
                let isSpace = i == utf16.count || utf16[i] == 0x20
                if isSpace, let s = start {
                    let x0 = CTLineGetOffsetForStringIndex(line, s, nil)
                    let x1 = CTLineGetOffsetForStringIndex(line, i, nil)
                    let word = String(utf16CodeUnits: Array(utf16[s..<i]), count: i - s)
                    lineWords.append((word, x + x0, x + x1))
                    start = nil
                } else if !isSpace, start == nil {
                    start = i
                }
            }
            words.append(lineWords)
        }
        let cgImage = try #require(context.makeImage())
        let image = try #require(PixelBufferImages.pixelBuffer(cgImage))
        return DrawnText(image: image, words: words, lineTops: tops, lineBottoms: bottoms)
    }
}

@Suite struct TextPipelineTests {
    @Test func aOneXImageThroughTheMapReaderLandsInOriginalPixels() async throws {
        let drawn = try PipelineText.draw([("Open Settings", 30, 30)], width: 400, height: 90, fontSize: 16)
        let map = try await TextMapReader(reader: VisionTextReader(), files: ImageIOFileReader())
            .read(.buffer(drawn.image), pixelsPerPoint: 1)
        let line = try #require(map.lines.first)
        #expect(line.text == "Open Settings")
        let first = try #require(drawn.words[0].first)
        let last = try #require(drawn.words[0].last)
        #expect(abs(line.box.minX - first.minX) <= 8)
        #expect(abs(line.box.maxX - last.maxX) <= 8)
        #expect(map.width == 400)
        #expect(map.height == 90)
    }

    @Test func aLineInsideTheStripOverlapIsReadOnce() async throws {
        // 8,200 px at 2×: strips 0..<4000 and 3800..<7800 share rows 3800..<4000.
        let drawn = try PipelineText.draw(
            [("Header line", 40, 100), ("Inside the overlap", 40, 3880), ("Middle line", 40, 6000)], width: 800,
            height: 8200)
        let map = try await TextMapReader(reader: VisionTextReader(), files: ImageIOFileReader())
            .read(.buffer(drawn.image), pixelsPerPoint: 2)
        #expect(map.lines.map(\.text) == ["Header line", "Inside the overlap", "Middle line"])
    }

    /// `BUGEYE_RECORD_OCR=<dir>` (off in CI): writes `<png>.json` fixtures for every PNG in `<dir>` (OCR §8), in the
    /// format `TextCoreTests` replays. A name containing `@1x` is read at 1 pixel per point, anything else at 2.
    @Test func recordFixtures() async throws {
        guard let folder = ProcessInfo.processInfo.environment["BUGEYE_RECORD_OCR"], !folder.isEmpty else { return }
        let directory = URL(fileURLWithPath: folder, isDirectory: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".png") }
        for name in names.sorted() {
            let url = directory.appendingPathComponent(name)
            let pixelsPerPoint = name.contains("@1x") ? 1.0 : 2.0
            let recorder = RecordingTextReader(VisionTextReader())
            let files = ImageIOFileReader()
            let info = try await files.info(of: url)
            _ = try await TextMapReader(reader: recorder, files: files, stripTimeout: .seconds(60))
                .read(.file(url), pixelsPerPoint: pixelsPerPoint)
            let fixture = RecordedOCR(
                pixelsPerPoint: pixelsPerPoint, width: info.width, height: info.height, strips: recorder.strips)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(fixture).write(to: directory.appendingPathComponent(name + ".json"))
        }
    }
}

/// The recorded-fixture format of `Tests/TextCoreTests/Fixtures` (OCR §8).
struct RecordedOCR: Codable {
    var pixelsPerPoint: Double
    var width: Int
    var height: Int
    var strips: [[OCRLine]]
}

/// Passes reads through and keeps each strip's lines, in order.
final class RecordingTextReader: TextReader, Sendable {
    private let base: any TextReader
    private let state = Mutex<[[OCRLine]]>([])
    init(_ base: any TextReader) { self.base = base }
    var strips: [[OCRLine]] { state.withLock { $0 } }

    func recognizeText(in image: PixelBuffer) async throws -> [OCRLine] {
        let lines = try await base.recognizeText(in: image)
        state.withLock { $0.append(lines) }
        return lines
    }
}

/// Writes `image` as a PNG.
func writeCGImage(_ image: CGImage, to url: URL) throws {
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
}
