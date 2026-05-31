import CoreImage.CIFilterBuiltins
import SwiftUI

struct QRCodeView: View {
    let text: String

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        if let image = makeImage() {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("QR code")
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .overlay(Text("QR").foregroundStyle(.secondary))
        }
    }

    private func makeImage() -> NSImage? {
        filter.message = Data(text.utf8)
        filter.correctionLevel = "H"

        guard let outputImage = filter.outputImage else { return nil }

        let extent = outputImage.extent.integral
        let moduleWidth = Int(extent.width)
        let moduleHeight = Int(extent.height)
        var pixels = [UInt8](repeating: 0, count: moduleWidth * moduleHeight * 4)

        context.render(
            outputImage,
            toBitmap: &pixels,
            rowBytes: moduleWidth * 4,
            bounds: extent,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let quietZone = 4
        let moduleSize: CGFloat = 9
        let side = CGFloat(max(moduleWidth, moduleHeight) + quietZone * 2) * moduleSize
        let image = NSImage(size: NSSize(width: side, height: side))

        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        NSColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1).setFill()

        for y in 0..<moduleHeight {
            for x in 0..<moduleWidth where isDarkModule(x: x, y: y, width: moduleWidth, pixels: pixels) {
                let rect = NSRect(
                    x: CGFloat(x + quietZone) * moduleSize,
                    y: CGFloat(y + quietZone) * moduleSize,
                    width: moduleSize,
                    height: moduleSize
                ).insetBy(dx: moduleSize * 0.12, dy: moduleSize * 0.12)

                NSBezierPath(
                    roundedRect: rect,
                    xRadius: moduleSize * 0.38,
                    yRadius: moduleSize * 0.38
                ).fill()
            }
        }

        image.unlockFocus()
        return image
    }

    private func isDarkModule(x: Int, y: Int, width: Int, pixels: [UInt8]) -> Bool {
        let offset = (y * width + x) * 4
        guard pixels.indices.contains(offset + 3) else { return false }
        return pixels[offset] < 128 && pixels[offset + 3] > 0
    }
}
