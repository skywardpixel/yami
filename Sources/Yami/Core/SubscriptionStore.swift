import Foundation
import Observation

/// The one subscription. Fetches it, renders it, installs it — and remembers
/// nothing else.
@MainActor
@Observable
final class SubscriptionStore {
    var url: String {
        didSet { Self.store.set(url, forKey: Keys.url) }
    }
    private(set) var lastUpdated: Date?
    private(set) var error: String?
    private(set) var isUpdating = false

    private enum Keys {
        static let url = "subscriptionURL"
        static let lastUpdated = "subscriptionLastUpdated"
    }

    /// Test seam, paired with `Paths`: an instance launched under `YAMI_HOME`
    /// keeps its settings in a throwaway domain, so the integration checks never
    /// touch — or momentarily blank — the real subscription.
    private static let store: UserDefaults = {
        guard ProcessInfo.processInfo.environment["YAMI_HOME"]?.isEmpty == false else {
            return .standard
        }
        return UserDefaults(suiteName: "dev.yami.verify") ?? .standard
    }()

    private static let refreshInterval: TimeInterval = 24 * 60 * 60

    init() {
        url = Self.store.string(forKey: Keys.url) ?? ""
        let stamp = Self.store.double(forKey: Keys.lastUpdated)
        lastUpdated = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    var hasConfig: Bool { FileManager.default.fileExists(atPath: Paths.config.path) }

    var needsRefresh: Bool {
        guard !url.isEmpty else { return false }
        guard let lastUpdated else { return true }
        return Date().timeIntervalSince(lastUpdated) > Self.refreshInterval
    }

    /// Returns true if a new config was installed.
    @discardableResult
    func update() async -> Bool {
        let target = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let requestURL = URL(string: target), requestURL.scheme?.hasPrefix("http") == true else {
            error = "Not a valid URL"
            return false
        }

        isUpdating = true
        error = nil
        defer { isUpdating = false }

        do {
            let yaml = try await Self.fetch(requestURL)
            let rendered = try ConfigWriter.render(subscription: yaml)
            try ConfigWriter.install(rendered)
            lastUpdated = Date()
            Self.store.set(lastUpdated!.timeIntervalSince1970, forKey: Keys.lastUpdated)
            return true
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private static func fetch(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        // Providers gate their config on a recognised client UA and will hand a
        // browser UA an HTML dashboard page instead of YAML.
        request.setValue("mihomo/1.19.30", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ConfigError.validationFailed("Server returned HTTP \(http.statusCode)")
        }
        return String(decoding: data, as: UTF8.self)
    }
}
