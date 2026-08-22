import SwiftUI

struct PopoverView: View {
    let model: AppModel

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var subscription = model.subscription

        VStack(alignment: .leading, spacing: 16) {
            // Headings rather than dividers: a heading says what a group is,
            // not merely where it ends, so doing both is twice the separation.
            section("CONNECTION") {
                coreRow
                statusLine
                proxyRow
                routingRow
            }
            section("SUBSCRIPTION") {
                urlField($subscription.url)
                updateRow(url: $subscription.url)
            }
            section("APP") {
                launchAtLoginRow
                MenuRow("View Config", enabled: model.subscription.hasConfig, action: showConfig)
                MenuRow("Reveal Log", action: model.revealLog)
                MenuRow("Quit Yami", action: model.quit)
                about
            }
        }
        .padding(12)
        .frame(width: 280)
        // Without a background of its own, a square-cornered backing shows
        // through behind the content — invisible in dark mode, obvious in
        // light, where it reads as a rectangle inside the rounded panel.
        .background(.regularMaterial)
        // The only moment the user looks at these controls — and the system
        // proxy can be changed behind our back in System Settings.
        .task { await model.popoverAppeared() }
    }

    // MARK: - Connection

    /// The core, the system proxy and routing are one thought: whether traffic
    /// is carried, whether anything uses it, and where it goes.
    private var coreRow: some View {
        switchRow(
            "Mihomo",
            isOn: Binding(
                get: { model.core.state.isRunning || model.core.state.isBusy },
                set: { _ in model.toggleCore() }
            ),
            enabled: model.core.canStart || model.core.state.isRunning,
            help: "Run the Mihomo core"
        )
    }

    /// A caption belonging to the row above, deliberately not a full-height row.
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
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
    }

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

    /// A picker rather than a switch: none of the three positions is an "off".
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
        .frame(height: PopoverMetrics.rowHeight)
        .padding(.horizontal, 6)
        .disabled(!model.canInteract)
        .help(model.subscription.routing.detail)
    }

    // MARK: - Subscription

    private func urlField(_ url: Binding<String>) -> some View {
        TextField("https://…", text: url)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, design: .monospaced))
            .lineLimit(1)
            .onSubmit { Task { await model.update() } }
    }

    private func updateRow(url: Binding<String>) -> some View {
        HStack {
            Text(model.lastUpdatedText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Update") { Task { await model.update() } }
                .controlSize(.small)
                .disabled(url.wrappedValue.isEmpty || !model.canInteract)
        }
        .frame(height: PopoverMetrics.rowHeight)
    }

    // MARK: - App

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
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .help(model.aboutDetail)
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            content()
        }
    }

    /// Matches `MenuRow`'s height and inset, so a switch and a plain action row
    /// sit on the same rhythm instead of the switch standing taller.
    private func switchRow(
        _ title: String,
        isOn: Binding<Bool>,
        enabled: Bool,
        help: String
    ) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 12))
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(height: PopoverMetrics.rowHeight)
        .padding(.horizontal, 6)
        .disabled(!enabled)
        .help(help)
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
