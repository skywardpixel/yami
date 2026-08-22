import Foundation
import ServiceManagement
import YamiShared

@MainActor
enum HelperInstaller {
    static var status: SMAppService.Status {
        SMAppService.daemon(plistName: HelperInfo.plistName).status
    }

    static var isEnabled: Bool { status == .enabled }

    /// Registration is deliberately lazy — triggered by the first System Proxy
    /// toggle, never at launch. A user who only ever runs the core should not be
    /// asked to approve a root daemon.
    static func register() throws {
        try SMAppService.daemon(plistName: HelperInfo.plistName).register()
    }

    /// What to tell the user for a status that is not `.enabled`.
    static func explanation(for status: SMAppService.Status) -> String? {
        switch status {
        case .enabled: nil
        case .requiresApproval: "Approve Yami in Login Items"
        case .notRegistered: "Helper not installed"
        case .notFound: "Helper missing from the app bundle"
        @unknown default: "Helper unavailable"
        }
    }
}
