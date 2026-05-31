import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? ".build/AppIcon.iconset"
let outputURL = URL(fileURLWithPath: outputPath)

try? FileManager.default.removeItem(at: outputURL)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let iconEntries: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

for entry in iconEntries {
    let pixels = entry.points * entry.scale
    let image = NSImage(size: NSSize(width: pixels, height: pixels))

    image.lockFocus()
    drawIcon(size: CGFloat(pixels))
    image.unlockFocus()

    guard let data = pngData(from: image) else {
        fatalError("Could not render icon size \(pixels)")
    }

    let suffix = entry.scale == 1 ? "" : "@\(entry.scale)x"
    let fileURL = outputURL.appendingPathComponent("icon_\(entry.points)x\(entry.points)\(suffix).png")
    try data.write(to: fileURL)
}

func drawIcon(size: CGFloat) {
    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    let outerRect = bounds.insetBy(dx: size * 0.035, dy: size * 0.035)
    let outerPath = NSBezierPath(
        roundedRect: outerRect,
        xRadius: size * 0.22,
        yRadius: size * 0.22
    )

    NSGraphicsContext.saveGraphicsState()
    outerPath.addClip()

    drawBackground(in: bounds, size: size)
    drawPreviewCard(size: size)
    drawWiFiArcs(size: size)
    drawPhone(size: size)
    drawHighlights(size: size)

    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.48).setStroke()
    outerPath.lineWidth = max(size * 0.01, 1)
    outerPath.stroke()
}

func drawBackground(in bounds: NSRect, size: CGFloat) {
    let gradient = NSGradient(colors: [
        NSColor(red: 0.78, green: 0.91, blue: 1.00, alpha: 1),
        NSColor(red: 0.96, green: 0.98, blue: 1.00, alpha: 1),
        NSColor(red: 0.77, green: 0.82, blue: 0.95, alpha: 1),
    ])
    gradient?.draw(in: bounds, angle: -38)

    NSColor.white.withAlphaComponent(0.34).setFill()
    NSBezierPath(ovalIn: NSRect(x: -size * 0.10, y: size * 0.55, width: size * 0.72, height: size * 0.56)).fill()

    NSColor(red: 0.14, green: 0.43, blue: 0.96, alpha: 0.16).setFill()
    NSBezierPath(ovalIn: NSRect(x: size * 0.47, y: -size * 0.12, width: size * 0.70, height: size * 0.58)).fill()
}

func drawPreviewCard(size: CGFloat) {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.17)
    shadow.shadowBlurRadius = size * 0.035
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.018)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()

    let card = NSRect(x: size * 0.145, y: size * 0.245, width: size * 0.47, height: size * 0.47)
    let cardPath = NSBezierPath(roundedRect: card, xRadius: size * 0.07, yRadius: size * 0.07)

    NSColor.white.withAlphaComponent(0.88).setFill()
    cardPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    let imageRect = card.insetBy(dx: size * 0.038, dy: size * 0.038)
    let imagePath = NSBezierPath(roundedRect: imageRect, xRadius: size * 0.045, yRadius: size * 0.045)
    NSGraphicsContext.saveGraphicsState()
    imagePath.addClip()

    let sky = NSGradient(colors: [
        NSColor(red: 0.40, green: 0.70, blue: 1.00, alpha: 1),
        NSColor(red: 0.98, green: 0.58, blue: 0.40, alpha: 1),
    ])
    sky?.draw(in: imageRect, angle: 90)

    NSColor(red: 0.07, green: 0.39, blue: 0.31, alpha: 1).setFill()
    let mountainA = NSBezierPath()
    mountainA.move(to: CGPoint(x: imageRect.minX, y: imageRect.minY))
    mountainA.line(to: CGPoint(x: imageRect.minX + imageRect.width * 0.34, y: imageRect.minY + imageRect.height * 0.45))
    mountainA.line(to: CGPoint(x: imageRect.minX + imageRect.width * 0.62, y: imageRect.minY))
    mountainA.close()
    mountainA.fill()

    NSColor(red: 0.03, green: 0.23, blue: 0.28, alpha: 1).setFill()
    let mountainB = NSBezierPath()
    mountainB.move(to: CGPoint(x: imageRect.minX + imageRect.width * 0.30, y: imageRect.minY))
    mountainB.line(to: CGPoint(x: imageRect.minX + imageRect.width * 0.72, y: imageRect.minY + imageRect.height * 0.58))
    mountainB.line(to: CGPoint(x: imageRect.maxX, y: imageRect.minY))
    mountainB.close()
    mountainB.fill()

    NSColor.white.withAlphaComponent(0.86).setFill()
    NSBezierPath(ovalIn: NSRect(x: imageRect.minX + imageRect.width * 0.64, y: imageRect.minY + imageRect.height * 0.63, width: imageRect.width * 0.17, height: imageRect.width * 0.17)).fill()

    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.7).setStroke()
    cardPath.lineWidth = max(size * 0.006, 1)
    cardPath.stroke()
}

