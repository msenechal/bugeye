import BugeyeCore
import BugeyeTestSupport
import Foundation
import Testing

@testable import TextCore

/// A recorded OCR fixture (OCR §8): what the recogniser returned for each strip of one image.
struct RecordedFixture: Codable {
    var pixelsPerPoint: Double
    var width: Int
    var height: Int
    var strips: [[OCRLine]]
}

enum Fixtures {
    static var directory: URL {
        Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    }

    /// Where `BUGEYE_UPDATE_GOLDENS=1` writes goldens: the source folder, not the bundle copy (plan P14).
    static func sourceDirectory(file: String = #filePath) -> URL {
        URL(fileURLWithPath: file).deletingLastPathComponent().appendingPathComponent("Fixtures")
    }

    /// The names of every `<name>.json` that isn't a golden.
    static var names: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.filter { $0.hasSuffix(".json") && !$0.hasSuffix(".map.json") }
            .map { String($0.dropLast(".json".count)) }.sorted()
    }
}

@Suite struct RecordedFixtureTests {
    @Test func theHandMadeFixturesArePresent() {
        #expect(Set(["traceback", "label-fields", "overlap-8200", "french"]).isSubset(of: Set(Fixtures.names)))
    }

    @Test(arguments: Fixtures.names)
    func aFixtureReplaysToItsGoldens(name: String) async throws {
        let data = try Data(contentsOf: Fixtures.directory.appendingPathComponent("\(name).json"))
        let fixture = try JSONDecoder().decode(RecordedFixture.self, from: data)
        let text = FakeTextReader(steps: fixture.strips.map { .lines($0) })
        let image = try PixelBuffer(
            width: fixture.width, height: fixture.height, fill: RGBA8(red: 255, green: 255, blue: 255))
        let map = try await TextMapReader(reader: text, files: FakeImageFileReader())
            .read(.buffer(image), pixelsPerPoint: fixture.pixelsPerPoint)
        #expect(text.calls.count == fixture.strips.count)
        let layout = TextLayout.lines(map) ?? ""

        if ProcessInfo.processInfo.environment["BUGEYE_UPDATE_GOLDENS"] == "1" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let source = Fixtures.sourceDirectory()
            try (encoder.encode(map) + Data("\n".utf8)).write(to: source.appendingPathComponent("\(name).map.json"))
            try Data((layout + "\n").utf8).write(to: source.appendingPathComponent("\(name).txt"))
            return
        }
        let golden = try JSONDecoder().decode(
            TextMap.self, from: Data(contentsOf: Fixtures.directory.appendingPathComponent("\(name).map.json")))
        #expect(map == golden)
        let goldenText = try String(
            contentsOf: Fixtures.directory.appendingPathComponent("\(name).txt"), encoding: .utf8)
        #expect(layout + "\n" == goldenText)
    }
}
