import BugeyeCore
import Synchronization

/// Displays and images given by the test.
public final class FakeScreenSource: ScreenSource {
    private let state: Mutex<(displays: [DisplayInfo], images: [DisplayID: PixelBuffer])>

    public init(displays: [DisplayInfo] = [], images: [DisplayID: PixelBuffer] = [:]) {
        state = Mutex((displays, images))
    }

    public func displays() async throws -> [DisplayInfo] {
        state.withLock { $0.displays }
    }

    public func capture(display: DisplayID, rect: Rect2D?) async throws -> PixelBuffer {
        guard let image = state.withLock({ $0.images[display] }) else { throw FakeFailure("no image for display") }
        return image
    }
}
