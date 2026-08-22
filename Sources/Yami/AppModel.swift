import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let core = CoreController()
    let subscription = SubscriptionStore()
    let proxy = ProxyController()

    @ObservationIgnored private var terminationSignal: DispatchSourceSignal?

    init() {
        try? Paths.createDirectories()

        // Quitting via the menu or the Quit button.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutdown() }
        }

        // ...and quitting because macOS said so. SIGTERM's default disposition
        // kills the process outright, so willTerminate never runs — which
        // orphaned the core on every logout and shutdown until this was added.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.shutdown()
                NSApp.terminate(nil)
            }
        }
        source.resume()
        terminationSignal = source

        observeCoreState()
        Task { await launch() }
    }

    /// Must not orphan the core, and must not leave the machine pointed at a
    /// proxy port with nothing behind it. Idempotent: both exit paths call it,
    /// and the SIGTERM path calls it again by way of `willTerminate`.
    private func shutdown() {
        proxy.disableForQuit(port: Defaults.mixedPort)
        core.terminateForQuit()
    }

    private func launch() async {
        if subscription.hasConfig { core.start() }
        await proxy.refresh()
        if subscription.needsRefresh { await update() }
    }

    // MARK: - Actions

    func update() async {
        if await subscription.update() {
            core.applyNewConfig()
        }
    }

    func toggleCore() {
        core.state.isRunning || core.state.isBusy ? core.stop() : core.start()
    }

    func setSystemProxy(_ on: Bool) async {
        await proxy.setEnabled(on, port: Defaults.mixedPort)
    }

    func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([Paths.log])
    }

    func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Safety interlock

    /// The system proxy is only ever as good as the core behind it. If the core
    /// stops — crashed, out of restarts, or switched off — a proxy left pointing
    /// at 7890 takes the whole machine offline, so it comes down with the core.
    private func observeCoreState() {
        withObservationTracking {
            _ = core.state
        } onChange: {
            // onChange fires before the new value lands; hop to read it.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.coreStateChanged()
                self.observeCoreState()
            }
        }
    }

    private func coreStateChanged() {
        switch core.state {
        case .stopped, .exited:
            // .starting is deliberately excluded: a config reload passes through
            // it, and flapping the proxy on every restart would be worse.
            if proxy.isOn {
                Task { await setSystemProxy(false) }
            }
        case .running, .starting:
            break
        }
    }

    // MARK: - Presentation

    /// The one place errors surface, in order of what most needs acting on.
    var statusText: String {
        if subscription.isUpdating { return "Updating subscription…" }
        if let error = proxy.error { return error }
        if let error = subscription.error { return "Update failed: \(error)" }
        switch core.state {
        case .stopped: return "Stopped"
        case .starting: return "Starting…"
        case .running(let port): return "Running · port \(port)"
        case .exited(let reason): return reason
        }
    }

    var statusColor: Color3 {
        if proxy.error != nil { return .amber }
        if subscription.error != nil { return .amber }
        switch core.state {
        case .running: return .green
        case .exited: return .red
        case .stopped, .starting: return .grey
        }
    }

    var lastUpdatedText: String {
        guard let date = subscription.lastUpdated else { return "Never updated" }
        return "Updated " + date.formatted(.relative(presentation: .named))
    }

    /// The proxy may only be switched on over a core that is actually serving.
    var canToggleProxy: Bool { core.state.isRunning || proxy.isOn }

    var canInteract: Bool { !subscription.isUpdating }

    enum Color3 { case green, red, amber, grey }
}
