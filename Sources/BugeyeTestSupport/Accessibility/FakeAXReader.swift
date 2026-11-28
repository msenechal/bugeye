import BugeyeCore

/// An Accessibility tree given by the test: the element at a point is the last one containing it.
public struct FakeAXReader: AXReader {
    public var elementsByProcess: [Int32: [AXElementInfo]]
    public init(elementsByProcess: [Int32: [AXElementInfo]] = [:]) { self.elementsByProcess = elementsByProcess }

    public func element(at point: Point2D) async throws -> AXElementInfo? {
        elementsByProcess.values.flatMap { $0 }.last { $0.frame.contains(point) }
    }

    public func elements(inWindowOf processID: Int32) async throws -> [AXElementInfo] {
        elementsByProcess[processID] ?? []
    }
}
