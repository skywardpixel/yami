import Foundation

/// Where traffic goes. Yami is opinionated here: the subscription supplies
/// nodes, Yami supplies routing.
///
/// Providers commonly ship a single `MATCH` rule and nothing else, so there is
/// rarely any routing to preserve. Rather than a rule editor, there are two
/// positions — a maintained public rule set, or everything through the proxy.
///
/// Rules come from github.com/Loyalsoldier/clash-rules.
enum Routing: String, CaseIterable, Identifiable, Sendable {
    /// Whatever the provider shipped, rules and rule-providers alike. Often a
    /// bare `MATCH`, which makes it equivalent to `global`.
    case subscription
    /// Loyalsoldier: proxy by default, with mainland China, LAN, Apple and
    /// iCloud going direct and known ad and tracker hosts rejected outright.
    case rules
    /// Everything through the proxy, no exceptions.
    case global

    nonisolated var id: String { rawValue }

    var label: String {
        switch self {
        case .subscription: "Subscription"
        case .rules: "Loyalsoldier"
        case .global: "Global"
        }
    }

    var detail: String {
        switch self {
        case .subscription: "Use the rules your provider ships, unchanged"
        case .rules: "Mainland China and LAN direct, ads blocked, everything else proxied"
        case .global: "Send all traffic through the proxy"
        }
    }

    /// `global` is deliberately *not* mihomo's `mode: global`. That routes via
    /// the GLOBAL selector, whose selection defaults to DIRECT and does not
    /// persist — switching to it would silently send everything direct. A
    /// single `MATCH` rule says exactly what it does and survives a restart.
    /// Nil means "leave the provider's rules alone".
    func rules(routingThrough policy: String) -> String? {
        switch self {
        case .subscription:
            return nil
        case .global:
            return "rules:\n  - MATCH,\(policy)"
        case .rules:
            return Self.ruleBlock
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.hasSuffix(",PROXY") ? $0.dropLast("PROXY".count) + policy : $0 }
                .joined(separator: "\n")
        }
    }

    /// Only Loyalsoldier needs the external lists fetched.
    var needsProviders: Bool { self == .rules }

    /// Fetched by the core at runtime and refreshed daily. Pinned to the
    /// upstream release branch rather than a commit: staying current is the
    /// point of using a maintained list.
    static let providers = """
rule-providers:
  reject:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/reject.txt"
    path: ./ruleset/reject.yaml
    interval: 86400

  icloud:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/icloud.txt"
    path: ./ruleset/icloud.yaml
    interval: 86400

  apple:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/apple.txt"
    path: ./ruleset/apple.yaml
    interval: 86400

  google:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/google.txt"
    path: ./ruleset/google.yaml
    interval: 86400

  proxy:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/proxy.txt"
    path: ./ruleset/proxy.yaml
    interval: 86400

  direct:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/direct.txt"
    path: ./ruleset/direct.yaml
    interval: 86400

  private:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/private.txt"
    path: ./ruleset/private.yaml
    interval: 86400

  gfw:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/gfw.txt"
    path: ./ruleset/gfw.yaml
    interval: 86400

  tld-not-cn:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/tld-not-cn.txt"
    path: ./ruleset/tld-not-cn.yaml
    interval: 86400

  telegramcidr:
    type: http
    behavior: ipcidr
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/telegramcidr.txt"
    path: ./ruleset/telegramcidr.yaml
    interval: 86400

  cncidr:
    type: http
    behavior: ipcidr
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/cncidr.txt"
    path: ./ruleset/cncidr.yaml
    interval: 86400

  lancidr:
    type: http
    behavior: ipcidr
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/lancidr.txt"
    path: ./ruleset/lancidr.yaml
    interval: 86400

  applications:
    type: http
    behavior: classical
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/applications.txt"
    path: ./ruleset/applications.yaml
    interval: 86400
"""

    private static let ruleBlock = """
rules:
  - RULE-SET,applications,DIRECT
  - DOMAIN,clash.razord.top,DIRECT
  - DOMAIN,yacd.haishan.me,DIRECT
  - RULE-SET,private,DIRECT
  - RULE-SET,reject,REJECT
  - RULE-SET,icloud,DIRECT
  - RULE-SET,apple,DIRECT
  - RULE-SET,google,PROXY
  - RULE-SET,proxy,PROXY
  - RULE-SET,direct,DIRECT
  - RULE-SET,lancidr,DIRECT
  - RULE-SET,cncidr,DIRECT
  - RULE-SET,telegramcidr,PROXY
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
"""
}
