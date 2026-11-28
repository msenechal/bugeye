import BugeyeCore
import Foundation
import Synchronization
@preconcurrency import UserNotifications

/// What `UserNotificationNotifier` needs from the notification center; injected in tests.
public protocol NotificationCenterClient: Sendable {
    /// Asks for `.alert` and `.sound`; true when granted.
    func requestAuthorization() async -> Bool
    func add(title: String, body: String)
}

/// User notifications through `UNUserNotificationCenter` (contracts §4.4, Capture §5.7, `design/01` §2.13).
/// Posts made before the authorization answer are held and delivered after it, in order. With no bundle id
/// (`swift run`, tests) it only logs `<title>: <body>`: `UNUserNotificationCenter` traps without one.
public final class UserNotificationNotifier: Notifier {
    private struct State {
        var answered = false
        var held: [(title: String, body: String)] = []
    }

    private let client: (any NotificationCenterClient)?
    private let log: @Sendable (String) -> Void
    private let state = Mutex(State())

    /// The live notifier: the system center when the process is an app bundle with a bundle id, else logging only
    /// (a test runner can have a bundle id without being an app, and the center traps there too).
    public convenience init() {
        let isApp = Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
        self.init(client: isApp ? SystemNotificationCenterClient() : nil)
    }

    public init(
        client: (any NotificationCenterClient)?, log: @escaping @Sendable (String) -> Void = { NSLog("%@", $0) }
    ) {
        self.client = client
        self.log = log
    }

    /// The shell calls this once at launch. Delivers the held posts after the answer, whatever it is (the system
    /// drops them if denied).
    public func requestAuthorization() async {
        guard let client else { return }
        _ = await client.requestAuthorization()
        state.withLock { state in
            state.answered = true
            for post in state.held { client.add(title: post.title, body: post.body) }
            state.held = []
        }
    }

    public func post(title: String, body: String) {
        guard let client else {
            log("\(title): \(body)")
            return
        }
        state.withLock { state in
            if state.answered {
                client.add(title: title, body: body)
            } else {
                state.held.append((title, body))
            }
        }
    }
}

/// The real center. Becomes its delegate so banners show while Bugeye is frontmost.
final class SystemNotificationCenterClient: NotificationCenterClient {
    private let delegate = PresentingDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func add(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("Notification not posted: %@", String(describing: error)) }
        }
    }
}

/// Shows banners even while Bugeye is the active app.
final class PresentingDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
