import BugeyeCore
import BugeyeTestSupport
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing

@testable import MacAdapters

/// Text drawn with Core Text at test time (OCR §8: no committed binaries), with where each word landed.
struct DrawnText {
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

@Suite struct VisionTextReaderTests {
    @Test func codeComesBackExactly() async throws {
        let drawn = try DrawnText.draw([("let x = foo(bar)", 40, 40)], width: 800, height: 120)
        let lines = try await VisionTextReader().recognizeText(in: drawn.image)
        #expect(lines.map(\.text) == ["let x = foo(bar)"])
    }

    @Test func frenchKeepsItsAccents() async throws {
        let drawn = try DrawnText.draw(
            [("Déjà vu, garçon. Où est la bibliothèque ?", 40, 40)], width: 1400, height: 120, fontName: "Helvetica")
        let lines = try await VisionTextReader().recognizeText(in: drawn.image)
        #expect(lines.map(\.text) == ["Déjà vu, garçon. Où est la bibliothèque ?"])
    }

    @Test func wordBoxesLandOnTheGlyphs() async throws {
        let drawn = try DrawnText.draw([("Remember me Send reports", 60, 50)], width: 1000, height: 140)
        let lines = try await VisionTextReader().recognizeText(in: drawn.image)
        let line = try #require(lines.first)
        #expect(line.text == "Remember me Send reports")
        let expected = drawn.words[0]
        #expect(line.words.count == expected.count)
        let characters = Array(line.text)
        for (word, truth) in zip(line.words, expected) {
            #expect(String(characters[word.range]) == truth.text)
            #expect(abs(word.bounds.minX - truth.minX) <= 4, "\(truth.text) left edge")
            #expect(abs(word.bounds.maxX - truth.maxX) <= 4, "\(truth.text) right edge")
            // The word's box covers the line's ink vertically (glyph heights differ per word, so not ±4 px).
            #expect(word.bounds.minY <= drawn.lineTops[0] + 4)
            #expect(word.bounds.maxY >= drawn.lineBottoms[0] - 4)
        }
    }
}

@Suite struct VisionLineTests {
    @Test func wordsAreSplitOnAnyWhitespaceIntoCharacterRangesAndUnboxedWordsAreLeftOut() {
        let text = "Où\t est  là"
        let line = VisionTextReader.line(
            text: text, bounds: CGRect(x: 0, y: 0.5, width: 1, height: 0.5), confidence: 0.75, width: 200,
            height: 100
        ) { range in
            text[range] == "est" ? nil : CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        }
        #expect(line.text == text)
        #expect(line.bounds == Rect2D(x: 0, y: 0, width: 200, height: 50))
        #expect(line.confidence == 0.75)
        #expect(line.words.map(\.range) == [0..<2, 9..<11])
        #expect(line.words.map(\.bounds) == Array(repeating: Rect2D(x: 50, y: 25, width: 100, height: 25), count: 2))
    }
}
