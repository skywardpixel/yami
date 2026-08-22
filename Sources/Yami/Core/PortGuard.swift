import Foundation

/// Pre-flight checks that run before every core launch.
///
/// Both exist because of the same failure: a core that is alive but not actually
/// serving. The control socket answering `/version` only proves the process
/// started — if the mixed port failed to bind, mihomo keeps running and the app
/// would otherwise report "Running" over a proxy that carries nothing. With the
/// system proxy pointed at that port, the machine loses all network.
enum PortGuard {
    /// Returns an error message, or nil if it is safe to launch.
    /// Blocking: call this off the main actor.
    static func preflight(port: Int) -> String? {
        reapOrphanedCores()
        guard isPortAvailable(port) else {
            // Name the culprit. "Port 7890 is already in use" sends you to lsof;
            // "in use by Clash Verge" tells you what to quit.
            if let holder = listenerName(on: port) {
                return "Port \(port) is in use by \(holder)"
            }
            return "Port \(port) is already in use"
        }
        return nil
    }

    /// Confirms something is actually accepting connections on the proxy port.
    /// The control socket answering only proves the process is alive.
    static func canConnect(port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connected = withUnsafePointer(to: &addr) { raw in
            raw.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return connected == 0
    }

    /// The command name of whatever is listening, for the error message only.
    private static func listenerName(on port: Int) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-F", "c"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .first { $0.hasPrefix("c") }
            .map { String($0.dropFirst()) }
    }

    /// A SIGKILLed Yami leaves its core running and holding both the proxy port
    /// and the config cache. Match on the socket path in argv: that string is
    /// unique to cores Yami spawned, so a mihomo the user runs by hand or under
    /// brew services is never touched.
    private static func reapOrphanedCores() {
        for pid in pidsMatching(Paths.socket.path) {
            kill(pid, SIGTERM)
        }
        // Give them a moment to go quietly, then insist.
        for _ in 0..<20 {
            let remaining = pidsMatching(Paths.socket.path)
            if remaining.isEmpty { return }
            usleep(100_000)
        }
        for pid in pidsMatching(Paths.socket.path) {
            kill(pid, SIGKILL)
        }
    }

    private static func pidsMatching(_ pattern: String) -> [pid_t] {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/pgrep")
        process.arguments = ["-f", pattern]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let ourselves = getpid()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 != ourselves }
    }

    /// Ask the kernel directly rather than parsing `lsof`.
    ///
    /// SO_REUSEADDR is essential, not incidental: this check must be exactly as
    /// permissive as Go's `net.Listen`, which mihomo uses. Without it, a client
    /// that leaks its connection (Chrome does) leaves mihomo's side of the socket
    /// in FIN_WAIT_2 holding the port, a plain bind fails EADDRINUSE, and Yami
    /// refuses to start a core over a port mihomo could have bound fine.
    /// A real LISTEN still fails the check, which is the case worth catching.
    static func isPortAvailable(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return true }
        defer { close(fd) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &addr) { raw in
            raw.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bound == 0
    }
}
