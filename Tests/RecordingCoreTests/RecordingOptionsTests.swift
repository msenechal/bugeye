import BugeyeCore
import BugeyeTestSupport
import Foundation
import RecordingCore
import Testing

@Suite struct RecordingSettingsTests {
    @Test func defaults() {
        let options = RecordingSettings.load(from: InMemorySettingsStore())
        #expect(
            options
                == RecordingOptions(
                    fps: 30, quality: .standard, mic: false, systemAudio: false, clicks: false, keys: false,
                    camera: false, micDevice: "", cameraDevice: "", bubbleSize: .medium, codec: .h264,
                    showAllKeys: false, timeline: true))
        #expect(RecordingSettings.lastArea(in: InMemorySettingsStore()) == nil)
    }

    @Test func storedValuesAreRead() {
        let store = InMemorySettingsStore([
            "recording.fps": .int(60), "recording.quality": .string("high"), "recording.mic": .bool(true),
            "recording.systemAudio": .bool(true), "recording.clicks": .bool(true), "recording.keys": .bool(true),
            "recording.camera": .bool(true), "recording.micDevice": .string("mic-1"),
            "recording.cameraDevice": .string("cam-1"), "recording.bubbleSize": .string("large"),
            "recording.codec": .string("hevc"), "recording.showAllKeys": .bool(true),
            "recording.timeline": .bool(false),
        ])
        #expect(
            RecordingSettings.load(from: store)
                == RecordingOptions(
                    fps: 60, quality: .high, mic: true, systemAudio: true, clicks: true, keys: true, camera: true,
                    micDevice: "mic-1", cameraDevice: "cam-1", bubbleSize: .large, codec: .hevc, showAllKeys: true,
                    timeline: false))
    }

    @Test func invalidValuesFallBackToDefaults() {
        let store = InMemorySettingsStore([
            "recording.fps": .int(24), "recording.quality": .string("ultra"), "recording.mic": .string("yes"),
            "recording.bubbleSize": .int(3), "recording.codec": .string("av1"), "recording.micDevice": .bool(true),
            "recording.timeline": .int(0),
        ])
        let options = RecordingSettings.load(from: store)
        #expect(options == RecordingSettings.load(from: InMemorySettingsStore()))
    }

    @Test func aChangeWritesOnlyItsKey() {
        let store = InMemorySettingsStore()
        let changes: [(RecordingOptionChange, String, SettingValue)] = [
            (.fps(60), "recording.fps", .int(60)), (.quality(.high), "recording.quality", .string("high")),
            (.mic(true), "recording.mic", .bool(true)), (.systemAudio(true), "recording.systemAudio", .bool(true)),
            (.clicks(true), "recording.clicks", .bool(true)), (.keys(true), "recording.keys", .bool(true)),
            (.camera(true), "recording.camera", .bool(true)), (.micDevice("m"), "recording.micDevice", .string("m")),
            (.cameraDevice("c"), "recording.cameraDevice", .string("c")),
            (.bubbleSize(.small), "recording.bubbleSize", .string("small")),
            (.codec(.hevc), "recording.codec", .string("hevc")),
            (.showAllKeys(true), "recording.showAllKeys", .bool(true)),
        ]
        for (change, key, value) in changes {
            #expect(change.setting.key == key)
            #expect(change.setting.value == value)
            RecordingSettings.write(change, to: store)
        }
        #expect(store.all.count == changes.count)
        var options = RecordingOptions()
        for (change, _, _) in changes { options = options.applying(change) }
        #expect(RecordingSettings.load(from: store) == options)
    }

    @Test func theLastAreaRoundTripsAsJSON() {
        let store = InMemorySettingsStore()
        let area = StoredArea(
            display: DisplayID(7), rect: Rect2D(x: 10, y: 20, width: 300, height: 200),
            displaySize: Size2D(width: 1512, height: 982))
        RecordingSettings.storeLastArea(area, in: store)
        #expect(RecordingSettings.lastArea(in: store) == area)
        store.setValue(.string("{nope"), forKey: "recording.lastArea")
        #expect(RecordingSettings.lastArea(in: store) == nil)
    }

    @Test func bubbleSizesCycleAndHaveTheirDiameters() {
        #expect(BubbleSize.small.diameter == 120)
        #expect(BubbleSize.medium.diameter == 180)
        #expect(BubbleSize.large.diameter == 240)
        #expect(BubbleSize.small.next == .medium)
        #expect(BubbleSize.medium.next == .large)
        #expect(BubbleSize.large.next == .small)
    }
}

@Suite struct EffectiveOptionsTests {
    private let everything = RecordingOptions(
        fps: 60, quality: .high, mic: true, systemAudio: true, clicks: true, keys: true, camera: true,
        micDevice: "mic-2", cameraDevice: "cam-2", bubbleSize: .large, codec: .hevc, showAllKeys: true,
        timeline: true)
    private let allGranted = RecordingPermissions(microphone: .granted, camera: .granted, accessibility: .granted)
    private let devices = CaptureDeviceList(microphones: ["mic-1", "mic-2"], cameras: ["cam-1", "cam-2"])

    @Test func grantedAndPresentKeepsEverything() {
        #expect(effectiveOptions(everything, permissions: allGranted, devices: devices) == everything)
    }

    @Test(arguments: [PermissionState.denied, .notDetermined])
    func micOffWithoutPermission(state: PermissionState) {
        var permissions = allGranted
        permissions.microphone = state
        let effective = effectiveOptions(everything, permissions: permissions, devices: devices)
        #expect(!effective.mic)
        #expect(effective.systemAudio)
    }

    @Test(arguments: [PermissionState.denied, .notDetermined])
    func keysOffWithoutAccessibility(state: PermissionState) {
        var permissions = allGranted
        permissions.accessibility = state
        #expect(!effectiveOptions(everything, permissions: permissions, devices: devices).keys)
    }

    @Test func camOffWithoutPermissionOrCamera() {
        var permissions = allGranted
        permissions.camera = .denied
        #expect(!effectiveOptions(everything, permissions: permissions, devices: devices).camera)
        let none = CaptureDeviceList(microphones: ["mic-1"], cameras: [])
        #expect(!effectiveOptions(everything, permissions: allGranted, devices: none).camera)
    }

    @Test func unknownDevicesFallBackToTheDefault() {
        let other = CaptureDeviceList(microphones: ["mic-1"], cameras: ["cam-1"])
        let effective = effectiveOptions(everything, permissions: allGranted, devices: other)
        #expect(effective.micDevice == "")
        #expect(effective.cameraDevice == "")
        #expect(effective.mic)
        #expect(effective.camera)
    }
}

@Suite struct DiskGuardTests {
    @Test func thresholds() {
        #expect(DiskGuard.canStart(freeBytes: 1_000_000_000))
        #expect(!DiskGuard.canStart(freeBytes: 999_999_999))
        #expect(DiskGuard.mustStop(freeBytes: 299_999_999))
        #expect(!DiskGuard.mustStop(freeBytes: 300_000_000))
        #expect(DiskGuard.canConvert(movieBytes: 2_000_000_000, freeBytes: 2_050_000_000))
        #expect(!DiskGuard.canConvert(movieBytes: 2_000_000_000, freeBytes: 2_049_999_999))
    }

    @Test func theConversionDeadlineIs60SecondsPlusHalfTheDuration() {
        #expect(DiskGuard.conversionDeadline(duration: 0) == 60)
        #expect(DiskGuard.conversionDeadline(duration: 600) == 360)
        #expect(DiskGuard.conversionDeadline(duration: -5) == 60)
    }
}
