import BugeyeCore
import Carbon.HIToolbox
import Foundation

/// `HotkeyRegistrar` on Carbon's `RegisterEventHotKey` (Capture §5.6), signature `'BgEy'`, distinct from the old
/// app's `'CSC!'`. Presses arrive on the main thread's event loop.
@MainActor
public final class CarbonHotkeyRegistrar: HotkeyRegistrar {
    /// 'BgEy'.
    public nonisolated static let signature: OSType = 0x4267_4579

    private var registrations: [String: (ref: EventHotKeyRef, number: UInt32)] = [:]
    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var nextNumber: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    public init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == CarbonHotkeyRegistrar.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let registrar = Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
            let number = hotKeyID.id
            MainActor.assumeIsolated { registrar.fire(number) }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    public func register(_ id: String, key: GlobalKey, onPress: @escaping @MainActor () -> Void) -> Bool {
        unregister(id)
        guard let code = Self.keyCode(for: key.key) else { return false }
        let number = nextNumber
        nextNumber += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            code, Self.carbonModifiers(key), EventHotKeyID(signature: Self.signature, id: number),
            GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        registrations[id] = (ref, number)
        handlers[number] = onPress
        return true
    }

    public func unregister(_ id: String) {
        guard let registration = registrations.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(registration.ref)
        handlers[registration.number] = nil
    }

    private func fire(_ number: UInt32) {
        handlers[number]?()
    }

    /// Carbon modifier bits.
    public nonisolated static func carbonModifiers(_ key: GlobalKey) -> UInt32 {
        var bits = 0
        if key.command { bits |= cmdKey }
        if key.option { bits |= optionKey }
        if key.control { bits |= controlKey }
        if key.shift { bits |= shiftKey }
        return UInt32(bits)
    }

    /// The ANSI virtual key code of a lowercase letter or digit, or Escape.
    public nonisolated static func keyCode(for key: String) -> UInt32? {
        let codes: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
            "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
            "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "\u{1B}": kVK_Escape,
        ]
        return codes[key].map { UInt32($0) }
    }
}
