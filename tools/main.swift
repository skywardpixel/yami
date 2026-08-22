import AppKit

// Draws the project's artwork from the crescent in MenuBarIcon, so the app icon,
// the status item, and the README figure cannot drift apart.
//
//   makeicon <out.icns>            the app icon
//   makeicon --png <out.png>       the app icon as a flat PNG, for the README
//   makeicon --states <out.png>    the README's menu bar state figure

func renderAppIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon geometry: art inset inside the canvas, corner radius ~22.4%.
    let inset = size * 0.098
    let art = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let plate = NSBezierPath(roundedRect: art, xRadius: art.width * 0.224, yRadius: art.width * 0.224)

    // Yami — darkness. Deep indigo falling to near-black.
    NSGradient(
        starting: NSColor(srgbRed: 0.16, green: 0.16, blue: 0.27, alpha: 1),
        ending: NSColor(srgbRed: 0.04, green: 0.04, blue: 0.08, alpha: 1)
    )!.draw(in: plate, angle: -90)

    let moonWidth = art.width * 0.54
    NSColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1).setFill()
    MenuBarIcon.crescent(in: NSRect(
        x: art.midX - moonWidth / 2,
        y: art.midY - moonWidth / 2,
        width: moonWidth,
        height: moonWidth
    )).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writeAppIcon(to output: URL) {
    let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "Yami-\(UUID().uuidString).iconset")
    try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let suffix = scale == 1 ? "" : "@2x"
            let data = renderAppIcon(size: CGFloat(base * scale))
                .representation(using: .png, properties: [:])!
            try! data.write(to: iconset.appending(path: "icon_\(base)x\(base)\(suffix).png"))
        }
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
    try! iconutil.run()
    iconutil.waitUntilExit()
    try? FileManager.default.removeItem(at: iconset)
    print(iconutil.terminationStatus == 0 ? "wrote \(output.path)" : "iconutil failed")
}

/// Paints a template image in one colour. The tint must be composited inside
/// the image's own transparent context — doing it after the image is drawn onto
/// an opaque background makes `sourceAtop` fill the whole rectangle.
func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let out = NSImage(size: image.size)
    out.lockFocus()
    image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    color.setFill()
    NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

/// The four menu bar states, on a light and a dark bar. Template images carry no
/// colour of their own, so each is tinted the way the system would tint it.
func writeStateFigure(to output: URL) {
    let states: [(Bool, Bool)] = [(false, false), (true, false), (false, true), (true, true)]
    // Rendered at 2x the width the README displays it at, so it stays crisp on
    // a Retina screen.
    let scale: CGFloat = 8
    let cell = NSSize(width: 34 * scale, height: 24 * scale)
    let size = NSSize(width: cell.width * CGFloat(states.count), height: cell.height * 2)

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    for (row, background) in [NSColor(white: 0.16, alpha: 1), NSColor.white].enumerated() {
        let tint: NSColor = row == 0 ? .white : .black
        let y = CGFloat(row) * cell.height
        background.setFill()
        NSRect(x: 0, y: y, width: size.width, height: cell.height).fill()

        for (column, state) in states.enumerated() {
            let icon = tinted(MenuBarIcon.image(coreRunning: state.0, proxyOn: state.1), tint)
            let box = NSRect(
                x: CGFloat(column) * cell.width + (cell.width - icon.size.width * scale) / 2,
                y: y + (cell.height - icon.size.height * scale) / 2,
                width: icon.size.width * scale,
                height: icon.size.height * scale
            )
            icon.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
    NSGraphicsContext.restoreGraphicsState()

    let data = rep.representation(using: .png, properties: [.interlaced: false])!
    try! data.write(to: output)
    print("wrote \(output.path) (\(data.count) bytes)")
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--states", arguments.count > 1 {
    writeStateFigure(to: URL(fileURLWithPath: arguments[1]))
} else if arguments.first == "--png", arguments.count > 1 {
    // The README shows this at 96pt; 256 covers Retina with room to spare.
    let data = renderAppIcon(size: 256).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: arguments[1]))
    print("wrote \(arguments[1]) (\(data.count) bytes)")
} else if let first = arguments.first {
    writeAppIcon(to: URL(fileURLWithPath: first))
} else {
    print("usage: makeicon <out.icns> | makeicon --states <out.png>")
    exit(1)
}
