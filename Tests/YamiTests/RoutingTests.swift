import Foundation
import Testing
import Yams
@testable import Yami

/// Yami supplies the routing, so getting the policy substitution wrong would
/// send every packet somewhere unintended — or nowhere.
@Suite("Routing")
struct RoutingTests {
    static let subscription = """
        proxies:
          - {name: "node-a", type: ss, server: 192.0.2.10, port: 8388, cipher: aes-256-gcm, password: "x"}
        proxy-groups:
          - {name: "MyGroup", type: select, proxies: ["node-a", "DIRECT"]}
          - {name: "MyGroup Auto", type: url-test, proxies: ["node-a"]}
        rules:
          - MATCH,MyGroup
        """

    private func rendered(_ routing: Routing) throws -> [String: Any] {
        let output = try ConfigWriter.render(subscription: Self.subscription, routing: routing)
        return try #require(try Yams.load(yaml: output) as? [String: Any])
    }

    // MARK: - Which group counts as "the proxy"

    @Test("takes the policy from the subscription's own MATCH rule")
    func policyFromMatch() {
        let config: [String: Any] = ["rules": ["DOMAIN,x.com,Other", "MATCH,MyGroup"]]
        #expect(ConfigWriter.primaryPolicy(in: config) == "MyGroup")
    }

    /// A provider that defaults to direct still has a group worth routing to.
    @Test("falls back to the first group when MATCH is DIRECT")
    func policyFallsBack() {
        let config: [String: Any] = [
            "rules": ["MATCH,DIRECT"],
            "proxy-groups": [["name": "Fallback"], ["name": "Second"]],
        ]
        #expect(ConfigWriter.primaryPolicy(in: config) == "Fallback")
    }

    @Test("no groups at all means nothing to route through")
    func policyMissing() {
        #expect(ConfigWriter.primaryPolicy(in: ["rules": ["MATCH,DIRECT"]]) == nil)
    }

    // MARK: - Rendering

    @Test("global sends everything to the subscription's group")
    func globalRoutesToGroup() throws {
        let config = try rendered(.global)
        #expect(config["rules"] as? [String] == ["MATCH,MyGroup"])
        #expect(config["rule-providers"] == nil, "global needs no external lists")
    }

    /// The published rules name a policy called PROXY, which this subscription
    /// does not define. Leaving it unrewritten would fail to load.
    @Test("rules mode rewrites PROXY to the subscription's group")
    func rulesRewritePolicy() throws {
        let config = try rendered(.rules)
        let rules = try #require(config["rules"] as? [String])
        #expect(!rules.contains { $0.hasSuffix(",PROXY") }, "PROXY survived the rewrite")
        #expect(rules.contains("MATCH,MyGroup"))
        #expect(rules.contains { $0.hasSuffix(",MyGroup") })
    }

    @Test("rules mode keeps DIRECT and REJECT targets alone")
    func rulesKeepBuiltins() throws {
        let rules = try #require(try rendered(.rules)["rules"] as? [String])
        #expect(rules.contains { $0.hasSuffix(",DIRECT") })
        #expect(rules.contains { $0.hasSuffix(",REJECT") })
    }

    @Test("rules mode ships the external lists it depends on")
    func rulesIncludeProviders() throws {
        let providers = try #require(try rendered(.rules)["rule-providers"] as? [String: Any])
        #expect(providers.count == 13)
        for name in ["reject", "cncidr", "lancidr", "gfw", "applications"] {
            #expect(providers[name] != nil, "\(name) missing")
        }
    }

    /// Every RULE-SET the rules reference must have a provider defining it, or
    /// the core rejects the config.
    @Test("every RULE-SET referenced is defined")
    func everyRuleSetIsDefined() throws {
        let config = try rendered(.rules)
        let rules = try #require(config["rules"] as? [String])
        let providers = try #require(config["rule-providers"] as? [String: Any])
        for rule in rules where rule.hasPrefix("RULE-SET,") {
            let name = String(rule.split(separator: ",")[1])
            #expect(providers[name] != nil, "rule references undefined set: \(name)")
        }
    }

    @Test("switching routing leaves the nodes untouched")
    func nodesSurvive() throws {
        for routing in Routing.allCases {
            let config = try rendered(routing)
            #expect((config["proxies"] as? [Any])?.count == 1)
            #expect((config["proxy-groups"] as? [Any])?.count == 2)
        }
    }

    // MARK: - Leaving the provider alone

    @Test("subscription mode keeps the provider's own rules")
    func subscriptionKeepsRules() throws {
        let config = try rendered(.subscription)
        #expect(config["rules"] as? [String] == ["MATCH,MyGroup"])
        #expect(config["rule-providers"] == nil)
    }

    /// A provider that ships its own rule-providers must keep them.
    @Test("subscription mode keeps the provider's own rule-providers")
    func subscriptionKeepsProviders() throws {
        let yaml = Self.subscription + """

            rule-providers:
              theirs:
                type: http
                behavior: domain
                url: "https://example.com/theirs.txt"
                path: ./theirs.yaml
                interval: 86400
            """
        let output = try ConfigWriter.render(subscription: yaml, routing: .subscription)
        let config = try #require(try Yams.load(yaml: output) as? [String: Any])
        let providers = try #require(config["rule-providers"] as? [String: Any])
        #expect(providers["theirs"] != nil)
        #expect(providers.count == 1, "Yami's lists must not be mixed in")
    }

    /// Overriding routing needs somewhere to send traffic; without a group
    /// there is nothing to substitute and failing loudly beats a silent MATCH.
    @Test("overriding routing with no group to route through fails")
    func overrideWithoutGroupFails() {
        let bare = """
            proxies:
              - {name: "n", type: ss, server: 192.0.2.1, port: 1, cipher: aes-256-gcm, password: "x"}
            """
        for routing in [Routing.rules, .global] {
            var caught: ConfigError?
            do { _ = try ConfigWriter.render(subscription: bare, routing: routing) }
            catch let e as ConfigError { caught = e } catch {}
            guard case .noPolicy = caught else {
                Issue.record("expected .noPolicy for \(routing)"); continue
            }
        }
    }

    @Test("subscription mode works even with no group defined")
    func subscriptionNeedsNoGroup() throws {
        let bare = """
            proxies:
              - {name: "n", type: ss, server: 192.0.2.1, port: 1, cipher: aes-256-gcm, password: "x"}
            """
        #expect(throws: Never.self) {
            try ConfigWriter.render(subscription: bare, routing: .subscription)
        }
    }
}
