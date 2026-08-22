import Foundation

enum CoreState: Equatable {
    case stopped
    case starting
    case running(port: Int)
    /// Carries the last meaningful line the core logged before dying.
    case exited(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isBusy: Bool { self == .starting }
}
