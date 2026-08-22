import Foundation
import Testing
@testable import Yami

/// Regression cover for the bug that wedged the app: the availability check was
/// stricter than the listener it guards, so a leaked client connection made Yami
/// refuse to start a core over a port mihomo could have bound fine.
@Suite("PortGuard")
struct PortGuardTests {
    // MARK: - Socket fixtures

    private static func listener() -> (fd: Int32, port: Int) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = Self.loopback(port: 0)
        _ = withUnsafePointer(to: &addr) { raw in
            raw.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        listen(fd, 5)

        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) { raw in
            raw.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        return (fd, Int(UInt16(bigEndian: actual.sin_port)))
    }

    private static func loopback(port: Int) -> sockaddr_in {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return addr
    }

    private static func connectClient(to port: Int) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var addr = loopback(port: port)
        _ = withUnsafePointer(to: &addr) { raw in
            raw.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return fd
    }

    /// A bind with no SO_REUSEADDR — the check as it was originally written.
    /// Present so the regression test proves *why* it changed rather than just
    /// asserting the current behaviour.
    private static func naiveBindSucceeds(port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = loopback(port: port)
        let bound = withUnsafePointer(to: &addr) { raw in
            raw.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bound == 0
    }

    // MARK: - Tests

    @Test("a port nobody holds is available")
    func freePortIsAvailable() {
        let (fd, port) = Self.listener()
        close(fd)
        #expect(PortGuard.isPortAvailable(port))
    }

    /// The case the check exists for: another client (Clash Verge, a stale core)
    /// actually serving on our port.
    @Test("a port with a live listener is not available")
    func listeningPortIsUnavailable() {
        let (fd, port) = Self.listener()
        defer { close(fd) }
        #expect(PortGuard.isPortAvailable(port) == false)
    }

    /// The regression. Terminating a core whose client leaked its connection
    /// leaves the core's side in FIN_WAIT_2 still holding the port. mihomo — via
    /// Go's net.Listen, which sets SO_REUSEADDR — rebinds happily, so Yami must
    /// not report a conflict.
    @Test("a port held only by a half-closed connection is available")
    func finWait2PortIsAvailable() {
        let (listenFD, port) = Self.listener()
        let clientFD = Self.connectClient(to: port)
        let acceptedFD = accept(listenFD, nil, nil)
        defer { close(clientFD) }

        close(listenFD)    // give up the LISTEN, as a terminating core would
        close(acceptedFD)  // server sends FIN; the client never closes
        usleep(150_000)    // let the socket settle into FIN_WAIT_2

        // Proves the scenario is a genuine conflict for a naive check, so this
        // test cannot quietly become vacuous.
        #expect(Self.naiveBindSucceeds(port: port) == false,
                "fixture did not produce a half-closed conflict")
        #expect(PortGuard.isPortAvailable(port),
                "a half-closed peer must not block the core from restarting")
    }

    @Test("canConnect follows a listener appearing and going away")
    func canConnectTracksListener() {
        let (fd, port) = Self.listener()
        #expect(PortGuard.canConnect(port: port))
        close(fd)
        #expect(PortGuard.canConnect(port: port) == false)
    }
}
