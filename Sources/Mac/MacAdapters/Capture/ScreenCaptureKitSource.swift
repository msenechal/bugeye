import AppKit
import BugeyeCore
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// `ScreenSource` on ScreenCaptureKit (design/02 §2.4, Capture C8). A freeze is one `SCShareableContent` fetch, then
/// every display concurrently, Bugeye's windows excluded by process id. Scale comes from the captured image.
public struct ScreenCaptureKitSource: ScreenSource {
    public init() {}

    /// From `NSScreen`, without a shareable-content fetch. Frames are Cocoa global points.
    public func displays() async throws -> [DisplayInfo] {
        await MainActor.run { Self.screens() }
    }

    @MainActor
    static func screens() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let frame = screen.frame
            return DisplayInfo(
                id: DisplayID(number.uint32Value),
                frame: Rect2D(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height),
                scale: screen.backingScaleFactor)
        }
    }

    public func freeze(displays wanted: [DisplayID]?) async throws -> [FrozenDisplay] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let own = getpid()
            let excluded = content.windows.filter { $0.owningApplication?.processID == own }
            let infos = await MainActor.run { Self.screens() }
            let order = try Self.targets(
                wanted: wanted, available: content.displays.map { DisplayID($0.displayID) }, screens: infos.map(\.id))
            var jobs:
                [(
                    index: Int, info: DisplayInfo, filter: Unchecked<SCContentFilter>,
                    config: Unchecked<SCStreamConfiguration>
                )] = []
            for (index, id) in order.enumerated() {
                guard let display = content.displays.first(where: { $0.displayID == id.rawValue }),
                    let info = infos.first(where: { $0.id == id })
                else { throw ScreenSourceError.displayNotFound }
                let filter = SCContentFilter(display: display, excludingWindows: excluded)
                let config = SCStreamConfiguration()
                let size = Self.pixelSize(
                    pointWidth: Double(filter.contentRect.width), pointHeight: Double(filter.contentRect.height),
                    scale: Double(filter.pointPixelScale))
                config.width = size.width
                config.height = size.height
                config.showsCursor = false
                config.captureResolution = .best
                jobs.append((index, info, Unchecked(value: filter), Unchecked(value: config)))
            }
            return try await withThrowingTaskGroup(of: (Int, FrozenDisplay).self) { group in
                for job in jobs {
                    group.addTask {
                        let image = try await SCScreenshotManager.captureImage(
                            contentFilter: job.filter.value, configuration: job.config.value)
                        return (
                            job.index,
                            FrozenDisplay(display: job.info, image: CapturedImage(cgImage: image), time: Date())
                        )
                    }
                }
                var frozen: [(Int, FrozenDisplay)] = []
                for try await result in group { frozen.append(result) }
                return frozen.sorted { $0.0 < $1.0 }.map(\.1)
            }
        } catch {
            throw Self.map(error)
        }
    }

    public func captureWindow(_ id: WindowID, pixelSize: Size2D) async throws -> CapturedImage {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == id.rawValue }) else {
                throw ScreenSourceError.windowNotFound
            }
            // A desktop-independent window filter gives a transparent background; the shadow is kept.
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = max(1, Int(pixelSize.width.rounded()))
            config.height = max(1, Int(pixelSize.height.rounded()))
            config.showsCursor = false
            config.captureResolution = .best
            config.ignoreShadowsSingleWindow = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return CapturedImage(cgImage: image)
        } catch {
            throw Self.map(error)
        }
    }

    /// The displays to freeze, in ScreenCaptureKit's order. Asked-for ids must all be there; with none asked, a display
    /// ScreenCaptureKit lists before `NSScreen` knows it (just plugged in) is skipped rather than failing the freeze.
    public static func targets(wanted: [DisplayID]?, available: [DisplayID], screens: [DisplayID]) throws -> [DisplayID]
    {
        if let wanted {
            for id in wanted where !available.contains(id) || !screens.contains(id) {
                throw ScreenSourceError.displayNotFound
            }
            return available.filter { wanted.contains($0) }
        }
        let known = available.filter { screens.contains($0) }
        guard !known.isEmpty else { throw ScreenSourceError.displayNotFound }
        return known
    }

    /// The frame's pixel size: its points × the display's point-pixel scale, rounded (design/02 §2.4).
    public static func pixelSize(pointWidth: Double, pointHeight: Double, scale: Double) -> (width: Int, height: Int) {
        (Int((pointWidth * scale).rounded()), Int((pointHeight * scale).rounded()))
    }

    /// `userDeclined` → `permissionDenied` (the alert); `ScreenSourceError` passes through; anything else is
    /// `failed(localizedDescription)` (`Capture failed`).
    public static func map(_ error: any Error) -> ScreenSourceError {
        if let mapped = error as? ScreenSourceError { return mapped }
        let ns = error as NSError
        if ns.domain == SCStreamError.errorDomain, ns.code == SCStreamError.Code.userDeclined.rawValue {
            return .permissionDenied
        }
        return .failed(error.localizedDescription)
    }
}

/// Lets a ScreenCaptureKit filter or configuration (never mutated once built, but not marked `Sendable` by the SDK)
/// cross into the freeze's child tasks. Private so nothing else can use it to hide a non-Sendable value.
private struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
}
