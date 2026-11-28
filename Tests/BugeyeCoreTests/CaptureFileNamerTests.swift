import BugeyeCore
import Foundation
import Testing

@Suite struct CaptureFileNamerTests {
    let paris = TimeZone(identifier: "Europe/Paris")!
    /// 27 Nov 2026, 14:03:12 in Paris (UTC+1).
    let date = Date(timeIntervalSince1970: 1_795_784_592)

    @Test func namesUseThePrefixDateAndExtension() {
        #expect(
            CaptureFileNamer.name(kind: .screenshot, date: date, timeZone: paris)
                == "Screenshot 2026-11-27 at 14.03.12.png")
        #expect(
            CaptureFileNamer.name(kind: .recording, date: date, timeZone: paris)
                == "Recording 2026-11-27 at 14.03.12.mp4")
        #expect(
            CaptureFileNamer.name(kind: .gif, date: date, timeZone: paris) == "Recording 2026-11-27 at 14.03.12.gif")
        #expect(
            CaptureFileNamer.name(kind: .collection, date: date, timeZone: paris)
                == "Collection 2026-11-27 at 14.03.12.bugeye")
        #expect(
            CaptureFileNamer.name(kind: .recording, date: date, fileExtension: "mov", timeZone: paris)
                == "Recording 2026-11-27 at 14.03.12.mov")
    }

    @Test func namesUseTheGivenTimeZone() {
        #expect(
            CaptureFileNamer.name(kind: .screenshot, date: date, timeZone: TimeZone(identifier: "UTC")!)
                == "Screenshot 2026-11-27 at 13.03.12.png")
    }

    @Test func candidatesSuffixBeforeTheLastExtension() {
        #expect(CaptureFileNamer.candidate("a.png", attempt: 1) == "a.png")
        #expect(CaptureFileNamer.candidate("a.png", attempt: 2) == "a (2).png")
        #expect(CaptureFileNamer.candidate("a.b.png", attempt: 3) == "a.b (3).png")
        #expect(CaptureFileNamer.candidate("README", attempt: 2) == "README (2)")
        #expect(CaptureFileNamer.candidate(".hidden", attempt: 2) == ".hidden (2)")
        #expect(
            CaptureFileNamer.candidate("Screenshot 2026-11-27 at 14.03.12.png", attempt: 999)
                == "Screenshot 2026-11-27 at 14.03.12 (999).png")
    }

    @Test func foldersSitInTheHomesLibrary() {
        #expect(CaptureFolders.bundleID == "dev.msenechal.bugeye")
        #expect(
            CaptureFolders.temp(home: "/Users/m").path == "/Users/m/Library/Caches/dev.msenechal.bugeye/Captures")
        #expect(
            CaptureFolders.recordingsInProgress(home: "/Users/m/").path
                == "/Users/m/Library/Caches/dev.msenechal.bugeye/Recordings")
        #expect(
            CaptureFolders.applicationSupport(home: "/Users/m").path
                == "/Users/m/Library/Application Support/dev.msenechal.bugeye")
        #expect(CaptureFolders.temp(home: "/Users/m").hasDirectoryPath)
    }

    @Test func foldersAreNotCreated() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("bugeye-home-\(UUID())").path
        _ = CaptureFolders.temp(home: home)
        #expect(!FileManager.default.fileExists(atPath: home))
    }
}
