import Foundation

enum Versions {
    static var app: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// Asks the binary Yami would actually run, rather than hardcoding a number
    /// that drifts the moment the core is bundled, upgraded, or falls back to
    /// Homebrew. Blocking: call off the main actor.
    static func readCore() -> String? {
        let process = Process()
        process.executableURL = Paths.mihomo
        process.arguments = ["-v"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parseCore(String(decoding: data, as: UTF8.self))
    }

    /// mihomo prints `Mihomo Meta v1.19.30 darwin arm64 with go1.26.6 …`, and
    /// the Homebrew build prints the same without the `v`. Pull out the first
    /// thing shaped like a version and normalise it.
    static func parseCore(_ output: String) -> String? {
        guard let first = output.split(separator: "\n").first else { return nil }
        for token in first.split(separator: " ") {
            let candidate = token.hasPrefix("v") ? String(token.dropFirst()) : String(token)
            let parts = candidate.split(separator: ".")
            guard parts.count >= 2,
                  parts.allSatisfy({ $0.allSatisfy(\.isNumber) })
            else { continue }
            return candidate
        }
        return nil
    }
}
