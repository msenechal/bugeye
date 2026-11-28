import Foundation

public enum CaptureKind: String, Hashable, Codable, Sendable, CaseIterable {
    case screenshot, recording, gif, collection

    /// "Screenshot", "Recording", "Recording", "Collection".
    public var namePrefix: String {
        switch self {
        case .screenshot: "Screenshot"
        case .recording, .gif: "Recording"
        case .collection: "Collection"
        }
    }

    /// "png", "mp4", "gif", "bugeye": only the default for new files. The extension of an item's `fileURL`
    /// is authoritative (a recording can be a `.mov`, Recording V8), and Save keeps it.
    public var fileExtension: String {
        switch self {
        case .screenshot: "png"
        case .recording: "mp4"
        case .gif: "gif"
        case .collection: "bugeye"
        }
    }
}

/// One capture as every module knows it. Provenance and snapshots stay on the file (xattrs), not here.
public struct CaptureItem: Hashable, Codable, Sendable, Identifiable {
    public var id: CaptureID
    public var fileURL: URL
    /// In the save folder. False: in the temp folder, until Quick Access saves it.
    public var isSaved: Bool
    public var kind: CaptureKind
    /// When the pixels were taken (Capture C10); a recording's first frame (Recording §5.6).
    public var createdAt: Date
    /// 2 on Retina, 1 on a 1× display or after "Downscale Retina captures to 1×"; a recording's stream scale.
    public var pixelsPerPoint: Double
    /// Seconds, for recordings and GIFs; nil for stills.
    public var duration: Double?

    public init(
        id: CaptureID, fileURL: URL, isSaved: Bool, kind: CaptureKind, createdAt: Date, pixelsPerPoint: Double,
        duration: Double? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.isSaved = isSaved
        self.kind = kind
        self.createdAt = createdAt
        self.pixelsPerPoint = pixelsPerPoint
        self.duration = duration
    }
}

/// What happened to a capture. An open set: later epics add values without breaking anyone's switch,
/// so subscribers ignore changes they don't know.
public struct CaptureChange: RawRepresentable, Hashable, Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// A new capture's file exists.
    public static let created = CaptureChange(rawValue: "created")
    /// Moved from the temp folder into the save folder.
    public static let saved = CaptureChange(rawValue: "saved")
    /// The file now lives at another URL, for any other reason.
    public static let moved = CaptureChange(rawValue: "moved")
    /// The file's content was rewritten in place.
    public static let edited = CaptureChange(rawValue: "edited")
    /// Trashed (saved) or removed (temp).
    public static let deleted = CaptureChange(rawValue: "deleted")
    /// A document window (the editor) opened on it; the item is unchanged.
    public static let editingStarted = CaptureChange(rawValue: "editingStarted")
    /// That window closed.
    public static let editingEnded = CaptureChange(rawValue: "editingEnded")
}

public struct CaptureEvent: Hashable, Sendable {
    /// The widest a `preview` may be, in pixels.
    public static let previewMaxWidth = 480

    public var change: CaptureChange
    /// The capture as it is after the change. Publishers take it from `bus.item(id)`, not a stale copy.
    public var item: CaptureItem
    /// For saved and moved: where the file was.
    public var previousURL: URL?
    /// For created and edited: the image at most `previewMaxWidth` wide (sRGB), so no subscriber decodes the
    /// file. Nil when it couldn't be made (Quick Access then shows a generic icon).
    public var preview: PixelBuffer?
    /// The publishing module's `FeatureModule.id`: "capture", "quickAccess", "editor", "recording".
    public var origin: String

    public init(
        change: CaptureChange, item: CaptureItem, previousURL: URL? = nil, preview: PixelBuffer? = nil, origin: String
    ) {
        self.change = change
        self.item = item
        self.previousURL = previousURL
        self.preview = preview
        self.origin = origin
    }
}
