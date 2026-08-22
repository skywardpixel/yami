import Foundation
import Observation
import ServiceManagement
import YamiShared

/// Client half of the privileged helper. Owns one long-lived XPC connection:
/// the helper treats losing it as "the app is gone" and undoes the proxy, so
/// churning connections would churn the user's network settings.
@MainActor
@Observable
final class ProxyController {
    private(set) var isOn = false
    private(set) var error: String?

    @ObservationIgnored private var connection: NSXPCConnection?

    func setEnabled(_ on: Bool, port: Int) async {
        error = nil
        if on, let problem = await ensureHelper() {
            error = problem
            return
        }
        if let problem = await send(enabled: on, port: port) {
            error = problem
            // Do not claim a state we failed to reach.
            await refresh()
            return
        }
        isOn = on
    }

    func refresh() async {
        guard HelperInstaller.isEnabled else {
            isOn = false
            return
        }
        isOn = await withCheckedContinuation { continuation in
            let once = OnceBox(continuation)
            guard let helper = remote(onError: { _ in once.resume(false) }) else {
                once.resume(false)
                return
            }
            helper.proxyState { state in once.resume(state) }
        }
    }

    /// Called during app termination. The helper would undo the proxy anyway
    /// when the connection drops, but doing it explicitly means the network is
    /// already restored by the time the process exits.
    func disableForQuit(port: Int) {
        guard isOn, let helper = remote(onError: { _ in }) else { return }
        let done = DispatchSemaphore(value: 0)
        helper.setProxy(enabled: false, port: port) { _ in done.signal() }
        _ = done.wait(timeout: .now() + 2)
    }

    // MARK: - Plumbing

    private func ensureHelper() async -> String? {
        if HelperInstaller.isEnabled { return nil }
        do {
            try HelperInstaller.register()
        } catch {
            return "Could not install helper: \(error.localizedDescription)"
        }
        // Registration succeeds immediately but the daemon stays inert until the
        // user approves it in System Settings.
        return HelperInstaller.explanation(for: HelperInstaller.status)
    }

    private func send(enabled: Bool, port: Int) async -> String? {
        await withCheckedContinuation { continuation in
            let once = OnceBox(continuation)
            guard let helper = remote(onError: { once.resume($0) }) else {
                once.resume("Helper unavailable")
                return
            }
            helper.setProxy(enabled: enabled, port: port) { message in once.resume(message) }
        }
    }

    private func remote(onError: @escaping @Sendable (String) -> Void) -> YamiHelperProtocol? {
        if connection == nil {
            let new = NSXPCConnection(
                machServiceName: HelperInfo.machServiceName,
                options: .privileged
            )
            new.remoteObjectInterface = NSXPCInterface(with: YamiHelperProtocol.self)
            // The mirror of the helper's own check: verify the daemon we are
            // handing proxy settings to is really ours.
            new.setCodeSigningRequirement(HelperInfo.helperRequirement)
            new.invalidationHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            new.interruptionHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            new.resume()
            connection = new
        }
        return connection?.remoteObjectProxyWithErrorHandler { error in
            onError(error.localizedDescription)
        } as? YamiHelperProtocol
    }
}

/// XPC can deliver both a reply and an error for the same call; resuming a
/// continuation twice is a crash, so collapse them to the first one home.
private final class OnceBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
