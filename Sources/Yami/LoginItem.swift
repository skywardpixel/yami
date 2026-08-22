import Foundation
import ServiceManagement

/// Start Yami when the user logs in. Distinct from the privileged helper's
/// registration: this is the app itself, needs no approval prompt, and is what
/// makes a menu bar proxy app usable at all.
@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
