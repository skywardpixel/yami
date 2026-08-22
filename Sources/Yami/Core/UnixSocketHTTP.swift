import Foundation

/// A deliberately tiny HTTP client for mihomo's unix-domain external controller.
///
/// URLSession cannot address unix sockets, and the only request Yami ever makes
/// is `GET /version` as a readiness probe — so a raw socket beats pulling in a
/// networking dependency for one call.
enum UnixSocketHTTP {
    /// Returns the HTTP status code, or nil if the socket could not be reached.
    /// Blocking: call this off the main actor.
    static func get(_ path: String, socketPath: String, timeout: TimeInterval = 1.0) -> Int? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var timeval = timeval(
            tv_sec: Int(timeout),
            tv_usec: suseconds_t((timeout - Double(Int(timeout))) * 1_000_000)
        )
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeval, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeval, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard socketPath.utf8.count < capacity else { return nil }
        withUnsafeMutablePointer(to: &addr.sun_path) { dst in
            dst.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                _ = strncpy(dst, socketPath, capacity - 1)
            }
        }

        let connected = withUnsafePointer(to: &addr) { raw in
            raw.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                connect(fd, addr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }

        let request = "GET \(path) HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        let sent = request.withCString { send(fd, $0, strlen($0), 0) }
        guard sent > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: 256)
        let received = recv(fd, &buffer, buffer.count, 0)
        guard received > 0 else { return nil }

        // "HTTP/1.1 200 OK" — we only need the middle field of the status line.
        let head = String(decoding: buffer[0..<received], as: UTF8.self)
        let fields = head.split(separator: "\r\n", maxSplits: 1).first?.split(separator: " ") ?? []
        guard fields.count >= 2 else { return nil }
        return Int(fields[1])
    }
}
