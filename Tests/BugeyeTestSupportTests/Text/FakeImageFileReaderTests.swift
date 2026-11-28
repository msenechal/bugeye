import BugeyeCore
import BugeyeTestSupport
import Foundation
import Testing

@Suite struct FakeImageFileReaderTests {
    let url = URL(fileURLWithPath: "/captures/a.png")
    let print1 = FileFingerprint(size: 1, modified: Date(timeIntervalSince1970: 1))
    let print2 = FileFingerprint(size: 2, modified: Date(timeIntervalSince1970: 2))

    /// A 2-wide image whose row y is filled with grey y.
    func striped(height: Int) throws -> PixelBuffer {
        var bytes: [UInt8] = []
        for y in 0..<height { for _ in 0..<2 { bytes += [UInt8(y), UInt8(y), UInt8(y), 255] } }
        return try PixelBuffer(width: 2, height: height, bytesPerRow: 8, bytes: bytes)
    }

    @Test func infoAndPixelsOfAKnownFile() async throws {
        let files = FakeImageFileReader()
        files.set(url, image: try striped(height: 5), fingerprint: print1)
        #expect(try await files.info(of: url) == ImageFileInfo(width: 2, height: 5, fingerprint: print1))
        #expect(try await files.pixels(of: url, rows: nil) == (try striped(height: 5)))
    }

    @Test func aRowRangeIsCropped() async throws {
        let files = FakeImageFileReader()
        files.set(url, image: try striped(height: 5), fingerprint: print1)
        let rows = try await files.pixels(of: url, rows: 2..<4)
        #expect(rows.height == 2)
        #expect(rows.pixel(x: 0, y: 0)?.red == 2)
        #expect(rows.pixel(x: 1, y: 1)?.red == 3)
    }

    @Test func anUnknownFileIsMissing() async {
        let files = FakeImageFileReader()
        await #expect(throws: ImageFileError.missing(url)) { try await files.info(of: url) }
        await #expect(throws: ImageFileError.missing(url)) { try await files.pixels(of: url, rows: nil) }
    }

    @Test func anInjectedFailureIsThrown() async throws {
        let files = FakeImageFileReader()
        files.set(url, image: try striped(height: 5), fingerprint: print1)
        files.fail(url, with: ImageFileError.unreadable(url))
        await #expect(throws: ImageFileError.unreadable(url)) { try await files.info(of: url) }
        await #expect(throws: ImageFileError.unreadable(url)) { try await files.pixels(of: url, rows: nil) }
    }

    @Test func filesChangeWhileATestRuns() async throws {
        let files = FakeImageFileReader()
        files.set(url, image: try striped(height: 5), fingerprint: print1)
        files.set(url, image: try striped(height: 6), fingerprint: print2)
        #expect(try await files.info(of: url) == ImageFileInfo(width: 2, height: 6, fingerprint: print2))
        files.remove(url)
        await #expect(throws: ImageFileError.missing(url)) { try await files.info(of: url) }
    }

    @Test func callsAndTheHookSeeEveryPixelsRequest() async throws {
        let files = FakeImageFileReader()
        let other = URL(fileURLWithPath: "/captures/b.png")
        files.set(url, image: try striped(height: 5), fingerprint: print1)
        let replacement = try striped(height: 7)
        let print2 = self.print2
        // The hook runs before the pixels are taken: here it edits the file under the read.
        files.beforePixels = { files, url, _ in files.set(url, image: replacement, fingerprint: print2) }
        _ = try await files.pixels(of: url, rows: 0..<2)
        _ = try? await files.pixels(of: other, rows: nil)
        #expect(files.calls.map(\.url) == [url, other])
        #expect(files.calls.map(\.rows) == [0..<2, nil])
        #expect(try await files.info(of: url).fingerprint == print2)
    }
}
