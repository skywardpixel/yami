import Foundation
import Yams

enum ConfigError: LocalizedError {
    case notYAML
    case notAConfig
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notYAML: "Response was not valid YAML"
        case .notAConfig: "No proxies in the downloaded config"
        case .validationFailed(let detail): detail
        }
    }
}

/// Turns provider YAML into the config Yami actually runs.
///
/// The provider is trusted for `proxies`, `proxy-groups` and `rules`. Everything
/// that decides how Yami itself reaches the core is overridden, because those
/// keys are contracts between the app and the process it supervises.
enum ConfigWriter {
    static var overrides: [String: Any] {[
        "mixed-port": Defaults.mixedPort,  // one port serving both HTTP and SOCKS5
        "allow-lan": false,                 // never expose the proxy to the network
        "mode": "rule",
        "log-level": "warning",
        "external-controller": "",          // the unix socket is the only API
    ]}

    /// Extra listeners and controllers a provider might set that would either
    /// bind ports we never told the user about or fight with our own socket.
    static let removed = [
        "port", "socks-port", "redir-port", "tproxy-port",
        "external-controller-tls", "external-controller-unix",
        "external-controller-pipe", "secret", "external-ui",
    ]

    static func render(subscription yaml: String) throws -> String {
        guard let loaded = try? Yams.load(yaml: yaml) else { throw ConfigError.notYAML }
        guard var config = loaded as? [String: Any] else { throw ConfigError.notYAML }

        // A provider handing back an error page or a login redirect parses as
        // *something*; requiring proxies is what actually catches that.
        guard let proxies = config["proxies"] as? [Any], !proxies.isEmpty else {
            throw ConfigError.notAConfig
        }

        for key in removed { config.removeValue(forKey: key) }
        for (key, value) in overrides { config[key] = value }

        return try Yams.dump(object: config)
    }

    /// Stage, validate with the core's own parser, then swap atomically. This is
    /// why a bad subscription can never take a working core down.
    static func install(_ rendered: String) throws {
        try rendered.write(to: Paths.stagedConfig, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: Paths.stagedConfig) }

        if let failure = validate(Paths.stagedConfig) {
            throw ConfigError.validationFailed(failure)
        }
        guard rename(Paths.stagedConfig.path, Paths.config.path) == 0 else {
            throw ConfigError.validationFailed("Could not replace config.yaml")
        }
    }

    /// Returns a failure message, or nil if `mihomo -t` accepted the file.
    private static func validate(_ url: URL) -> String? {
        let process = Process()
        process.executableURL = Paths.mihomo
        process.arguments = ["-t", "-d", Paths.support.path, "-f", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do { try process.run() } catch { return "Could not run mihomo: \(error.localizedDescription)" }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }

        let text = String(decoding: output, as: UTF8.self)
        let line = text.split(separator: "\n").last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return line.map(String.init) ?? "Config rejected by mihomo"
    }
}
