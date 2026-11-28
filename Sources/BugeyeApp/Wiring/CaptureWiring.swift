import BugeyeFeatures

/// Created by the contracts PR, owned by the Capture epic afterwards. Both members stay empty until its last
/// (wiring) PR, so `main` never shows half a feature (K7).
@MainActor
enum CaptureWiring {
    static let modules: [any FeatureModule] = []
    static func install(_ context: AppContext) {}
}
