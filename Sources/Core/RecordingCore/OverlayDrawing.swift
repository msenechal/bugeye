import BugeyeCore

/// The keystroke badge (§5.4): a label shown 1.5 s, the last 0.3 s fading; the same label within 1.5 s counts
/// "×N". Times in seconds (any clock); drawing in the area's points, top-left.
public struct KeystrokeBadge: Hashable, Sendable {
    public static let visible = 1.5
    public static let fade = 0.3
    public static let font = FontDescriptor(name: FontDescriptor.systemFontName, size: 22, weight: 0.3)
    public static let bottomGap = 40.0
    public static let padding = Size2D(width: 14, height: 8)
    public static let cornerRadius = 10.0
    public static let background = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.75)
    public static let foreground = RGBAColor(red: 1, green: 1, blue: 1)

    private var label: String?
    private var count = 0
    private var shownAt = -Double.infinity

    public init() {}

    /// Auto-repeat is never passed here.
    public mutating func press(_ label: String, at time: Double) {
        if label == self.label, time - shownAt < Self.visible {
            count += 1
        } else {
            self.label = label
            count = 1
        }
        shownAt = time
    }

    public func isVisible(at time: Double) -> Bool {
        label != nil && time >= shownAt && time - shownAt < Self.visible
    }

    public func text(at time: Double) -> String? {
        guard isVisible(at: time), let label else { return nil }
        return count > 1 ? "\(label) ×\(count)" : label
    }

    public func opacity(at time: Double) -> Double {
        guard isVisible(at: time) else { return 0 }
        let left = Self.visible - (time - shownAt)
        // Rounded to a thousandth, so drawing and goldens carry no float noise.
        return left >= Self.fade ? 1 : (left / Self.fade * 1000).rounded() / 1000
    }

    /// Centred, 40 pt above the bottom of `area`; nil when nothing shows.
    public func displayList(at time: Double, area: Size2D, measurer: any TextMeasuring) -> DisplayList? {
        guard let text = text(at: time) else { return nil }
        let metrics = measurer.measure(text, font: Self.font)
        let width = metrics.width + 2 * Self.padding.width
        let height = metrics.ascent + metrics.descent + 2 * Self.padding.height
        let rect = Rect2D(
            x: max((area.width - width) / 2, 0), y: area.height - Self.bottomGap - height, width: width, height: height)
        return DisplayList(
            size: area,
            commands: [
                .pushGroup(GroupStyle(opacity: opacity(at: time))),
                .fillPath(.roundedRect(rect, cornerRadius: Self.cornerRadius), color: Self.background),
                .textRun(
                    text,
                    origin: Point2D(
                        x: rect.minX + Self.padding.width, y: rect.minY + Self.padding.height + metrics.ascent),
                    font: Self.font, color: Self.foreground),
                .popGroup,
            ])
    }
}

/// Click rings (§5.4): left clicks yellow, right clicks pink, growing from 14 to 28 pt across (ease-out) and
/// fading over 0.5 s; 3 pt stroke and a 25 % fill. Points in the area, top-left.
public struct ClickRings: Hashable, Sendable {
    public static let duration = 0.5
    public static let startDiameter = 14.0
    public static let endDiameter = 28.0
    public static let lineWidth = 3.0
    public static let fillAlpha = 0.25
    /// systemYellow and systemPink.
    public static let yellow = RGBAColor(red: 1, green: 0.8, blue: 0)
    public static let pink = RGBAColor(red: 1, green: 0.176, blue: 0.333)

    private struct Ring: Hashable, Sendable {
        var center: Point2D
        var color: RGBAColor
        var start: Double
    }

    private var rings: [Ring] = []

    public init() {}

    /// Other buttons don't ring.
    public mutating func click(_ button: TimelineButton, at point: Point2D, time: Double) {
        let color: RGBAColor
        switch button {
        case .left: color = Self.yellow
        case .right: color = Self.pink
        case .other: return
        }
        rings.removeAll { time - $0.start >= Self.duration }
        rings.append(Ring(center: point, color: color, start: time))
    }

    public func count(at time: Double) -> Int { live(at: time).count }

    /// The overlay's animation timer stops when this is false.
    public func isAnimating(at time: Double) -> Bool { !live(at: time).isEmpty }

    /// Ease-out (quadratic).
    public static func diameter(progress: Double) -> Double {
        let p = min(max(progress, 0), 1)
        return startDiameter + (endDiameter - startDiameter) * (1 - (1 - p) * (1 - p))
    }

    public func displayList(at time: Double, area: Size2D) -> DisplayList {
        var commands: [DisplayCommand] = []
        for ring in live(at: time) {
            let progress = (time - ring.start) / Self.duration
            let d = Self.diameter(progress: progress)
            let alpha = 1 - progress
            let path = VectorPath.ellipse(
                in: Rect2D(x: ring.center.x - d / 2, y: ring.center.y - d / 2, width: d, height: d))
            var fill = ring.color
            fill.alpha = Self.fillAlpha * alpha
            var stroke = ring.color
            stroke.alpha = alpha
            commands += [
                .fillPath(path, color: fill), .strokePath(path, color: stroke, lineWidth: Self.lineWidth),
            ]
        }
        return DisplayList(size: area, commands: commands)
    }

    private func live(at time: Double) -> [Ring] {
        rings.filter { time >= $0.start && time - $0.start < Self.duration }
    }
}
