import Foundation

/// Streams the core's stdout/stderr to core.log while keeping the last few lines
/// in memory, so a crash can be explained in the status line without asking the
/// user to go read a file.
final class LogSink: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: FileHandle?
    private var recent: [String] = []
    private var partial = ""

    private static let ringSize = 20

    init(url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        try? handle?.seekToEnd()
    }

    func write(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        try? handle?.write(contentsOf: data)

        partial += String(decoding: data, as: UTF8.self)
        var lines = partial.components(separatedBy: "\n")
        partial = lines.removeLast()
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            recent.append(line)
        }
        if recent.count > Self.ringSize { recent.removeFirst(recent.count - Self.ringSize) }
    }

    /// The most useful line to show a user after an unexpected exit: mihomo puts
    /// the real cause on a level=fatal/error line, so prefer those.
    func lastError() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let interesting = recent.last { $0.contains("level=fatal") || $0.contains("level=error") }
        return (interesting ?? recent.last).map(Self.condense)
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        try? handle?.close()
        handle = nil
    }

    /// mihomo log lines are `time="..." level=fatal msg="..."` — the msg is the
    /// only part worth putting in a 280pt popover.
    private static func condense(_ line: String) -> String {
        guard let range = line.range(of: "msg=") else { return line }
        var message = String(line[range.upperBound...])
        if message.hasPrefix("\"") { message = String(message.dropFirst()) }
        if message.hasSuffix("\"") { message = String(message.dropLast()) }
        return message
    }
}
