/// User notifications (UNUserNotificationCenter on macOS). Capture, Quick Access, Editor, Recording.
public protocol Notifier: Sendable {
    func post(title: String, body: String)
}
