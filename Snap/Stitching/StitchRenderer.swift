import CoreGraphics
import Foundation

/// Draws a `StitchPlan` into a single tall image, or into a window onto one.
///
/// Bands are addressed top-down (row 0 = top of the screenshot) and converted to
/// Core Graphics' bottom-left origin at draw time, which keeps the arithmetic
/// readable and matches how `CGImage.cropping(to:)` already interprets its rect.
enum StitchRenderer {
    /// Photos handles very tall images, but there is no reason to produce
    /// something unusable. Captures beyond this are scaled down to fit.
    static let maximumOutputHeight = 24_000

    /// One contiguous band of a source screenshot copied into the output.
    struct Placement {
        let frameIndex: Int
        let sourceTop: Int
        let height: Int
        let destinationTop: Int
    }

    /// Walks the plan once, producing every band in output order. Both the full
    /// render and the seam close-up work from this, so they cannot disagree
    /// about where a seam actually falls.
    static func placements(for plan: StitchPlan) -> [Placement] {
        var result: [Placement] = []
        var cursor = 0

        if plan.sticky.top > 0 {
            result.append(Placement(frameIndex: 0, sourceTop: 0, height: plan.sticky.top, destinationTop: cursor))
            cursor += plan.sticky.top
        }

        // The first screenshot contributes its whole scrolling band.
        result.append(Placement(
            frameIndex: 0, sourceTop: plan.sticky.top, height: plan.contentHeight, destinationTop: cursor
        ))
        cursor += plan.contentHeight

        // Every later screenshot contributes only its newly revealed rows, taken
        // from the bottom of its scrolling band.
        let contentBottom = plan.frameHeight - plan.sticky.bottom
        for (index, join) in plan.joins.enumerated() {
            let advance = min(max(join.advance, 0), plan.contentHeight)
            guard advance > 0 else { continue }
            result.append(Placement(
                frameIndex: index + 1,
                sourceTop: contentBottom - advance,
                height: advance,
                destinationTop: cursor
            ))
            cursor += advance
        }

        if plan.sticky.bottom > 0 {
            result.append(Placement(
                frameIndex: max(plan.frameCount - 1, 0),
                sourceTop: contentBottom,
                height: plan.sticky.bottom,
                destinationTop: cursor
            ))
        }
        return result
    }

    static func render(plan: StitchPlan, frames: [FrameBitmap], scale: CGFloat = 1) -> CGImage? {
        let fitScale = min(1, CGFloat(maximumOutputHeight) / CGFloat(max(plan.totalHeight, 1)))
        return draw(
            plan: plan,
            frames: frames,
            outputRange: 0..<plan.totalHeight,
            scale: min(scale, fitScale)
        )
    }

    /// Renders just the rows around one seam, for inspecting a join close up
    /// without having to scroll a very tall preview.
    static func renderSeamWindow(
        plan: StitchPlan,
        frames: [FrameBitmap],
        joinIndex: Int,
        radius: Int
    ) -> (image: CGImage, seamFraction: Double)? {
        guard plan.joins.indices.contains(joinIndex) else { return nil }
        let seam = plan.seamRow(atJoinIndex: joinIndex)
        let start = max(0, seam - radius)
        let end = min(plan.totalHeight, seam + radius)
        guard end > start else { return nil }
        guard let image = draw(plan: plan, frames: frames, outputRange: start..<end, scale: 1) else {
            return nil
        }
        return (image, Double(seam - start) / Double(end - start))
    }

    private static func draw(
        plan: StitchPlan,
        frames: [FrameBitmap],
        outputRange: Range<Int>,
        scale: CGFloat
    ) -> CGImage? {
        guard frames.count == plan.frameCount, !frames.isEmpty, !outputRange.isEmpty else { return nil }

        let outputWidth = max(1, Int((CGFloat(plan.frameWidth) * scale).rounded()))
        let outputHeight = max(1, Int((CGFloat(outputRange.count) * scale).rounded()))

        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return nil }
        context.interpolationQuality = .high

        // Only the frames this window actually touches need decoding.
        var images: [Int: CGImage] = [:]
        for placement in placements(for: plan) {
            let bandStart = placement.destinationTop
            let bandEnd = placement.destinationTop + placement.height
            guard bandEnd > outputRange.lowerBound, bandStart < outputRange.upperBound else { continue }
            guard frames.indices.contains(placement.frameIndex) else { continue }

            let image: CGImage
            if let cached = images[placement.frameIndex] {
                image = cached
            } else if let made = frames[placement.frameIndex].makeCGImage() {
                images[placement.frameIndex] = made
                image = made
            } else {
                continue
            }

            // Clip the band to the requested window.
            let visibleTop = max(bandStart, outputRange.lowerBound)
            let visibleBottom = min(bandEnd, outputRange.upperBound)
            let sourceTop = placement.sourceTop + (visibleTop - bandStart)
            let height = visibleBottom - visibleTop
            guard height > 0, sourceTop >= 0, sourceTop + height <= image.height else { continue }
            guard let slice = image.cropping(
                to: CGRect(x: 0, y: sourceTop, width: plan.frameWidth, height: height)
            ) else { continue }

            let scaledTop = CGFloat(visibleTop - outputRange.lowerBound) * scale
            let scaledHeight = CGFloat(height) * scale
            context.draw(
                slice,
                in: CGRect(
                    x: 0,
                    y: CGFloat(outputHeight) - scaledTop - scaledHeight,
                    width: CGFloat(outputWidth),
                    height: scaledHeight
                )
            )
        }

        return context.makeImage()
    }
}
