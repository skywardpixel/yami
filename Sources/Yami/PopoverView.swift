import SwiftUI

struct PopoverView: View {
    let model: AppModel

    var body: some View {
        @Bindable var subscription = model.subscription

        VStack(alignment: .leading, spacing: 0) {
            coreSection
            Divider().padding(.vertical, 10)
            proxyRow
            Divider().padding(.vertical, 10)
            subscriptionSection(url: $subscription.url)
            Divider().padding(.vertical, 10)
            launchAtLoginRow
            Divider().padding(.vertical, 10)
            footer
        }
        .padding(12)
        .frame(width: 280)
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
        }
    }

    private var footer: some View {
        HStack {
            Button("Reveal Log", action: model.revealLog)
                .buttonStyle(.link)
                .font(.system(size: 11))
            Spacer()
            Button("Quit Yami", action: model.quit)
                .buttonStyle(.link)
                .font(.system(size: 11))
        }
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
