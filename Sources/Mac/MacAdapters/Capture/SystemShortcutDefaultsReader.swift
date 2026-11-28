import BugeyeCore
import CoreFoundation
import Foundation

/// `SystemShortcutReader` on `com.apple.symbolichotkeys` and `sysctl hw.model` (Capture C13).
public struct SystemShortcutDefaultsReader: SystemShortcutReader {
    public init() {}

    public func symbolicHotkeys() -> [Int: SymbolicHotkey]? {
        guard
            let value = CFPreferencesCopyAppValue(
                "AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString),
            let dictionary = value as? [String: Any]
        else { return nil }
        return Self.parse(dictionary)
    }

    /// `{"28": {"enabled": 1, "value": {"parameters": [51, 20, 1179648], "type": "standard"}}, …}`.
    public static func parse(_ dictionary: [String: Any]) -> [Int: SymbolicHotkey] {
        var result: [Int: SymbolicHotkey] = [:]
        for (key, raw) in dictionary {
            guard let number = Int(key), let entry = raw as? [String: Any] else { continue }
            let enabled = (entry["enabled"] as? NSNumber)?.boolValue ?? false
            let value = entry["value"] as? [String: Any]
            let parameters = (value?["parameters"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } ?? []
            result[number] = SymbolicHotkey(enabled: enabled, parameters: parameters)
        }
        return result
    }

    public func hardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
