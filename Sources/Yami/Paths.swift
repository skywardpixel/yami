import Foundation

enum Defaults {
    /// One port serving both HTTP and SOCKS5. Not configurable: a port picker is
    /// a setting users touch once and then forget they changed.
    static let mixedPort = 7890
}

enum Paths {
    /// Test seam. `scripts/verify.sh` redirects every piece of state here so the
    /// integration checks cannot touch the real config, cache, or running core.
    private static let override = ProcessInfo.processInfo.environment["YAMI_HOME"]
        .flatMap { $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory) }

    /// mihomo's `-d` directory. It owns everything in here: our generated
    /// config, its own caches, geoip databases, and the API socket.
    static let support = override ?? FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Yami", directoryHint: .isDirectory)

    static let config = support.appending(path: "config.yaml")
    /// The provider's YAML as downloaded. Kept so routing can be changed
    /// without asking the provider for the same file again.
    static let rawSubscription = support.appending(path: "subscription.yaml")
    static let stagedConfig = support.appending(path: "config.yaml.new")
    static let socket = support.appending(path: "api.sock")

    static let logDirectory = override ?? FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/Yami", directoryHint: .isDirectory)
    static let log = logDirectory.appending(path: "core.log")

    /// Development: the Homebrew binary. A distributable build copies mihomo
    /// into Contents/MacOS and this reads from Bundle.main instead.
    static var mihomo: URL {
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "mihomo") { return bundled }
        return URL(filePath: "/opt/homebrew/bin/mihomo")
    }

    /// The subscription URL is a credential, but config.yaml next door already
    /// holds every node's password in plaintext — so lock the directory down
    /// rather than pretending the URL alone deserves the Keychain.
    static func createDirectories() throws {
        for dir in [support, logDirectory] {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }
}
