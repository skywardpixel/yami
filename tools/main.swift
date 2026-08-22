import AppKit

// Generates AppIcon.icns from the same crescent used in the menu bar, so the
// app icon and the status item are demonstrably the same mark.
//
// usage: makeicon <output.icns>

func renderIcon(size: CGFloat) -> NSBitmapImageRep {
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

    // macOS icon geometry: the art sits inset inside the canvas with a
    // continuous-curvature corner radius of ~22.4% of the art's width.
    let inset = size * 0.098
    let art = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let plate = NSBezierPath(roundedRect: art, xRadius: art.width * 0.224, yRadius: art.width * 0.224)

    // Yami — darkness. Deep indigo falling to near-black.
    let gradient = NSGradient(
        starting: NSColor(srgbRed: 0.16, green: 0.16, blue: 0.27, alpha: 1),
        ending: NSColor(srgbRed: 0.04, green: 0.04, blue: 0.08, alpha: 1)
    )!
    gradient.draw(in: plate, angle: -90)

    let moonWidth = art.width * 0.54
    let moon = NSRect(
        x: art.midX - moonWidth / 2,
        y: art.midY - moonWidth / 2,
        width: moonWidth,
        height: moonWidth
    )
    NSColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1).setFill()
    MenuBarIcon.crescent(in: moon).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appending(path: "Yami-\(UUID().uuidString).iconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let suffix = scale == 1 ? "" : "@2x"
        let data = renderIcon(size: CGFloat(pixels))
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
