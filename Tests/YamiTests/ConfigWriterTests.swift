import Foundation
import Testing
import Yams
@testable import Yami

/// `render` is the security boundary between a provider's YAML and the core we
/// supervise: it decides which ports get opened and whether the control API is
/// exposed. These cases mirror the hostile config used to verify it by hand.
@Suite("ConfigWriter")
struct ConfigWriterTests {
    /// A provider config that sets everything we override or strip, including
    /// a control API bound to every interface.
    static let hostile = """
        port: 7777
        socks-port: 7778
        redir-port: 7779
        mixed-port: 9999
        allow-lan: true
        mode: global
        log-level: debug
        secret: "provider-secret"
        external-controller: 0.0.0.0:9090
        external-ui: /tmp/ui
        proxies:
          - {name: "node-a", type: ss, server: 192.0.2.10, port: 8388, cipher: aes-256-gcm, password: "x"}
        proxy-groups:
          - {name: "PROXY", type: select, proxies: ["node-a", "DIRECT"]}
        rules:
          - DOMAIN-SUFFIX,example.com,PROXY
          - MATCH,DIRECT
        """

    private func rendered(_ yaml: String) throws -> [String: Any] {
        let output = try ConfigWriter.render(subscription: yaml)
        return try #require(try Yams.load(yaml: output) as? [String: Any])
    }

    private func error(_ yaml: String) -> ConfigError? {
        do {
            _ = try ConfigWriter.render(subscription: yaml)
            return nil
        } catch let error as ConfigError {
            return error
        } catch {
            return nil
        }
    }

    @Test("overrides the keys that define how Yami reaches the core")
    func overrides() throws {
        let config = try rendered(Self.hostile)
        #expect(config["mixed-port"] as? Int == Defaults.mixedPort)
        #expect(config["allow-lan"] as? Bool == false)
        #expect(config["mode"] as? String == "rule")
        #expect(config["log-level"] as? String == "warning")
    }

    /// The one that matters most: a provider pointing the control API at
    /// 0.0.0.0 would expose it on every interface.
    @Test("disables a provider's TCP control API")
    func externalControllerDisabled() throws {
        let config = try rendered(Self.hostile)
        #expect(config["external-controller"] as? String == "")
    }

    @Test("strips listeners and controllers the user was never told about")
    func stripsExtraListeners() throws {
        let config = try rendered(Self.hostile)
        for key in ConfigWriter.removed {
            #expect(config[key] == nil, "\(key) survived rendering")
        }
    }

    @Test("passes the provider's own proxies, groups and rules through untouched")
    func preservesProviderContent() throws {
        let config = try rendered(Self.hostile)
        #expect((config["proxies"] as? [Any])?.count == 1)
        #expect((config["proxy-groups"] as? [Any])?.count == 1)
        #expect(config["rules"] as? [String] == [
            "DOMAIN-SUFFIX,example.com,PROXY",
            "MATCH,DIRECT",
        ])
    }

    /// Providers gate their config behind a login and hand a browser a page
    /// instead of YAML. That page must never reach the core.
    @Test("rejects an HTML login page")
    func rejectsHTML() {
        let html = """
            <!DOCTYPE html><html><head><title>Sign in</title></head>
            <body><h1>Please log in</h1></body></html>
            """
        #expect(error(html) != nil)
    }

    /// Valid YAML that is not a config parses fine — requiring proxies is what
    /// actually catches it.
    @Test("rejects YAML with no proxies")
    func rejectsProxylessYAML() {
        guard case .notAConfig = error("message: subscription expired") else {
            Issue.record("expected .notAConfig")
            return
        }
    }

    @Test("rejects an empty proxy list")
    func rejectsEmptyProxies() {
        guard case .notAConfig = error("proxies: []\nrules: []") else {
            Issue.record("expected .notAConfig")
            return
        }
    }
}

/// The refresh policy decides whether the app quietly serves a stale node list.
/// It ran only at launch until a menu bar app's actual lifetime made that a bug.
@Suite("Refresh policy")
struct RefreshPolicyTests {
    private let day = SubscriptionStore.refreshInterval

    @Test("no URL means nothing to refresh")
    func noURL() {
        #expect(SubscriptionStore.needsRefresh(url: "", lastUpdated: nil) == false)
        #expect(SubscriptionStore.needsRefresh(url: "   ", lastUpdated: Date()) == false)
    }

    @Test("a URL that has never been fetched needs a refresh")
    func neverFetched() {
        #expect(SubscriptionStore.needsRefresh(url: "https://example.com/sub", lastUpdated: nil))
    }

    @Test("a recent fetch is left alone")
    func recentFetch() {
        let now = Date()
        #expect(SubscriptionStore.needsRefresh(
            url: "https://example.com/sub",
            lastUpdated: now.addingTimeInterval(-day + 60),
            now: now
        ) == false)
    }

    @Test("a fetch older than the interval is refreshed")
    func staleFetch() {
        let now = Date()
        #expect(SubscriptionStore.needsRefresh(
            url: "https://example.com/sub",
            lastUpdated: now.addingTimeInterval(-day - 60),
            now: now
        ))
    }

    /// A Mac that slept for a week wakes with a clock far past the interval.
    @Test("a long sleep triggers a refresh on wake")
    func afterLongSleep() {
        let now = Date()
        #expect(SubscriptionStore.needsRefresh(
            url: "https://example.com/sub",
            lastUpdated: now.addingTimeInterval(-day * 7),
            now: now
        ))
    }
}
