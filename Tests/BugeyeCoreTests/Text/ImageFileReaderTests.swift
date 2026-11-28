import BugeyeCore
import Foundation
import Testing

@Suite struct ImageFileReaderTests {
    // `Date` near 1.8e9 s resolves about 240 ns, so half a microsecond is the finest step this can check.
    @Test func fingerprintsCompareSizeAndDateBelowAMicrosecond() {
        let date = Date(timeIntervalSince1970: 1_800_000_000.123456789)
        #expect(FileFingerprint(size: 10, modified: date) == FileFingerprint(size: 10, modified: date))
        #expect(FileFingerprint(size: 10, modified: date) != FileFingerprint(size: 11, modified: date))
        #expect(
            FileFingerprint(size: 10, modified: date)
                != FileFingerprint(size: 10, modified: date.addingTimeInterval(0.000_000_5)))
    }

    @Test func aFingerprintRoundTripsThroughJSON() throws {
        let print = FileFingerprint(size: 42, modified: Date(timeIntervalSince1970: 1_800_000_000.5))
        #expect(try JSONDecoder().decode(FileFingerprint.self, from: JSONEncoder().encode(print)) == print)
    }

    @Test func infoHoldsSizeAndFingerprint() {
        let print = FileFingerprint(size: 1, modified: Date(timeIntervalSince1970: 0))
        let info = ImageFileInfo(width: 3, height: 4, fingerprint: print)
        #expect(info.width == 3)
        #expect(info.height == 4)
        #expect(info.fingerprint == print)
    }

    @Test func errorsNameTheirURL() {
        let url = URL(fileURLWithPath: "/tmp/a.png")
        #expect(ImageFileError.missing(url) != ImageFileError.unreadable(url))
    }
}
