import AppKit

/// Yami's mark: a crescent, drawn rather than borrowed from SF Symbols.
///
/// The mark is built as one circle minus another, so it stays a crisp silhouette
/// at 16pt where a stroked or detailed glyph turns to mush — `globe` read as a
/// grey blob at menu bar size. It also nods at the name (闇, darkness).
///
/// The two states stay orthogonal, because the core can run without the proxy:
///
///   full tint / dimmed          →  core running / stopped
///   badge dot present / absent  →  system proxy on / off
enum MenuBarIcon {
    /// Menu bar glyphs sit in an 18pt band; 15 leaves the standard optical margin.
    private static let diameter: CGFloat = 15
    private static let badgeDiameter: CGFloat = 4.5
    /// Transparent moat so the badge reads as separate from the mark.
    private static let badgeGap: CGFloat = 1.5
    /// Dimmed, not hidden: a stopped core should still be findable in the bar.
    private static let dimmedAlpha: CGFloat = 0.4

    static func image(coreRunning: Bool, proxyOn: Bool) -> NSImage {
        // The canvas is the same size whether or not the badge is showing, and
        // the mark is centred in it. Sizing the canvas to the badge would shift
        // the crescent up and left every time the proxy was switched on.
        let inset = badgeDiameter / 2 + badgeGap
        let size = NSSize(width: diameter + inset, height: diameter + inset)
        let image = NSImage(size: size)
        let alpha = coreRunning ? 1.0 : dimmedAlpha

        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = true
        }

        NSColor.black.withAlphaComponent(alpha).setFill()
        crescent(in: NSRect(
            x: (size.width - diameter) / 2,
            y: (size.height - diameter) / 2,
            width: diameter,
            height: diameter
        )).fill()

        guard proxyOn else { return image }

        let badge = NSRect(
            x: size.width - badgeDiameter,
            y: size.height - badgeDiameter,
            width: badgeDiameter,
            height: badgeDiameter
        )
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: badge.insetBy(dx: -badgeGap, dy: -badgeGap)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.black.withAlphaComponent(alpha).setFill()
        NSBezierPath(ovalIn: badge).fill()

        return image
    }

    /// Spoken by VoiceOver and shown as the item's tooltip — a dimmed mark and a
    /// badge dot are not self-explanatory, so the state needs saying in words.
    static func describe(coreRunning: Bool, proxyOn: Bool) -> String {
        switch (coreRunning, proxyOn) {
        case (true, true): "Mihomo running, system proxy on"
        case (true, false): "Mihomo running, system proxy off"
        case (false, true): "Mihomo stopped, system proxy on"
        case (false, false): "Mihomo stopped"
        }
    }

    /// The crescent outline, as two arcs meeting at the horns.
    ///
    /// Built from the real circle-circle intersection rather than by filling one
    /// disc and subtracting another: the subtracting disc necessarily overhangs
    /// the outer one (that overhang is what forms the horns), and an even-odd
    /// fill paints that overhang too, which turns the mark into a broken ring.
    static func crescent(in rect: NSRect) -> NSBezierPath {
        let outerRadius = rect.width / 2
        let center = NSPoint(x: rect.midX, y: rect.midY)

        // Tuned so the waist stays ~25% of the diameter — thin enough to read as
        // a crescent, thick enough to survive antialiasing at 15pt.
        let biteRadius = outerRadius * 0.92
        let offset = outerRadius * 0.42
        let biteCenter = NSPoint(x: center.x + offset, y: center.y)

        // Where the two circles cross, measured along the line of centres.
        let along = (offset * offset - biteRadius * biteRadius + outerRadius * outerRadius)
            / (2 * offset)
        let across = (outerRadius * outerRadius - along * along).squareRoot()

        let outerAngle = atan2(across, along) * 180 / .pi
        let biteAngle = atan2(across, along - offset) * 180 / .pi

        let path = NSBezierPath()
        // The long way round the outer disc, horn to horn.
        path.appendArc(
            withCenter: center,
            radius: outerRadius,
            startAngle: outerAngle,
            endAngle: 360 - outerAngle,
            clockwise: false
        )
        // Back along the bite, bulging into the disc.
        path.appendArc(
            withCenter: biteCenter,
            radius: biteRadius,
            startAngle: 360 - biteAngle,
            endAngle: biteAngle,
            clockwise: true
        )
        path.close()
        return path
    }
}
