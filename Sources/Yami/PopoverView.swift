import SwiftUI

struct PopoverView: View {
    let model: AppModel

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var subscription = model.subscription

        VStack(alignment: .leading, spacing: 0) {
            // Three groups rather than a divider between every control:
            // what is running, what it is running, and the app itself.
            connection
            Divider().padding(.vertical, 10)
            subscriptionSection(url: $subscription.url)
            Divider().padding(.vertical, 10)
            application
        }
        .padding(12)
        .frame(width: 280)
        // Without a background of its own, a square-cornered backing shows
        // through behind the content — invisible in dark mode, obvious in
        // light, where it reads as a rectangle inside the rounded panel.
        // Anything that fills the frame inherits the panel's rounded clip.
        .background(.regularMaterial)
        // The only moment the user looks at these controls — and the system
        // proxy can be changed behind our back in System Settings.
        .task { await model.popoverAppeared() }
    }

    private var launchAtLoginRow: some View {
        switchRow(
            "Launch at Login",
            isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ),
            enabled: true,
            help: "Start Yami when you log in"
        )
    }

    // MARK: - Core

    /// The core and the proxy are both plain on/off state, so they get the same
    /// control. A power button next to a switch implied they were different
    /// kinds of thing.
    /// The core and the system proxy are one thought: is traffic being carried,
    /// and is anything using it.
    private var connection: some View {
        VStack(alignment: .leading, spacing: 8) {
            coreSection
            proxyRow
        }
    }

    /// Settings that belong to the app rather than to the connection, followed
    /// by the actions.
    private var application: some View {
        VStack(alignment: .leading, spacing: 8) {
            launchAtLoginRow
            actions
            about
        }
    }

    private var coreSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            switchRow(
                "Mihomo",
                isOn: Binding(
                    get: { model.core.state.isRunning || model.core.state.isBusy },
                    set: { _ in model.toggleCore() }
                ),
                enabled: model.core.canStart || model.core.state.isRunning,
                help: "Run the Mihomo core"
            )
            statusLine
        }
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(model.statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Proxy

    private var proxyRow: some View {
        switchRow(
            "System Proxy",
            isOn: Binding(
                get: { model.proxy.isOn },
                set: { on in Task { await model.setSystemProxy(on) } }
            ),
            // Switching the proxy on over a core that is not serving is the one
            // way this app can take the machine offline.
            enabled: model.canToggleProxy,
            help: model.canToggleProxy
                ? "Route system traffic through Mihomo"
                : "Start Mihomo first"
        )
    }

    /// A picker rather than a switch: neither position is an "off", and
    /// "Global" reads as a mode, not the absence of one.
    private var routingRow: some View {
        HStack(spacing: 0) {
            Text("Routing")
                .font(.system(size: 12))
            Spacer(minLength: 8)
            Picker("", selection: Binding(
                get: { model.subscription.routing },
                set: { model.setRouting($0) }
            )) {
                ForEach(Routing.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .labelsHidden()
            // A menu, not segments: three labels of this length do not fit
            // across a 280pt popover.
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        }
        .disabled(!model.canInteract)
        .help(model.subscription.routing.detail)
    }

    private func switchRow(
        _ title: String,
        isOn: Binding<Bool>,
        enabled: Bool,
        help: String
    ) -> some View {
        // A bare `Toggle(title:isOn:)` keeps the switch next to its label
        // rather than at the trailing edge, so the two rows would not line up.
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 12))
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .disabled(!enabled)
        .help(help)
    }

    // MARK: - Subscription

    private func subscriptionSection(url: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SUBSCRIPTION")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)

            TextField("https://…", text: url)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .onSubmit { Task { await model.update() } }

            HStack {
                Text(model.lastUpdatedText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Update") { Task { await model.update() } }
                    .controlSize(.small)
                    .disabled(url.wrappedValue.isEmpty || !model.canInteract)
            }
            routingRow
                .padding(.top, 2)
        }
    }

    /// Full rows rather than a row of links: the footer had to abbreviate
    /// "View Config" to "Config" to fit three across, and link-blue reads as a
    /// web link rather than a local action.
    private var actions: some View {
        VStack(spacing: 1) {
            MenuRow("View Config", enabled: model.subscription.hasConfig, action: showConfig)
            MenuRow("Reveal Log", action: model.revealLog)
            MenuRow("Quit Yami", action: model.quit)
        }
        // Let the hover highlight breathe into the popover's own padding.
        .padding(.horizontal, -6)
    }

    /// Selectable, because the first thing anyone reporting a problem is asked
    /// for is the two version numbers.
    private var about: some View {
        Text(model.aboutText)
            .font(.system(size: 10))
            // A concrete colour, not `.tertiary`. Hierarchical styles get
            // remapped against the popover's material, and selectable text in
            // that context came out at full label brightness.
            .foregroundStyle(Color.primary.opacity(0.45))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
            .help(model.aboutDetail)
    }

    /// An accessory app has to activate itself, or the window opens behind
    /// whatever the user was looking at.
    private func showConfig() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: ConfigWindow.id)
    }

    private var dotColor: Color {
        switch model.statusColor {
        case .green: .green
        case .red: .red
        case .amber: .orange
        case .grey: .secondary
        }
    }
}
