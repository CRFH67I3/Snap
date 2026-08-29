import CoreGraphics
import UIKit

struct DecorationOptions: Equatable {
    var watermarkText: String = ""
    var watermarkTiled: Bool = false
    var roundedFrame: Bool = false

    var isIdentity: Bool {
        watermarkText.trimmingCharacters(in: .whitespaces).isEmpty && !roundedFrame
    }
}

enum Decorator {
    /// A phone-style frame around a very tall image only makes sense as a border
    /// and rounded corners — an actual device bezel would be absurdly stretched.
    private static let cornerRadiusFraction: CGFloat = 0.045
    private static let framePaddingFraction: CGFloat = 0.03

    static func apply(_ options: DecorationOptions, to image: CGImage) -> CGImage? {
        guard !options.isIdentity else { return image }

        let sourceWidth = CGFloat(image.width)
        let sourceHeight = CGFloat(image.height)
        let padding = options.roundedFrame ? (sourceWidth * framePaddingFraction).rounded() : 0
        let outputWidth = sourceWidth + padding * 2
        let outputHeight = sourceHeight + padding * 2

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: outputWidth, height: outputHeight),
            format: format
        )

        let rendered = renderer.image { rendererContext in
            let context = rendererContext.cgContext
            let uiImage = UIImage(cgImage: image)

            UIColor.systemBackground.setFill()
            context.fill(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))

            let imageRect = CGRect(x: padding, y: padding, width: sourceWidth, height: sourceHeight)

            if options.roundedFrame {
                let radius = sourceWidth * cornerRadiusFraction
                let path = UIBezierPath(roundedRect: imageRect, cornerRadius: radius)
                context.saveGState()
                path.addClip()
                uiImage.draw(in: imageRect)
                context.restoreGState()

                UIColor.separator.setStroke()
                path.lineWidth = max(1, sourceWidth * 0.002)
                path.stroke()
            } else {
                uiImage.draw(in: imageRect)
            }

            drawWatermark(options, in: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
        }

        return rendered.cgImage
    }

    private static func drawWatermark(_ options: DecorationOptions, in rect: CGRect) {
        let text = options.watermarkText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let fontSize = max(18, rect.width * 0.032)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(options.watermarkTiled ? 0.22 : 0.75)
        ]
        let stroke: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.black.withAlphaComponent(options.watermarkTiled ? 0.12 : 0.35)
        ]
        let size = (text as NSString).size(withAttributes: attributes)

        if options.watermarkTiled {
            let stepX = size.width + fontSize * 3
            let stepY = size.height + fontSize * 5
            var y = fontSize
            var row = 0
            while y < rect.height {
                var x = row.isMultiple(of: 2) ? fontSize : fontSize + stepX / 2
                while x < rect.width {
                    (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
                    x += stepX
                }
                y += stepY
                row += 1
            }
        } else {
            let margin = fontSize
            let origin = CGPoint(
                x: rect.maxX - size.width - margin,
                y: rect.maxY - size.height - margin
            )
            (text as NSString).draw(
                at: CGPoint(x: origin.x + 1, y: origin.y + 1),
                withAttributes: stroke
            )
            (text as NSString).draw(at: origin, withAttributes: attributes)
        }
    }
}
