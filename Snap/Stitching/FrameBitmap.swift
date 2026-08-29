import CoreGraphics
import Foundation

/// A screenshot decoded into a known, tightly-packed BGRA layout, with two
/// per-row indexes used for alignment.
///
/// `rowHashes` is an exact fingerprint. `rowSignatures` is a deliberately blurry
/// one — average luminance across a handful of column bands. Real apps make the
/// exact hash too brittle on its own: a feed can re-render a live badge, finish
/// decoding a lazily loaded image, or rotate a promo string, so two screenshots
/// of "the same" content agree on ~99% of pixels but almost no rows match
/// byte-for-byte. The signature tolerates that; the exact hash and full pixel
/// comparison are then used to confirm a candidate rather than to find it.
struct FrameBitmap {
    /// Column bands per row signature.
    static let signatureBuckets = 12
    /// Per-band luminance difference still considered the same content.
    static let signatureTolerance = 3

    let width: Int
    let height: Int
    let bytesPerRow: Int
    let pixels: [UInt8]
    let rowHashes: [UInt64]
    let rowSignatures: [UInt8]

    init?(cgImage: CGImage) {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue

        let drew: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: bitmapInfo
                  ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }

        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.rowHashes = Self.computeRowHashes(pixels: pixels, height: height, bytesPerRow: bytesPerRow)
        self.rowSignatures = Self.computeRowSignatures(
            pixels: pixels, width: width, height: height, bytesPerRow: bytesPerRow
        )
        self.pixels = pixels
    }

    private static func computeRowHashes(pixels: [UInt8], height: Int, bytesPerRow: Int) -> [UInt64] {
        var hashes = [UInt64](repeating: 0, count: height)
        pixels.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for row in 0..<height {
                var hash: UInt64 = 0xcbf2_9ce4_8422_2325
                let start = base + row * bytesPerRow
                for i in 0..<bytesPerRow {
                    hash ^= UInt64(start[i])
                    hash = hash &* 0x0000_0100_0000_01b3
                }
                hashes[row] = hash
            }
        }
        return hashes
    }

    private static func computeRowSignatures(
        pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int
    ) -> [UInt8] {
        let buckets = signatureBuckets
        var out = [UInt8](repeating: 0, count: height * buckets)
        pixels.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for row in 0..<height {
                let rowStart = base + row * bytesPerRow
                for bucket in 0..<buckets {
                    let x0 = bucket * width / buckets
                    let x1 = (bucket + 1) * width / buckets
                    var sum = 0
                    var samples = 0
                    // Every fourth pixel is plenty for a band average and keeps
                    // this cheap enough to run over every row of every frame.
                    var x = x0
                    while x < x1 {
                        let i = x * 4
                        sum += Int(rowStart[i]) + Int(rowStart[i + 1]) + Int(rowStart[i + 2])
                        samples += 3
                        x += 4
                    }
                    out[row * buckets + bucket] = samples > 0 ? UInt8(sum / samples) : 0
                }
            }
        }
        return out
    }

    /// Whether two rows look like the same content, allowing for small rendering
    /// differences.
    static func signaturesMatch(_ a: FrameBitmap, _ rowA: Int, _ b: FrameBitmap, _ rowB: Int) -> Bool {
        let buckets = signatureBuckets
        let offsetA = rowA * buckets
        let offsetB = rowB * buckets
        for i in 0..<buckets {
            let delta = Int(a.rowSignatures[offsetA + i]) - Int(b.rowSignatures[offsetB + i])
            if delta > signatureTolerance || delta < -signatureTolerance { return false }
        }
        return true
    }

    /// Rebuilds a drawable image. Analysis keeps the unpacked pixels, so the
    /// originally decoded `CGImage` can be released once a `FrameBitmap` exists.
    func makeCGImage() -> CGImage? {
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Fraction of bytes that are identical between two rows of two frames.
    static func rowSimilarity(_ a: FrameBitmap, _ rowA: Int, _ b: FrameBitmap, _ rowB: Int) -> Double {
        guard a.bytesPerRow == b.bytesPerRow,
              rowA >= 0, rowA < a.height, rowB >= 0, rowB < b.height else { return 0 }
        if a.rowHashes[rowA] == b.rowHashes[rowB] { return 1 }

        let count = a.bytesPerRow
        var matching = 0
        a.pixels.withUnsafeBufferPointer { pa in
            b.pixels.withUnsafeBufferPointer { pb in
                guard let baseA = pa.baseAddress, let baseB = pb.baseAddress else { return }
                let startA = baseA + rowA * a.bytesPerRow
                let startB = baseB + rowB * b.bytesPerRow
                for i in 0..<count where startA[i] == startB[i] {
                    matching += 1
                }
            }
        }
        return Double(matching) / Double(count)
    }
}
