import AVFoundation
import BugeyeCore
import MacAdapters
import Testing

@Suite struct SystemMediaPermissionsTests {
    @Test func authorizationStatusesMap() {
        #expect(SystemMediaPermissions.state(.authorized) == .granted)
        #expect(SystemMediaPermissions.state(.notDetermined) == .notDetermined)
        #expect(SystemMediaPermissions.state(.denied) == .denied)
        #expect(SystemMediaPermissions.state(.restricted) == .denied)
    }

    /// Reading doesn't crash or prompt; Accessibility reads granted or denied.
    @Test func statesReadWithoutCrashing() {
        let permissions = SystemMediaPermissions()
        _ = permissions.state(.microphone)
        _ = permissions.state(.camera)
        #expect(permissions.state(.accessibility) != .notDetermined)
    }
}
