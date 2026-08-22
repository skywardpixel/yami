import AppKit
import SwiftUI

enum ConfigWindow {
    static let id = "config"
}

/// Read-only view of the config mihomo is actually running.
///
/// A deliberate exception to the app's one-popover rule: the file is far too
/// large for a 280pt popover, and handing it to the default `.yaml` handler is
/// worse — on a developer's Mac that is usually Xcode, which is a ten-second
/// launch to read a proxy config.
struct ConfigView: View {
    @State private var contents = ""
    @State private var problem: String?
    @State private var modified: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let problem {
                Spacer()
                Text(problem)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                MonospacedTextView(text: contents)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .task { load() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Generated from your subscription — edits here are overwritten on the next update.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            Button("Reveal", action: reveal)
                .controlSize(.small)
            Button("Reload", action: load)
                .controlSize(.small)
        }
        .padding(12)
    }

    private var subtitle: String {
        var parts = [Paths.config.path]
        if let modified {
            parts.append("written " + modified.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }

    private func load() {
        do {
            contents = try String(contentsOf: Paths.config, encoding: .utf8)
            modified = try FileManager.default
                .attributesOfItem(atPath: Paths.config.path)[.modificationDate] as? Date
            problem = nil
        } catch {
            contents = ""
            problem = FileManager.default.fileExists(atPath: Paths.config.path)
                ? "Could not read config.yaml: \(error.localizedDescription)"
                : "No config yet — add a subscription and update."
        }
    }

    private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([Paths.config])
    }
}

/// NSTextView rather than a SwiftUI `Text` in a `ScrollView`: a config with a
/// few hundred nodes runs to hundreds of kilobytes, which `Text` with selection
/// enabled does not handle gracefully. It also brings ⌘F along for free.
private struct MonospacedTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.usesFindBar = true
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.drawsBackground = false
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        view.string = text
        // Setting the string leaves the caret — and the scroller — at the end of
        // the document. A config is read from the top.
        view.scroll(NSPoint(x: 0, y: 0))
        view.setSelectedRange(NSRange(location: 0, length: 0))
    }
}
