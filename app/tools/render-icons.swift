// Renders Mage.app icon variants (light + dark) as 1024x1024 PNGs.
// Usage: swift render-icons.swift <out-dir>
// Design: rounded-rect tile, indigo/violet gradient, rune-like "M" with a
// four-point spark. Dark mode variant uses a graphite tile + brighter glyph.
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let size = CGSize(width: 1024, height: 1024)

func makeIcon(dark: Bool) -> NSImage {
    NSImage(size: size, flipped: false) { rect in
        let path = NSBezierPath(roundedRect: rect, xRadius: 224, yRadius: 224)
        path.addClip()

        let bgColors: [NSColor] = dark
            ? [NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.16, alpha: 1),
               NSColor(calibratedRed: 0.22, green: 0.21, blue: 0.26, alpha: 1)]
            : [NSColor(calibratedRed: 0.42, green: 0.36, blue: 1.00, alpha: 1),
               NSColor(calibratedRed: 0.29, green: 0.25, blue: 0.84, alpha: 1)]
        NSGradient(colors: bgColors)!
            .draw(in: rect, angle: 90) // 90 = top-first in unflipped coords

        // rune "M": angular polyline, round caps/joins
        let m = NSBezierPath()
        m.move(to: NSPoint(x: 262, y: 324))
        m.line(to: NSPoint(x: 262, y: 700))
        m.line(to: NSPoint(x: 512, y: 460))
        m.line(to: NSPoint(x: 762, y: 700))
        m.line(to: NSPoint(x: 762, y: 324))
        m.lineCapStyle = .round
        m.lineJoinStyle = .round
        m.lineWidth = 108
        (dark
            ? NSColor(calibratedRed: 0.93, green: 0.92, blue: 1.0, alpha: 1)
            : NSColor.white).setStroke()
        m.stroke()

        // four-point spark, top right of the M
        let cx: CGFloat = 795, cy: CGFloat = 795, r: CGFloat = 62, inner: CGFloat = 18
        let star = NSBezierPath()
        star.move(to: NSPoint(x: cx, y: cy + r))
        star.line(to: NSPoint(x: cx + inner, y: cy + inner))
        star.line(to: NSPoint(x: cx + r, y: cy))
        star.line(to: NSPoint(x: cx + inner, y: cy - inner))
        star.line(to: NSPoint(x: cx, y: cy - r))
        star.line(to: NSPoint(x: cx - inner, y: cy - inner))
        star.line(to: NSPoint(x: cx - r, y: cy))
        star.line(to: NSPoint(x: cx - inner, y: cy + inner))
        star.close()
        NSColor(calibratedRed: 0.85, green: 0.44, blue: 0.95, alpha: 1).setFill()
        star.fill()
        return true
    }
}

func writePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("png encode failed: \(path)")
    }
    try! png.write(to: URL(fileURLWithPath: path))
}

writePNG(makeIcon(dark: false), to: "\(outDir)/icon-light.png")
writePNG(makeIcon(dark: true), to: "\(outDir)/icon-dark.png")
print("icons written to \(outDir)")
