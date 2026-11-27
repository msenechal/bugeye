#if DEBUG
    import BugeyeFeatures
    import Darwin
    import Foundation
    import Testing

    @testable import BugeyeApp

    @Suite(.timeLimit(.minutes(1))) struct DebugChannelTests {
        /// A short path: Unix socket paths are limited to 104 bytes on macOS.
        let path = "/tmp/bugeye-\(UUID().uuidString.prefix(8)).sock"

        /// Connects, sends each command, and returns the reply lines.
        func ask(_ commands: [String]) throws -> [String] {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            #expect(fd >= 0)
            defer { close(fd) }
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            try #require(connected == 0)
            let request = Array(commands.map { $0 + "\n" }.joined().utf8)
            _ = request.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }

            var received: [UInt8] = []
            var buffer = [UInt8](repeating: 0, count: 256)
            while received.filter({ $0 == UInt8(ascii: "\n") }).count < commands.count {
                let count = read(fd, &buffer, buffer.count)
                guard count > 0 else { break }
                received += buffer[0..<count]
            }
            return String(decoding: received, as: UTF8.self).split(separator: "\n").map(String.init)
        }

        @Test func answersPingAndModules() throws {
            let channel = DebugChannel(path: path, handler: DebugCommandHandler(moduleIDs: ["general"]))
            try channel.start()
            defer { channel.stop() }
            #expect(try ask(["ping", "modules"]) == ["pong", "general"])
        }

        @Test func theSocketIsPrivateAndRemovedOnStop() throws {
            let channel = DebugChannel(path: path, handler: DebugCommandHandler(moduleIDs: []))
            try channel.start()
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            channel.stop()
            #expect(!FileManager.default.fileExists(atPath: path))
        }
    }
#endif
