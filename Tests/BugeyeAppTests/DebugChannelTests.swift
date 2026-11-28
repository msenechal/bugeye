#if DEBUG
    import BugeyeCore
    import BugeyeFeatures
    import BugeyeTestSupport
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

        /// The handler and its shell objects, made on the main actor. The test itself stays off the main actor:
        /// the channel answers on the main thread, which a blocking `ask` must not hold.
        struct Shell: Sendable {
            let handler: DebugCommandHandler
            let router: ActionRouter
            let bus: CaptureEventBus
            let settings: InMemorySettingsStore
        }

        func shell(moduleIDs: [String] = ["general"]) async -> Shell {
            await MainActor.run {
                let router = ActionRouter()
                let bus = CaptureEventBus()
                let settings = InMemorySettingsStore()
                let commands = DebugCommands()
                commands.register("recording.state") { "idle\($0.isEmpty ? "" : " " + $0)" }
                let handler = DebugCommandHandler(
                    moduleIDs: moduleIDs, router: router, settings: settings, bus: bus,
                    registered: { commands.handler(for: $0) })
                return Shell(handler: handler, router: router, bus: bus, settings: settings)
            }
        }

        @Test func answersPingAndModules() async throws {
            let channel = DebugChannel(path: path, handler: await shell().handler)
            try channel.start()
            defer { channel.stop() }
            #expect(try ask(["ping", "modules"]) == ["pong", "general"])
        }

        @Test func answersTheWaveOneCommandsOnTheMainActor() async throws {
            let shell = await shell()
            await MainActor.run {
                shell.router.onHotkey("capture.area") { MainActor.assertIsolated() }
                shell.router.onMenuItem("capture.window") {}
                shell.bus.publish(
                    CaptureEvent(
                        change: .created,
                        item: CaptureItem(
                            id: CaptureID(string: "e621e1f8-c36c-495a-93fc-0c247a3e6e5f")!,
                            fileURL: URL(fileURLWithPath: "/tmp/a.png"), isSaved: false, kind: .screenshot,
                            createdAt: Date(), pixelsPerPoint: 2),
                        origin: "capture"))
            }
            let channel = DebugChannel(path: path, handler: shell.handler)
            try channel.start()
            defer { channel.stop() }
            #expect(
                try ask([
                    "hotkey capture.area", "menu capture.window", "set capture.saveToFolder false",
                    "get capture.saveToFolder", "events", "recording.state", "hotkey nope",
                ]) == [
                    "ok", "ok", "ok", "false",
                    #"[{"change":"created","file":"a.png","id":"e621e1f8-c36c-495a-93fc-0c247a3e6e5f","origin":"capture"}]"#,
                    "idle", "error: no hotkey nope",
                ])
            #expect(shell.settings.value(forKey: "capture.saveToFolder") == .bool(false))
        }

        @Test func aClientThatHangsUpBeforeTheReplyDoesNotKillTheApp() async throws {
            let channel = DebugChannel(path: path, handler: await shell(moduleIDs: []).handler)
            try channel.start()
            defer { channel.stop() }
            // Send a command and close at once: the reply is written to a closed socket (SIGPIPE by default).
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            try #require(connected == 0)
            let request = Array("ping\nping\nping\n".utf8)
            _ = request.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            close(fd)
            // Still alive and still serving.
            #expect(try ask(["ping"]) == ["pong"])
        }

        @Test func theSocketIsPrivateAndRemovedOnStop() async throws {
            let channel = DebugChannel(path: path, handler: await shell(moduleIDs: []).handler)
            try channel.start()
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            channel.stop()
            #expect(!FileManager.default.fileExists(atPath: path))
        }
    }
#endif
