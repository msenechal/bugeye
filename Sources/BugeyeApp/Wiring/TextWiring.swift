import BugeyeCore
import BugeyeFeatures
import MacAdapters
import TextCore
import os

/// The OCR epic's wiring (OCR §7, T12): Vision and ImageIO behind `TextMapReader`, the per-capture store fed from
/// the bus, and its log lines to `os.Logger` (subsystem `dev.msenechal.bugeye`, category `text`). OCR has no module;
/// nothing here is user-visible.
@MainActor
enum TextWiring {
    static let modules: [any FeatureModule] = []

    static func install(_ context: AppContext) -> TextServices {
        let files = ImageIOFileReader()
        let reader = TextMapReader(reader: VisionTextReader(), files: files)
        let maps = CaptureTextMaps(reader: reader, files: files, log: { TextWiring.log($0) })
        return TextServices(maps: maps, bus: context.captureEvents)
    }

    /// Ids, sizes and timings only: the lines never hold recognised text or file names (OCR §6), so they are public.
    nonisolated static func log(_ line: TextLogLine) {
        let logger = Logger(subsystem: CaptureFolders.bundleID, category: "text")
        let message = line.description
        switch line {
        case .failed: logger.error("\(message, privacy: .public)")
        default: logger.notice("\(message, privacy: .public)")
        }
    }
}
