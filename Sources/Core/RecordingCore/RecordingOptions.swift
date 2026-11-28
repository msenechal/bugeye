import BugeyeCore
import Foundation

public enum VideoCodec: String, Hashable, Sendable, CaseIterable { case h264, hevc }

public enum RecordingQuality: String, Hashable, Sendable, CaseIterable { case standard, high }

public enum BubbleSize: String, Hashable, Sendable, CaseIterable {
    case small, medium, large

    /// Points: 120, 180, 240.
    public var diameter: Double {
        switch self {
        case .small: 120
        case .medium: 180
        case .large: 240
        }
    }

    /// Double-click cycles Small → Medium → Large → Small.
    public var next: BubbleSize {
        switch self {
        case .small: .medium
        case .medium: .large
        case .large: .small
        }
    }
}

/// What the user chose (spec §4). What is recorded is `effectiveOptions(...)` of this.
public struct RecordingOptions: Hashable, Sendable {
    /// 30 or 60.
    public var fps: Int
    public var quality: RecordingQuality
    public var mic: Bool
    public var systemAudio: Bool
    public var clicks: Bool
    public var keys: Bool
    public var camera: Bool
    /// A device unique id; empty for the default device.
    public var micDevice: String
    public var cameraDevice: String
    public var bubbleSize: BubbleSize
    public var codec: VideoCodec
    public var showAllKeys: Bool
    /// The hidden `recording.timeline` key (V13).
    public var timeline: Bool

    public init(
        fps: Int = 30, quality: RecordingQuality = .standard, mic: Bool = false, systemAudio: Bool = false,
        clicks: Bool = false, keys: Bool = false, camera: Bool = false, micDevice: String = "",
        cameraDevice: String = "", bubbleSize: BubbleSize = .medium, codec: VideoCodec = .h264,
        showAllKeys: Bool = false, timeline: Bool = true
    ) {
        self.fps = fps
        self.quality = quality
        self.mic = mic
        self.systemAudio = systemAudio
        self.clicks = clicks
        self.keys = keys
        self.camera = camera
        self.micDevice = micDevice
        self.cameraDevice = cameraDevice
        self.bubbleSize = bubbleSize
        self.codec = codec
        self.showAllKeys = showAllKeys
        self.timeline = timeline
    }

    public func applying(_ change: RecordingOptionChange) -> RecordingOptions {
        var options = self
        switch change {
        case .fps(let value): options.fps = value
        case .quality(let value): options.quality = value
        case .mic(let value): options.mic = value
        case .systemAudio(let value): options.systemAudio = value
        case .clicks(let value): options.clicks = value
        case .keys(let value): options.keys = value
        case .camera(let value): options.camera = value
        case .micDevice(let value): options.micDevice = value
        case .cameraDevice(let value): options.cameraDevice = value
        case .bubbleSize(let value): options.bubbleSize = value
        case .codec(let value): options.codec = value
        case .showAllKeys(let value): options.showAllKeys = value
        }
        return options
    }
}

/// One control changed in the bar, its ⚙ menu, the bubble or the Recording pane.
public enum RecordingOptionChange: Hashable, Sendable {
    case fps(Int)
    case quality(RecordingQuality)
    case mic(Bool)
    case systemAudio(Bool)
    case clicks(Bool)
    case keys(Bool)
    case camera(Bool)
    case micDevice(String)
    case cameraDevice(String)
    case bubbleSize(BubbleSize)
    case codec(VideoCodec)
    case showAllKeys(Bool)

    /// The one settings key this change writes.
    public var setting: (key: String, value: SettingValue) {
        typealias K = RecordingSettings.Key
        switch self {
        case .fps(let value): return (K.fps, .int(value))
        case .quality(let value): return (K.quality, .string(value.rawValue))
        case .mic(let value): return (K.mic, .bool(value))
        case .systemAudio(let value): return (K.systemAudio, .bool(value))
        case .clicks(let value): return (K.clicks, .bool(value))
        case .keys(let value): return (K.keys, .bool(value))
        case .camera(let value): return (K.camera, .bool(value))
        case .micDevice(let value): return (K.micDevice, .string(value))
        case .cameraDevice(let value): return (K.cameraDevice, .string(value))
        case .bubbleSize(let value): return (K.bubbleSize, .string(value.rawValue))
        case .codec(let value): return (K.codec, .string(value.rawValue))
        case .showAllKeys(let value): return (K.showAllKeys, .bool(value))
        }
    }
}

