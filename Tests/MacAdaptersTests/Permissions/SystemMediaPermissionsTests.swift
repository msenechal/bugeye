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

    /// Reading never prompts; Accessibility is never "not determined".
    @Test func statesReadWithoutPrompting() {
        let permissions = SystemMediaPermissions()
        _ = permissions.state(.microphone)
        _ = permissions.state(.camera)
        #expect(permissions.state(.accessibility) != .notDetermined)
    }
}