func drawWiFiArcs(size: CGFloat) {
    let center = CGPoint(x: size * 0.53, y: size * 0.51)
    let radii = [size * 0.20, size * 0.27, size * 0.34]

    for (index, radius) in radii.enumerated() {
        let path = NSBezierPath()
        path.lineWidth = size * (index == 2 ? 0.026 : 0.023)
        path.lineCapStyle = .round
        path.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 28,
            endAngle: 78,
            clockwise: false
        )
        NSColor.white.withAlphaComponent(0.92 - CGFloat(index) * 0.12).setStroke()
        path.stroke()
    }
}

func drawPhone(size: CGFloat) {
    let phone = NSRect(x: size * 0.545, y: size * 0.18, width: size * 0.30, height: size * 0.62)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = size * 0.042
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.018)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()

    let shell = NSBezierPath(roundedRect: phone, xRadius: size * 0.075, yRadius: size * 0.075)
    NSColor(red: 0.055, green: 0.065, blue: 0.085, alpha: 1).setFill()
    shell.fill()
    NSGraphicsContext.restoreGraphicsState()

    let screen = phone.insetBy(dx: size * 0.025, dy: size * 0.029)
    let screenPath = NSBezierPath(roundedRect: screen, xRadius: size * 0.052, yRadius: size * 0.052)
    let screenGradient = NSGradient(colors: [
        NSColor(red: 0.08, green: 0.14, blue: 0.22, alpha: 1),
        NSColor(red: 0.14, green: 0.40, blue: 0.64, alpha: 1),
    ])
    screenGradient?.draw(in: screenPath, angle: 90)

    NSColor.black.withAlphaComponent(0.76).setFill()
    NSBezierPath(
        roundedRect: NSRect(
            x: phone.midX - size * 0.040,
            y: phone.maxY - size * 0.064,
            width: size * 0.080,
            height: size * 0.016
        ),
        xRadius: size * 0.008,
        yRadius: size * 0.008
    ).fill()

    let thumb = NSRect(x: screen.minX + size * 0.035, y: screen.minY + size * 0.075, width: screen.width - size * 0.070, height: screen.width - size * 0.070)
    let thumbPath = NSBezierPath(roundedRect: thumb, xRadius: size * 0.026, yRadius: size * 0.026)
    NSColor.white.withAlphaComponent(0.90).setFill()
    thumbPath.fill()

    NSColor(red: 0.19, green: 0.62, blue: 0.94, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: thumb.minX + thumb.width * 0.61, y: thumb.minY + thumb.height * 0.57, width: thumb.width * 0.18, height: thumb.width * 0.18)).fill()

    NSColor(red: 0.05, green: 0.38, blue: 0.32, alpha: 1).setFill()
    let mountain = NSBezierPath()
    mountain.move(to: CGPoint(x: thumb.minX, y: thumb.minY))
    mountain.line(to: CGPoint(x: thumb.minX + thumb.width * 0.43, y: thumb.minY + thumb.height * 0.52))
    mountain.line(to: CGPoint(x: thumb.maxX, y: thumb.minY))
    mountain.close()
    mountain.fill()
}

func drawHighlights(size: CGFloat) {
    NSColor.white.withAlphaComponent(0.36).setStroke()
    let highlight = NSBezierPath()
    highlight.lineWidth = max(size * 0.014, 1.5)
    highlight.lineCapStyle = .round
    highlight.appendArc(
        withCenter: CGPoint(x: size * 0.50, y: size * 0.50),
        radius: size * 0.43,
        startAngle: 108,
        endAngle: 152,
        clockwise: false
    )
    highlight.stroke()
}

func pngData(from image: NSImage) -> Data? {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else {
        return nil
    }

    return bitmap.representation(using: .png, properties: [:])
}
