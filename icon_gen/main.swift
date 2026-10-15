import AppKit

let size: CGFloat = 1024
let rect = CGRect(x: 0, y: 0, width: size, height: size)

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("no context")
}

// Background: warm gradient rounded square, matching the app's cream/accent palette.
let bgPath = NSBezierPath(roundedRect: rect, xRadius: size * 0.225, yRadius: size * 0.225)
bgPath.addClip()

let colors = [
    NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.30, alpha: 1.0).cgColor,
    NSColor(calibratedRed: 0.88, green: 0.36, blue: 0.28, alpha: 1.0).cgColor
]
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// Subtle inner glow circle behind the waveform for depth.
ctx.saveGState()
let glowRect = rect.insetBy(dx: size * 0.16, dy: size * 0.16)
let glowPath = CGPath(ellipseIn: glowRect, transform: nil)
ctx.addPath(glowPath)
ctx.setFillColor(NSColor.white.withAlphaComponent(0.12).cgColor)
ctx.fillPath()
ctx.restoreGState()

// Waveform bars, centered, rounded caps, varying heights for a natural audio look.
let barHeights: [CGFloat] = [0.22, 0.40, 0.62, 0.84, 0.62, 0.95, 0.62, 0.84, 0.62, 0.40, 0.22]
let barCount = barHeights.count
let barWidth = size * 0.045
let spacing = size * 0.028
let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
var x = (size - totalWidth) / 2

ctx.setFillColor(NSColor.white.cgColor)
for h in barHeights {
    let barHeight = size * 0.62 * h
    let barRect = CGRect(x: x, y: (size - barHeight) / 2, width: barWidth, height: barHeight)
    let barPath = CGPath(roundedRect: barRect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
    ctx.addPath(barPath)
    ctx.fillPath()
    x += barWidth + spacing
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("failed to encode png")
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
try! png.write(to: outputURL)
print("wrote \(outputURL.path)")
