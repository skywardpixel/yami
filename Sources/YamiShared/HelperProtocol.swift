import Foundation

public enum HelperInfo {
    public static let machServiceName = "dev.yami.helper"
    public static let plistName = "dev.yami.helper.plist"

    /// The one place the signing team appears. Changing Apple developer account
    /// — enrolling in the paid programme, for instance — changes this, and the
    /// helper will refuse every connection until it matches the certificate the
    /// app is actually signed with.
    ///
    /// Not a secret: it is embedded in every signed binary and readable by
    /// anyone holding a copy of the app.
    public static let teamID = "AU534DT7GN"

    /// The helper runs as root with an open Mach service, so "who is calling"
    /// is the entire security boundary. Pin both the identifier and the team:
    /// identifier alone would accept anything ad-hoc signed with that name.
    public static let clientRequirement = requirement(for: "dev.yami")

    /// The mirror of the above: the app verifies the daemon it connects to, so
    /// a hijacked Mach name cannot impersonate the helper.
    public static let helperRequirement = requirement(for: "dev.yami.helper")

    private static func requirement(for identifier: String) -> String {
        """
        identifier "\(identifier)" \
        and anchor apple generic \
        and certificate leaf[subject.OU] = "\(teamID)"
        """
    }

    /// Bypassed regardless of the proxy: loopback, link-local, and the private
    /// ranges. 100.64.0.0/10 keeps Tailscale working; 17.0.0.0/8 is Apple's.
    public static let bypassList = [
        "127.0.0.1", "localhost", "*.local",
        "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
        "100.64.0.0/10", "17.0.0.0/8",
    ]
}

@objc public protocol YamiHelperProtocol {
    /// Replies with an error message, or nil on success.
    func setProxy(enabled: Bool, port: Int, reply: @escaping @Sendable (String?) -> Void)
    func proxyState(reply: @escaping @Sendable (Bool) -> Void)
}
