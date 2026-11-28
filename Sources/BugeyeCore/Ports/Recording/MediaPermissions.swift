// Recording-owned in Wave 1 (spec §3.1).

public enum MediaPermission: String, Hashable, Sendable, CaseIterable { case microphone, camera, accessibility }

public enum PermissionState: String, Hashable, Sendable { case granted, denied, notDetermined }

/// Microphone, camera and Accessibility permission (AVCaptureDevice and AXIsProcessTrusted on macOS).
public protocol MediaPermissions: Sendable {
    func state(_ permission: MediaPermission) -> PermissionState
    /// Shows the system prompt where macOS has one (microphone, camera: AVCaptureDevice.requestAccess;
    /// accessibility: AXIsProcessTrustedWithOptions with prompt) and returns the state afterwards.
    /// Accessibility returns its current state at once; the user grants it later in System Settings.
    func request(_ permission: MediaPermission) async -> PermissionState
}
