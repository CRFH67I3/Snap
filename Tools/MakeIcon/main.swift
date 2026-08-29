import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders the app icon at 1024×1024.
//
// The mark depicts what the app does: one tall capture with a seam running
// through it, where two screenshots were joined. Kept to a bold silhouette —
// a card, a seam — because the icon is mostly seen around 60pt.

let size = 1024
let canvas = CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))

guard let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { exit(1) }

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// Background: a diagonal gradient. App icons must be fully opaque and square;
// iOS applies the rounded mask itself.
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0x2563EB), color(0x7C3AED)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: canvas.maxY),
    end: CGPoint(x: canvas.maxX, y: 0),
    options: []
)

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// The captured page.
let card = CGRect(x: 286, y: 118, width: 452, height: 788)
let cardRadius: CGFloat = 54

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -18), blur: 46, color: color(0x1E1B4B, 0.35))
context.addPath(roundedPath(card, cardRadius))
context.setFillColor(color(0xFFFFFF))
context.fillPath()
context.restoreGState()

// Content lines, so the card reads as a screenshot rather than a blank sheet.
context.saveGState()
context.addPath(roundedPath(card, cardRadius))
context.clip()

let seamY = card.midY
let lineInset: CGFloat = 54
let innerWidth = card.width - lineInset * 2

// Content runs continuously from top to bottom, straight through the seam —
// which is the whole point: the join is where two screenshots met, not where
// the content breaks.
enum Block {
    case image(CGFloat)
    /// Width as a fraction of the card's inner width.
    case line(CGFloat)
}

let blocks: [Block] = [
    .image(132),
    .line(1.0), .line(0.72), .line(0.88),
    .image(120),
    .line(0.94), .line(0.66), .line(1.0), .line(0.78)
]

var cursor = card.maxY - 62
for block in blocks {
    switch block {
    case .image(let height):
        let rect = CGRect(x: card.minX + lineInset, y: cursor - height, width: innerWidth, height: height)
        context.addPath(roundedPath(rect, 22))
        context.setFillColor(color(0xC7D2FE))
        context.fillPath()
        cursor -= height + 34
    case .line(let fraction):
        let height: CGFloat = 30
        let rect = CGRect(
            x: card.minX + lineInset, y: cursor - height,
            width: innerWidth * fraction, height: height
        )
        context.addPath(roundedPath(rect, height / 2))
        context.setFillColor(color(0xE2E8F0))
        context.fillPath()
        cursor -= height + 26
    }
}
context.restoreGState()

// The seam: where two screenshots were joined.
context.saveGState()
context.setStrokeColor(color(0xF59E0B))
context.setLineWidth(14)
context.setLineCap(.round)
context.setLineDash(phase: 0, lengths: [34, 30])
context.move(to: CGPoint(x: card.minX + 26, y: seamY))
context.addLine(to: CGPoint(x: card.maxX - 26, y: seamY))
context.strokePath()
context.restoreGState()

guard let image = context.makeImage() else { exit(1) }

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon-1024.png"
let url = URL(fileURLWithPath: outputPath)
guard let destination = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.png.identifier as CFString, 1, nil
) else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
print("wrote \(url.path) (\(image.width)x\(image.height))")
