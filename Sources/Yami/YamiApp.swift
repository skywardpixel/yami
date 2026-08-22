import SwiftUI

@main
struct YamiApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            let running = model.core.state.isRunning
            let proxied = model.proxy.isOn
            Image(nsImage: MenuBarIcon.image(coreRunning: running, proxyOn: proxied))
                .accessibilityLabel(MenuBarIcon.describe(coreRunning: running, proxyOn: proxied))
        }
        .menuBarExtraStyle(.window)

        // The app has no dock icon, so this only ever appears on request.
        Window("Mihomo Configuration", id: ConfigWindow.id) {
            ConfigView()
        }
        .defaultSize(width: 620, height: 700)
    }
}
