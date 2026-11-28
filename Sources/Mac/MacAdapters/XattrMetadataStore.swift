import BugeyeCore
import Darwin
import Foundation

/// Extended attributes through Darwin's `listxattr`/`getxattr`/`setxattr`/`removexattr`, options 0
/// (symbolic links are followed, as Finder does).
public struct XattrMetadataStore: FileMetadataStore {
    public init() {}

    public func names(at url: URL) throws -> [String] {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw POSIXError(.ENOENT) }
            let size = listxattr(path, nil, 0, 0)
            guard size >= 0 else { throw Self.lastError() }
            guard size > 0 else { return [] }
            var buffer = [CChar](repeating: 0, count: size)
            let read = listxattr(path, &buffer, size, 0)
            guard read >= 0 else { throw Self.lastError() }
            return buffer[0..<read].split(separator: 0).map { name in
                String(decoding: name.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
    }

    public func value(_ name: String, at url: URL) throws -> Data? {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw POSIXError(.ENOENT) }
            let size = getxattr(path, name, nil, 0, 0, 0)
            if size < 0 {
                let code = errno
                if code == ENOATTR { return nil }
                throw Self.error(code)
            }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { buffer in
                getxattr(path, name, buffer.baseAddress, size, 0, 0)
            }
            if read < 0 { throw Self.lastError() }
            // Accept the value only if it didn't change size between the two reads (design/06 §2.6).
            guard read == size else { throw POSIXError(.EAGAIN) }
            return data
        }
    }

    public func setValue(_ value: Data, _ name: String, at url: URL) throws {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw POSIXError(.ENOENT) }
            let result = value.withUnsafeBytes { buffer in
                setxattr(path, name, buffer.baseAddress, value.count, 0, 0)
            }
            guard result == 0 else { throw Self.lastError() }
        }
    }

    public func removeValue(_ name: String, at url: URL) throws {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw POSIXError(.ENOENT) }
            guard removexattr(path, name, 0) == 0 else {
                let code = errno
                if code == ENOATTR { return }
                throw Self.error(code)
            }
        }
    }

    private static func lastError() -> POSIXError { error(errno) }

    private static func error(_ code: Int32) -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
}
