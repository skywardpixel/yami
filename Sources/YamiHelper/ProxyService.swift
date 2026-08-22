import Foundation
import SystemConfiguration
import YamiShared

enum ProxyError: LocalizedError {
    case noPreferences, noNetworkSet, commitFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPreferences: "Could not open network preferences"
        case .noNetworkSet: "No active network configuration"
        case .commitFailed(let stage): "Could not \(stage) network preferences"
        }
    }
}

/// The privileged half. Runs as root; touches nothing but the proxy keys of the
/// current network set.
final class ProxyService: NSObject, YamiHelperProtocol, @unchecked Sendable {
    static let shared = ProxyService()

    private let lock = NSLock()
    /// Whether *this helper* turned the proxy on. The difference matters: on
    /// losing the app we undo our own change, but never a setting the user made.
    private var enabledByUs = false

    func setProxy(enabled: Bool, port: Int, reply: @escaping @Sendable (String?) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try apply(enabled: enabled, port: port)
            enabledByUs = enabled
            reply(nil)
        } catch {
            reply(error.localizedDescription)
        }
    }

    func proxyState(reply: @escaping @Sendable (Bool) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        reply(currentlyEnabled())
    }

    /// Called when the app's connection drops — including a crash. This is what
    /// keeps a dead proxy from taking the machine offline.
    func disableIfEnabledByUs() {
        lock.lock()
        defer { lock.unlock() }
        guard enabledByUs else { return }
        try? apply(enabled: false, port: 0)
        enabledByUs = false
    }

    // MARK: - SystemConfiguration

    /// One commit reconfigures every interface atomically. Shelling out to
    /// `networksetup` would mean N separate reconfigurations, and a root daemon
    /// running shell commands built from caller input is a footgun.
    private func apply(enabled: Bool, port: Int) throws {
        guard let prefs = SCPreferencesCreate(nil, "Yami" as CFString, nil) else {
            throw ProxyError.noPreferences
        }
        guard let set = SCNetworkSetCopyCurrent(prefs),
              let services = SCNetworkSetCopyServices(set) as? [SCNetworkService] else {
            throw ProxyError.noNetworkSet
        }

        for service in services {
            guard SCNetworkServiceGetEnabled(service),
                  let proxies = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies)
            else { continue }

            // Read-modify-write: a service may carry proxy settings we do not
            // own (FTP passive, PAC URLs), and clobbering them would be rude.
            var config = (SCNetworkProtocolGetConfiguration(proxies) as? [String: Any]) ?? [:]

            if enabled {
                for (enable, proxy, portKey) in Self.proxyKeys {
                    config[enable] = 1
                    config[proxy] = "127.0.0.1"
                    config[portKey] = port
                }
                config[kSCPropNetProxiesExceptionsList as String] = HelperInfo.bypassList
                config[kSCPropNetProxiesExcludeSimpleHostnames as String] = 1
                // A configured PAC file outranks manual settings, so a stale one
                // would silently win over everything we just set.
                config[kSCPropNetProxiesProxyAutoConfigEnable as String] = 0
            } else {
                for (enable, _, _) in Self.proxyKeys {
                    config[enable] = 0
                }
            }

            SCNetworkProtocolSetConfiguration(proxies, config as CFDictionary)
        }

        guard SCPreferencesCommitChanges(prefs) else { throw ProxyError.commitFailed("save") }
        guard SCPreferencesApplyChanges(prefs) else { throw ProxyError.commitFailed("apply") }
    }

    private func currentlyEnabled() -> Bool {
        guard let prefs = SCPreferencesCreate(nil, "Yami" as CFString, nil),
              let set = SCNetworkSetCopyCurrent(prefs),
              let services = SCNetworkSetCopyServices(set) as? [SCNetworkService]
        else { return false }

        for service in services {
            guard SCNetworkServiceGetEnabled(service),
                  let proxies = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies),
                  let config = SCNetworkProtocolGetConfiguration(proxies) as? [String: Any]
            else { continue }
            if (config[kSCPropNetProxiesHTTPEnable as String] as? Int) == 1 { return true }
        }
        return false
    }

    private static let proxyKeys: [(String, String, String)] = [
        (kSCPropNetProxiesHTTPEnable as String, kSCPropNetProxiesHTTPProxy as String, kSCPropNetProxiesHTTPPort as String),
        (kSCPropNetProxiesHTTPSEnable as String, kSCPropNetProxiesHTTPSProxy as String, kSCPropNetProxiesHTTPSPort as String),
        (kSCPropNetProxiesSOCKSEnable as String, kSCPropNetProxiesSOCKSProxy as String, kSCPropNetProxiesSOCKSPort as String),
    ]
}
