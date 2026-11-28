import AVFoundation
import ApplicationServices
import BugeyeCore

/// Microphone and camera through AVCaptureDevice, Accessibility through AXIsProcessTrusted (Recording §3.1).
public struct SystemMediaPermissions: MediaPermissions {
    public init() {}

    public func state(_ permission: MediaPermission) -> PermissionState {
        switch permission {
        case .microphone: Self.state(AVCaptureDevice.authorizationStatus(for: .audio))
        case .camera: Self.state(AVCaptureDevice.authorizationStatus(for: .video))
        // macOS has no "not determined" for Accessibility: untrusted reads as denied.
        case .accessibility: AXIsProcessTrusted() ? .granted : .denied
        }
    }

    public func request(_ permission: MediaPermission) async -> PermissionState {
        switch permission {
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .accessibility:
            // The literal key of kAXTrustedCheckOptionPrompt (a C global Swift 6 can't read safely).
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        return state(permission)
    }

    public static func state(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }
}
