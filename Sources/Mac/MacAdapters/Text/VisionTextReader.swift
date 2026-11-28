import BugeyeCore
import CoreGraphics
import Foundation
import Vision

/// OCR with Vision (OCR §7, T5): `RecognizeTextRequest`, `.accurate`, no language correction (it turns
/// `foo(bar)` into `foo (bar)`), automatic language detection, no language list. Reads the image exactly as given.
/// Runs off the main actor.
public struct VisionTextReader: TextReader {
    public struct ImageError: Error, Hashable {}

    public init() {}

    @concurrent public func recognizeText(in image: PixelBuffer) async throws -> [OCRLine] {
        try Task.checkCancellation()
        guard let cgImage = PixelBufferImages.cgImage(image) else { throw ImageError() }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        let observations = try await request.perform(on: cgImage)
        try Task.checkCancellation()
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return Self.line(
                text: candidate.string, bounds: observation.boundingBox.cgRect,
                confidence: Double(candidate.confidence),
                width: image.width, height: image.height
            ) { range in candidate.boundingBox(for: range)?.boundingBox.cgRect }
        }
    }

    /// One `OCRLine`: the line box in pixels, the text split on whitespace into `Character` ranges, each word boxed
    /// by `wordBox` (normalised, bottom-left origin) and left out when it has none.
    static func line(
        text: String, bounds: CGRect, confidence: Double, width: Int, height: Int,
        wordBox: (Range<String.Index>) -> CGRect?
    ) -> OCRLine {
        var words: [OCRWord] = []
        var offset = 0
        var index = text.startIndex
        while index < text.endIndex {
            if text[index].isWhitespace {
                index = text.index(after: index)
                offset += 1
                continue
            }
            let start = index
            let startOffset = offset
            while index < text.endIndex, !text[index].isWhitespace {
                index = text.index(after: index)
                offset += 1
            }
            if let box = wordBox(start..<index) {
                words.append(
                    OCRWord(
                        range: startOffset..<offset,
                        bounds: NormalizedRect2D.pixelRect(rect(box), imageWidth: width, imageHeight: height)))
            }
        }
        return OCRLine(
            text: text, bounds: NormalizedRect2D.pixelRect(rect(bounds), imageWidth: width, imageHeight: height),
            confidence: confidence, words: words)
    }

    private static func rect(_ r: CGRect) -> Rect2D {
        Rect2D(x: r.origin.x, y: r.origin.y, width: r.size.width, height: r.size.height)
    }
}
