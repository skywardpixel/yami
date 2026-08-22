import SwiftUI

/// A full-width action row, styled like a menu item rather than a link.
///
/// Link-blue reads as "this opens a web page", which is wrong for a local
/// action, and a run of text buttons is a small target. A row that highlights
/// under the pointer is what a menu bar popover is expected to behave like.
struct MenuRow: View {
    private let title: String
    private let enabled: Bool
    private let action: () -> Void

    @State private var hovering = false

    init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(enabled ? .primary : .tertiary)
                .frame(maxWidth: .infinity, minHeight: PopoverMetrics.rowHeight, alignment: .leading)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The first control in the popover would otherwise draw a focus ring,
        // which no menu row has.
        .focusEffectDisabled()
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(hovering && enabled ? Color.primary.opacity(0.09) : .clear)
        )
        .onHover { hovering = $0 }
        .disabled(!enabled)
    }
}

enum PopoverMetrics {
    /// Every control and action row is this tall, so switches, pickers and
    /// plain text keep one rhythm down the popover.
    static let rowHeight: CGFloat = 24
}
