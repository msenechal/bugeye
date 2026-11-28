import BugeyeFeatures
import TextCore

/// Created by the contracts PR, owned by the OCR epic afterwards. OCR has no module; its install returns the text
/// services. Both stay as they are until OCR's last (wiring) PR (K7).
@MainActor
enum TextWiring {
    static let modules: [any FeatureModule] = []
    static func install(_ context: AppContext) -> TextServices { TextServices() }
}
