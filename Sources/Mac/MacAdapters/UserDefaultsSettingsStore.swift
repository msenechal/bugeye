import BugeyeCore
import Foundation

/// `SettingsStore` over `UserDefaults`. The only place in the app that touches UserDefaults
/// (`scripts/guards.sh` checks).
public final class UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    // @unchecked: UserDefaults is documented as thread-safe; `defaults` is never reassigned.
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func value(forKey key: String) -> SettingValue? {
        switch defaults.object(forKey: key) {
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            if CFNumberIsFloatType(number as CFNumber) { return .double(number.doubleValue) }
            return .int(number.intValue)
        default:
            return nil
        }
    }

    public func setValue(_ value: SettingValue?, forKey key: String) {
        switch value {
        case nil: defaults.removeObject(forKey: key)
        case .string(let string)?: defaults.set(string, forKey: key)
        case .bool(let bool)?: defaults.set(bool, forKey: key)
        case .int(let int)?: defaults.set(int, forKey: key)
        case .double(let double)?: defaults.set(double, forKey: key)
        }
    }
}
