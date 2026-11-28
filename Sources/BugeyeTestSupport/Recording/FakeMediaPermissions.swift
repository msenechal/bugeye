import BugeyeCore
import Synchronization

/// Permission states given by the test. `request` applies the scripted answer for that permission, if any,
/// and records the call.
public final class FakeMediaPermissions: MediaPermissions {
    private struct State {
        var states: [MediaPermission: PermissionState]
        var answers: [MediaPermission: PermissionState]
        var requests: [MediaPermission] = []
    }
    private let state: Mutex<State>

    public init(
        _ states: [MediaPermission: PermissionState] = [:], answers: [MediaPermission: PermissionState] = [:]
    ) {
        state = Mutex(State(states: states, answers: answers))
    }

    public var requests: [MediaPermission] { state.withLock { $0.requests } }

    public func set(_ permission: MediaPermission, _ value: PermissionState) {
        state.withLock { $0.states[permission] = value }
    }

    public func state(_ permission: MediaPermission) -> PermissionState {
        state.withLock { $0.states[permission] ?? .notDetermined }
    }

    public func request(_ permission: MediaPermission) async -> PermissionState {
        state.withLock { state in
            state.requests.append(permission)
            if let answer = state.answers[permission] { state.states[permission] = answer }
            return state.states[permission] ?? .notDetermined
        }
    }
}
