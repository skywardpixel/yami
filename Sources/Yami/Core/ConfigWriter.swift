import Foundation
import Yams

enum ConfigError: LocalizedError {
    case notYAML
    case notAConfig
    case noPolicy
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notYAML: "Response was not valid YAML"
        case .notAConfig: "No proxies in the downloaded config"
        case .noPolicy: "Subscription defines no proxy group to route through"
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

    /// The group a subscription routes through — what "the proxy" means for
    /// this provider. Taken from its own MATCH rule, since that is where a
    /// provider states its intent, falling back to the first group it defines.
    static func primaryPolicy(in config: [String: Any]) -> String? {
        if let rules = config["rules"] as? [String] {
            for rule in rules.reversed() {
                let parts = rule.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard parts.count >= 2, parts[0].uppercased() == "MATCH" else { continue }
                if parts[1] != "DIRECT", parts[1] != "REJECT" { return parts[1] }
            }
        }
        if let groups = config["proxy-groups"] as? [[String: Any]] {
            for group in groups {
                if let name = group["name"] as? String { return name }
            }
        }
        return nil
    }

    static func render(subscription yaml: String, routing: Routing) throws -> String {
        guard let loaded = try? Yams.load(yaml: yaml) else { throw ConfigError.notYAML }
        guard var config = loaded as? [String: Any] else { throw ConfigError.notYAML }

        // A provider handing back an error page or a login redirect parses as
        // *something*; requiring proxies is what actually catches that.
        guard let proxies = config["proxies"] as? [Any], !proxies.isEmpty else {
            throw ConfigError.notAConfig
        }

        for key in removed { config.removeValue(forKey: key) }
        for (key, value) in overrides { config[key] = value }

        // Routing is the one thing Yami will override, and only when asked:
        // `.subscription` leaves the provider's rules and rule-providers alone.
        if let policy = primaryPolicy(in: config),
           let rules = routing.rules(routingThrough: policy) {
            config["rules"] = try block(rules, key: "rules")
            if routing.needsProviders {
                config["rule-providers"] = try block(Routing.providers, key: "rule-providers")
            } else {
                config.removeValue(forKey: "rule-providers")
            }
        } else if routing != .subscription {
            throw ConfigError.noPolicy
        }

        return try Yams.dump(object: config)
    }

    /// Parses one of the embedded YAML fragments and pulls out its top-level
    /// value, so the rules and providers stay readable as YAML in the source.
    private static func block(_ yaml: String, key: String) throws -> Any {
        guard let loaded = try? Yams.load(yaml: yaml) as? [String: Any],
              let value = loaded[key]
        else { throw ConfigError.notYAML }
        return value
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
