import BugeyeCore
import Foundation
import Testing

@testable import TextCore

@Suite struct TextLogLineTests {
    let id = CaptureID(UUID(uuidString: "0A1B2C3D-0000-4000-8000-000000000001")!)

    @Test func theReadLine() {
        let line = TextLogLine.read(
            id: id, width: 3024, height: 1964, pixelsPerPoint: 2, strips: 1, lines: 42, milliseconds: 812,
            priority: .background)
        #expect(
            line.description
                == "read 0a1b2c3d-0000-4000-8000-000000000001 3024×1964 @2x: 1 strips, 42 lines in 812 ms (background)")
        let demand = TextLogLine.read(
            id: id, width: 10, height: 20, pixelsPerPoint: 1.5, strips: 3, lines: 0, milliseconds: 0, priority: .demand)
        #expect(
            demand.description
                == "read 0a1b2c3d-0000-4000-8000-000000000001 10×20 @1.5x: 3 strips, 0 lines in 0 ms (demand)")
    }

    @Test func theOtherLines() {
        #expect(
            TextLogLine.failed(id: id, error: .timedOut(strip: 1)).description
                == "failed 0a1b2c3d-0000-4000-8000-000000000001: timed out on strip 1")
        #expect(
            TextLogLine.failed(id: id, error: .unreadable(URL(fileURLWithPath: "/a/secret.png"))).description
                == "failed 0a1b2c3d-0000-4000-8000-000000000001: unreadable")
        #expect(
            TextLogLine.cancelled(id: id, reason: .deleted).description
                == "cancelled 0a1b2c3d-0000-4000-8000-000000000001: deleted")
        #expect(
            TextLogLine.cancelled(id: id, reason: .edited).description
                == "cancelled 0a1b2c3d-0000-4000-8000-000000000001: edited")
        #expect(
            TextLogLine.cancelled(id: id, reason: .moved).description
                == "cancelled 0a1b2c3d-0000-4000-8000-000000000001: moved")
        #expect(
            TextLogLine.dropped(id: id, reason: .gone).description
                == "dropped 0a1b2c3d-0000-4000-8000-000000000001: gone")
        #expect(
            TextLogLine.dropped(id: id, reason: .changed).description
                == "dropped 0a1b2c3d-0000-4000-8000-000000000001: changed")
    }
}