/// The `recording.*` keys (spec §4). Read fresh when the bar opens; each change writes only its key.
public enum RecordingSettings {
    public enum Key {
        public static let fps = "recording.fps"
        public static let quality = "recording.quality"
        public static let mic = "recording.mic"
        public static let systemAudio = "recording.systemAudio"
        public static let clicks = "recording.clicks"
        public static let keys = "recording.keys"
        public static let camera = "recording.camera"
        public static let micDevice = "recording.micDevice"
        public static let cameraDevice = "recording.cameraDevice"
        public static let bubbleSize = "recording.bubbleSize"
        public static let codec = "recording.codec"
        public static let showAllKeys = "recording.showAllKeys"
        public static let lastArea = "recording.lastArea"
        public static let hotkeyToggle = "recording.hotkey.toggle"
        /// Hidden (V13).
        public static let timeline = "recording.timeline"
        /// Reserved for Wave 2 (V9); never read or written in Wave 1.
        public static let reserved = ["recording.format", "recording.gifWidth", "recording.gifFps"]
    }

    /// Invalid stored values fall back to the defaults.
    public static func load(from store: any SettingsStore) -> RecordingOptions {
        let defaults = RecordingOptions()
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            if case .bool(let value)? = store.value(forKey: key) { return value }
            return fallback
        }
        func string(_ key: String) -> String? {
            if case .string(let value)? = store.value(forKey: key) { return value }
            return nil
        }
        var fps = defaults.fps
        if case .int(let value)? = store.value(forKey: Key.fps), [30, 60].contains(value) { fps = value }
        return RecordingOptions(
            fps: fps,
            quality: string(Key.quality).flatMap(RecordingQuality.init(rawValue:)) ?? defaults.quality,
            mic: bool(Key.mic, defaults.mic),
            systemAudio: bool(Key.systemAudio, defaults.systemAudio),
            clicks: bool(Key.clicks, defaults.clicks),
            keys: bool(Key.keys, defaults.keys),
            camera: bool(Key.camera, defaults.camera),
            micDevice: string(Key.micDevice) ?? defaults.micDevice,
            cameraDevice: string(Key.cameraDevice) ?? defaults.cameraDevice,
            bubbleSize: string(Key.bubbleSize).flatMap(BubbleSize.init(rawValue:)) ?? defaults.bubbleSize,
            codec: string(Key.codec).flatMap(VideoCodec.init(rawValue:)) ?? defaults.codec,
            showAllKeys: bool(Key.showAllKeys, defaults.showAllKeys),
            timeline: bool(Key.timeline, defaults.timeline))
    }

    public static func write(_ change: RecordingOptionChange, to store: any SettingsStore) {
        let setting = change.setting
        store.setValue(setting.value, forKey: setting.key)
    }

    /// `recording.lastArea`, a `StoredArea` as JSON; nil when missing or unreadable.
    public static func lastArea(in store: any SettingsStore) -> StoredArea? {
        guard case .string(let json)? = store.value(forKey: Key.lastArea) else { return nil }
        return try? JSONDecoder().decode(StoredArea.self, from: Data(json.utf8))
    }

    public static func storeLastArea(_ area: StoredArea, in store: any SettingsStore) {
        guard let data = try? JSONEncoder().encode(area) else { return }
        store.setValue(.string(String(decoding: data, as: UTF8.self)), forKey: Key.lastArea)
    }
}

/// The three permissions the bar depends on.
public struct RecordingPermissions: Hashable, Sendable {
    public var microphone: PermissionState
    public var camera: PermissionState
    public var accessibility: PermissionState

    public init(
        microphone: PermissionState = .notDetermined, camera: PermissionState = .notDetermined,
        accessibility: PermissionState = .notDetermined
    ) {
        self.microphone = microphone
        self.camera = camera
        self.accessibility = accessibility
    }

    public subscript(_ permission: MediaPermission) -> PermissionState {
        get {
            switch permission {
            case .microphone: microphone
            case .camera: camera
            case .accessibility: accessibility
            }
        }
        set {
            switch permission {
            case .microphone: microphone = newValue
            case .camera: camera = newValue
            case .accessibility: accessibility = newValue
            }
        }
    }
}

/// The capture devices present, by unique id.
public struct CaptureDeviceList: Hashable, Sendable {
    public var microphones: [String]
    public var cameras: [String]

    public init(microphones: [String] = [], cameras: [String] = []) {
        self.microphones = microphones
        self.cameras = cameras
    }
}

/// What is recorded (spec §5.2): mic off without permission, keys off without Accessibility, cam off without
/// permission or a camera, an unknown device id → the default.
public func effectiveOptions(
    _ options: RecordingOptions, permissions: RecordingPermissions, devices: CaptureDeviceList
) -> RecordingOptions {
    var effective = options
    if permissions.microphone != .granted { effective.mic = false }
    if permissions.accessibility != .granted { effective.keys = false }
    if permissions.camera != .granted || devices.cameras.isEmpty { effective.camera = false }
    if !devices.microphones.contains(options.micDevice) { effective.micDevice = "" }
    if !devices.cameras.contains(options.cameraDevice) { effective.cameraDevice = "" }
    return effective
}
