#if DEBUG
    import BugeyeFeatures
    import Darwin
    import Foundation
    import Synchronization

    /// The debug test channel (spec §5.6, `design/13` §4): a Unix-domain socket in the app's temp folder that
    /// answers one command per line through `DebugCommandHandler`. Debug builds only; release builds contain
    /// none of it (`scripts/check-release-symbols.sh`).
    final class DebugChannel: Sendable {
        static func defaultSocketPath() -> String {
            FileManager.default.temporaryDirectory.appendingPathComponent("bugeye-debug.sock").path
        }

        private let path: String
        private let handler: DebugCommandHandler
        private let listener = Mutex<Int32>(-1)
        private let stopped = Mutex(false)

        init(path: String, handler: DebugCommandHandler) {
            self.path = path
            self.handler = handler
        }

        func start() throws {
            unlink(path)
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw Self.posixError(errno) }
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let bytes = Array(path.utf8)
            guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
                close(fd)
                throw POSIXError(.ENAMETOOLONG)
            }
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0, listen(fd, 4) == 0 else {
                let code = errno
                close(fd)
                throw Self.posixError(code)
            }
            chmod(path, 0o600)
            listener.withLock { $0 = fd }
            let thread = Thread { [self] in acceptLoop(fd) }
            thread.name = "dev.msenechal.bugeye.debug-channel"
            thread.start()
        }

        func stop() {
            stopped.withLock { $0 = true }
            let fd = listener.withLock { fd in
                defer { fd = -1 }
                return fd
            }
            if fd >= 0 { close(fd) }
            unlink(path)
        }

        private func acceptLoop(_ fd: Int32) {
            while !stopped.withLock({ $0 }) {
                // Wake every 200 ms to notice stop(); closing a socket doesn't interrupt accept() on macOS.
                var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let ready = poll(&poller, 1, 200)
                guard ready > 0 else { continue }
                let client = accept(fd, nil, nil)
                guard client >= 0 else { continue }
                serve(client)
                close(client)
            }
        }

        private func serve(_ client: Int32) {
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            // A client that hangs up before reading its reply must not kill the app: without this, the write
            // below raises SIGPIPE, whose default action ends the process. The write then fails with EPIPE.
            var noSigPipe: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            var pending: [UInt8] = []
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = read(client, &buffer, buffer.count)
                guard count > 0 else { return }
                pending += buffer[0..<count]
                while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = String(decoding: pending[..<newline], as: UTF8.self)
                    pending.removeSubrange(...newline)
                    let reply = Array((handler.respond(to: line) + "\n").utf8)
                    let written = reply.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
                    guard written == reply.count else { return }
                }
                if pending.count > 4096 { return }  // No newline in sight: drop the client.
            }
        }

        private static func posixError(_ code: Int32) -> POSIXError {
            POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }
#endif
