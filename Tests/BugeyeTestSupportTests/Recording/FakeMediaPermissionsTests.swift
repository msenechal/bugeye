import BugeyeCore
import BugeyeTestSupport
import Testing

@Suite struct FakeMediaPermissionsTests {
    @Test func statesDefaultToNotDetermined() {
        let permissions = FakeMediaPermissions()
        for permission in MediaPermission.allCases {
            #expect(permissions.state(permission) == .notDetermined)
        }
    }

    @Test func requestAppliesTheScriptedAnswerAndRecordsTheCall() async {
        let permissions = FakeMediaPermissions([.camera: .granted], answers: [.microphone: .denied])
        #expect(permissions.state(.camera) == .granted)
        #expect(await permissions.request(.microphone) == .denied)
        #expect(permissions.state(.microphone) == .denied)
        #expect(permissions.requests == [.microphone])
    }

    @Test func requestWithoutAScriptedAnswerKeepsTheState() async {
        let permissions = FakeMediaPermissions([.accessibility: .denied])
        #expect(await permissions.request(.accessibility) == .denied)
        permissions.set(.accessibility, .granted)
        #expect(permissions.state(.accessibility) == .granted)
    }
}
