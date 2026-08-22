import Foundation
import YamiShared

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        // The whole security boundary. Without this, any local process could
        // drive a root daemon. Non-throwing: a connection failing the
        // requirement is invalidated by XPC before it can call anything.
        connection.setCodeSigningRequirement(HelperInfo.clientRequirement)

        connection.exportedInterface = NSXPCInterface(with: YamiHelperProtocol.self)
        connection.exportedObject = ProxyService.shared
        connection.invalidationHandler = {
            // The app quit or crashed. Undo our own proxy change so the machine
            // is never left pointing at a port with nothing behind it.
            ProxyService.shared.disableIfEnabledByUs()
        }
        connection.resume()
        return true
    }
}

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: HelperInfo.machServiceName)
listener.delegate = delegate
listener.resume()
dispatchMain()
