import RecordingCore
import Testing

@Suite struct MediaTimeTests {
    @Test(arguments: [
        (0.0, "00:00"), (7.9, "00:07"), (59.99, "00:59"), (754, "12:34"), (3599.9, "59:59"),
        (3600, "1:00:00"), (3723, "1:02:03"), (36000, "10:00:00"), (-3, "00:00"), (.nan, "00:00"),
        (.infinity, "00:00"),
    ])
    func formats(seconds: Double, text: String) {
        #expect(MediaTime.text(seconds: seconds) == text)
    }
}
