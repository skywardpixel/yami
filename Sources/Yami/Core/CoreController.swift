import Foundation
import Observation

/// Owns the mihomo process: spawn, readiness, restart-on-config-change, and a
/// bounded restart policy for unexpected exits.
@MainActor
@Observable
final class CoreController {
    private(set) var state: CoreState = .stopped

    /// Set when the user pressed the power toggle off, so a deliberate stop is
    /// never mistaken for a crash and restarted.
    private var stoppedByUser = false
    private var process: Process?
    private var sink: LogSink?
    private var restartAttempts = 0
    private var generation = 0

    private static let maxRestarts = 3

    var canStart: Bool { FileManager.default.fileExists(atPath: Paths.config.path) }

    func start() {
        guard !state.isRunning, !state.isBusy else { return }
        guard canStart else {
            state = .exited("No subscription configured")
            return
        }
        stoppedByUser = false
        restartAttempts = 0  // a manual start is a fresh beginning
        spawn()
    }

    func stop() {
        stoppedByUser = true
        restartAttempts = 0
        terminate()
        state = .stopped
    }

    /// Called after a new config lands. Restarts a live core, and starts one
    /// that never had a config to run — but respects a deliberate power-off.
    func applyNewConfig() {
        if state.isRunning || state.isBusy {
            terminate()
            restartAttempts = 0
            spawn()
        } else if !stoppedByUser {
            start()
        }
    }

    func terminateForQuit() {
        terminate()
    }

    // MARK: - Process lifecycle

    /// Pre-flight runs off the main actor: reaping an orphan can take a second,
    /// and the popover should stay responsive while it happens.
    private func spawn() {
        generation += 1
        let generation = self.generation
        state = .starting

        Task { [weak self] in
            let failure = await Task.detached(priority: .userInitiated) {
                PortGuard.preflight(port: Defaults.mixedPort)
            }.value
            guard let self, self.generation == generation else { return }
            guard let failure else {
                self.launchProcess(generation: generation)
                return
            }
            // A port conflict can be transient — a core we just terminated may
            // still be releasing sockets. Spend the normal restart budget before
            // giving up, rather than wedging until the user restarts the app.
            guard self.restartAttempts < Self.maxRestarts, !self.stoppedByUser else {
                self.state = .exited(failure)
                return
            }
            self.restartAttempts += 1
            try? await Task.sleep(for: .seconds(2))
            guard self.generation == generation else { return }
            self.spawn()
        }
    }

    private func launchProcess(generation: Int) {
        // A socket left behind by a crashed core makes mihomo fail to bind.
        try? FileManager.default.removeItem(at: Paths.socket)

        let sink = LogSink(url: Paths.log)
        self.sink = sink

        let process = Process()
        process.executableURL = Paths.mihomo
        process.arguments = [
            "-d", Paths.support.path,
            "-f", Paths.config.path,
            "-ext-ctl-unix", Paths.socket.path,
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            sink.write(data)
        }

        process.terminationHandler = { [weak self] finished in
            Task { @MainActor [weak self] in
                self?.processExited(status: finished.terminationStatus, generation: generation)
            }
        }

        do {
            try process.run()
        } catch {
            state = .exited("Could not launch mihomo: \(error.localizedDescription)")
            return
        }
        self.process = process

        Task { [weak self] in
            let ready = await Self.waitForReadiness(port: Defaults.mixedPort)
            guard let self, self.generation == generation else { return }
            // A core that died during the probe has already set .exited; do not
            // paper over that with a readiness failure.
            guard case .starting = self.state else { return }
            if ready {
                self.restartAttempts = 0
                self.state = .running(port: Defaults.mixedPort)
            } else {
                self.terminate()
                self.state = .exited(self.sink?.lastError() ?? "Core did not become ready")
            }
        }
    }

    private func processExited(status: Int32, generation: Int) {
        guard self.generation == generation else { return }  // superseded by a restart
        process = nil
        sink?.close()
        guard !stoppedByUser else { return }

        let reason = sink?.lastError() ?? "Core exited with status \(status)"
        if restartAttempts < Self.maxRestarts {
            restartAttempts += 1
            spawn()
        } else {
            state = .exited(reason)
        }
    }

    private func terminate() {
        generation += 1  // invalidate any in-flight readiness probe or exit handler
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process = nil
        sink?.close()
    }

    /// Ready means *serving*, not merely alive. The control socket answering
    /// `/version` proves the process started; only a connection to the mixed
    /// port proves the proxy a user's traffic will hit is actually up.
    private static func waitForReadiness(port: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(3)
        let socketPath = Paths.socket.path
        while Date() < deadline {
            let serving = await Task.detached(priority: .utility) {
                UnixSocketHTTP.get("/version", socketPath: socketPath) == 200
                    && PortGuard.canConnect(port: port)
            }.value
            if serving { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
}
