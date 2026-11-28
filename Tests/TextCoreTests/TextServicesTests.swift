import Testing

@testable import TextCore

@MainActor @Test func textServicesCanBeMade() {
    _ = TextServices()
}
