import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Synthetic iPhone 16 Pro geometry.
let screenW = 1206
let screenH = 2622
let statusBarH = 180      // status bar + nav bar
let inputBarH = 122       // chat input bar + home indicator
let contentH = screenH - statusBarH - inputBarH
let pageH = 9000

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  PASS  \(message)")
    } else {
        print("  FAIL  \(message)")
        failures += 1
    }
}

func makeBuffer(width: Int, height: Int) -> [UInt8] {
    [UInt8](repeating: 0, count: width * height * 4)
}

func setPixel(_ buf: inout [UInt8], _ w: Int, _ x: Int, _ y: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
    let i = (y * w + x) * 4
    buf[i] = b; buf[i + 1] = g; buf[i + 2] = r; buf[i + 3] = 255
}

func cgImage(from buf: [UInt8], width: Int, height: Int) -> CGImage {
    let provider = CGDataProvider(data: Data(buf) as CFData)!
    return CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    )!
}

// A tall page whose rows are individually distinctive, but which also contains a
// strongly repeating band pattern — the list-like content that defeated the
// previous Vision-based matcher.
func makePage() -> [UInt8] {
    var page = makeBuffer(width: screenW, height: pageH)
    let rng = SystemRandomNumberGenerator()
    for y in 0..<pageH {
        let band = (y / 140) % 4
        let base: (UInt8, UInt8, UInt8)
        switch band {
        case 0: base = (250, 250, 252)
        case 1: base = (255, 214, 10)
        case 2: base = (242, 242, 247)
        default: base = (255, 255, 255)
        }
        for x in 0..<screenW {
            setPixel(&page, screenW, x, y, base.0, base.1, base.2)
        }
        // "Text" runs: unique per row so the row hash is distinctive.
        let seed = UInt64(y &* 2_654_435_761)
        var local = SplitMix(seed: seed)
        let runs = 6 + Int(local.next() % 5)
        for _ in 0..<runs {
            let start = Int(local.next() % UInt64(screenW - 120))
            let length = 40 + Int(local.next() % 80)
            let shade = UInt8(30 + local.next() % 90)
            for x in start..<min(start + length, screenW) {
                setPixel(&page, screenW, x, y, shade, shade, UInt8(min(255, Int(shade) + 20)))
            }
        }
        _ = rng
    }
    return page
}

struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Builds one screenshot: frozen chrome top and bottom, page window in between.
/// `clockTick` perturbs a small area of the status bar the way a real clock does.
func makeScreenshot(page: [UInt8], scroll: Int, clockTick: Int) -> CGImage {
    var shot = makeBuffer(width: screenW, height: screenH)

    // Frozen top chrome.
    for y in 0..<statusBarH {
        for x in 0..<screenW {
            let v: UInt8 = y < 60 ? 245 : 255
            setPixel(&shot, screenW, x, y, v, v, v)
        }
        if y > 12 && y < 44 {
            for x in 80..<140 where (x + clockTick * 7) % 5 < 3 {
                setPixel(&shot, screenW, x, y, 20, 20, 20)
            }
        }
        if y > 90 && y < 150 {
            for x in 40..<600 where (x % 11) < 6 {
                setPixel(&shot, screenW, x, y, 60, 60, 70)
            }
        }
    }

    // Scrolling window into the page.
    for row in 0..<contentH {
        let pageRow = scroll + row
        guard pageRow < pageH else { break }
        let dstY = statusBarH + row
        for x in 0..<screenW {
            let s = (pageRow * screenW + x) * 4
            let d = (dstY * screenW + x) * 4
            shot[d] = page[s]; shot[d + 1] = page[s + 1]
            shot[d + 2] = page[s + 2]; shot[d + 3] = 255
        }
    }

    // Frozen bottom chrome.
    for y in (screenH - inputBarH)..<screenH {
        for x in 0..<screenW {
            let v: UInt8 = y > screenH - 30 ? 200 : 248
            setPixel(&shot, screenW, x, y, v, v, v)
        }
    }

    return cgImage(from: shot, width: screenW, height: screenH)
}

// ---------------------------------------------------------------------------

print("Building synthetic page and screenshots…")
let page = makePage()

// Deliberately uneven scrolls, including a full-screen jump with no overlap.
let scrolls = [0, 1180, 2010, 2600, 5200, 6100]
let shots = scrolls.enumerated().map { makeScreenshot(page: page, scroll: $1, clockTick: $0) }
let frames = shots.compactMap { FrameBitmap(cgImage: $0) }

print("\n[1] FrameBitmap")
check(frames.count == scrolls.count, "decoded \(frames.count)/\(scrolls.count) frames")
check(frames[0].width == screenW && frames[0].height == screenH, "dimensions preserved")

print("\n[2] Sticky region detection")
let alignments = StitchEngine.align(frames: frames)
let sticky = StickyRegionDetector.detect(frames: frames, alignments: alignments)
print("      detected top=\(sticky.top) bottom=\(sticky.bottom), expected top=\(statusBarH) bottom=\(inputBarH)")
check(abs(sticky.top - statusBarH) <= 4, "top band found despite a changing clock")
check(abs(sticky.bottom - inputBarH) <= 4, "bottom band found")

print("\n[3] Overlap matching")
for i in 0..<(frames.count - 1) {
    let expected = scrolls[i + 1] - scrolls[i]
    let overlaps = expected < contentH
    if let m = alignments[i] {
        let label = "pair \(i)->\(i+1): got \(m.offset), expected \(expected) (score \(String(format: "%.3f", m.score)))"
        check(overlaps && m.offset == expected, label)
    } else {
        check(!overlaps, "pair \(i)->\(i+1): correctly reported no overlap (expected scroll \(expected) >= band \(contentH))")
    }
}

print("\n[4] Plan")
guard let plan = StitchEngine.makePlan(frames: frames, alignments: alignments, detectSticky: true) else {
    print("  FAIL  plan could not be built"); exit(1)
}
let expectedTotal = sticky.top + plan.contentHeight
    + plan.joins.reduce(0) { $0 + $1.advance } + sticky.bottom
check(plan.totalHeight == expectedTotal, "total height \(plan.totalHeight) is self-consistent")
check(plan.joins.count == frames.count - 1, "one join per pair")
print("      unmatched joins flagged: \(plan.joins.filter { !$0.matched }.count)")

print("\n[5] Render + pixel-exact verification")
guard let output = StitchRenderer.render(plan: plan, frames: frames, scale: 1) else {
    print("  FAIL  render returned nil"); exit(1)
}
check(output.width == screenW, "output width \(output.width)")
check(output.height == plan.totalHeight, "output height \(output.height) matches plan")

// The strongest check: every stitched content row must be byte-identical to the
// original page row it came from. If the offsets were wrong by even one pixel,
// this fails.
guard let outBitmap = FrameBitmap(cgImage: output) else {
    print("  FAIL  could not read back output"); exit(1)
}
var pageBitmapBuf = makeBuffer(width: screenW, height: pageH)
pageBitmapBuf = page
let pageImage = cgImage(from: pageBitmapBuf, width: screenW, height: pageH)
let pageBitmap = FrameBitmap(cgImage: pageImage)!

// Walk the plan the same way the renderer does and confirm provenance.
var mismatchedRows = 0
var checkedRows = 0
var cursor = sticky.top
var pageCursor = scrolls[0]

// First frame's whole content band.
for row in 0..<plan.contentHeight {
    let outRow = cursor + row
    let srcRow = pageCursor + row
    guard srcRow < pageH, outRow < outBitmap.height else { break }
    checkedRows += 1
    if outBitmap.rowHashes[outRow] != pageBitmap.rowHashes[srcRow] { mismatchedRows += 1 }
}
cursor += plan.contentHeight

for (i, join) in plan.joins.enumerated() {
    let advance = join.advance
    // Rows contributed come from the bottom of frame i+1's band.
    let frameScroll = scrolls[i + 1]
    let bandBottomPageRow = frameScroll + contentH
    for k in 0..<advance {
        let outRow = cursor + k
        let srcRow = bandBottomPageRow - advance + k
        guard srcRow >= 0, srcRow < pageH, outRow < outBitmap.height else { continue }
        checkedRows += 1
        if outBitmap.rowHashes[outRow] != pageBitmap.rowHashes[srcRow] { mismatchedRows += 1 }
    }
    cursor += advance
}

print("      compared \(checkedRows) content rows against the original page")
check(mismatchedRows == 0, "every stitched row is byte-identical to its source (\(mismatchedRows) mismatches)")

print("\n[6] Continuity — no lost or duplicated page content across matched joins")
// Track where the previous frame's contribution ended in page coordinates. A
// matched join must resume exactly there. An unmatched join is allowed to skip —
// that is a real gap the user created by scrolling more than a screen, and the
// app's job is to flag it rather than invent content.
var pageEnd = scrolls[0] + contentH
var gaps: [String] = []
var flaggedGaps = 0
for (i, join) in plan.joins.enumerated() {
    let bandBottomPageRow = scrolls[i + 1] + contentH
    let contributedTop = bandBottomPageRow - join.advance
    if join.matched {
        if contributedTop != pageEnd {
            gaps.append("join \(i): resumed at page row \(contributedTop), expected \(pageEnd)")
        }
    } else {
        flaggedGaps += 1
        let skipped = contributedTop - pageEnd
        check(skipped > 0, "join \(i) flagged as unmatched and really did skip \(skipped) page rows")
    }
    pageEnd = bandBottomPageRow
}
check(gaps.isEmpty, gaps.isEmpty ? "matched joins resume exactly where the previous frame ended" : gaps.joined(separator: "; "))
check(flaggedGaps == 1, "the one genuine content gap was flagged (\(flaggedGaps) flagged)")

print("\n[7] Manual seam adjustment stays in bounds")
var edited = plan
edited.joins[0].advance = 999_999
let clamped = min(max(edited.joins[0].advance, 0), edited.contentHeight)
check(clamped == edited.contentHeight, "advance clamps to the content band")
if let smaller = StitchRenderer.render(plan: plan, frames: frames, scale: 0.25) {
    check(smaller.height < output.height, "preview scale produces a smaller render (\(smaller.height) < \(output.height))")
} else {
    check(false, "scaled preview render failed")
}

// A feed of visually near-identical cards — the case that defeated the previous
// Vision-based matcher, which locked onto the wrong card and scrambled the output.
// Each 200px card is structurally identical; only a narrow strip differs per card.
print("\n[8] Highly repetitive list content")
func makeRepetitivePage() -> [UInt8] {
    var p = makeBuffer(width: screenW, height: pageH)
    for y in 0..<pageH {
        let cardRow = y % 200
        for x in 0..<screenW {
            let v: UInt8 = cardRow < 8 ? 225 : (cardRow < 120 ? 255 : 247)
            setPixel(&p, screenW, x, y, v, v, v)
        }
        // Identical "icon" block in every card.
        if cardRow > 20 && cardRow < 100 {
            for x in 30..<110 { setPixel(&p, screenW, x, y, 255, 214, 10) }
        }
        // Only these rows carry per-card identity, ~5% of each card.
        if cardRow >= 130 && cardRow < 140 {
            var local = SplitMix(seed: UInt64(y / 200) &* 0x9E37_79B9)
            let start = 200 + Int(local.next() % 500)
            for x in start..<min(start + 260, screenW) {
                setPixel(&p, screenW, x, y, 40, 40, 60)
            }
        }
    }
    return p
}
let repetitivePage = makeRepetitivePage()
let repScrolls = [0, 640]
let repFrames = repScrolls.enumerated()
    .map { makeScreenshot(page: repetitivePage, scroll: $1, clockTick: $0) }
    .compactMap { FrameBitmap(cgImage: $0) }
if let m = OverlapMatcher.align(reference: repFrames[0], next: repFrames[1]) {
    check(m.offset == 640, "picked the true offset 640, not a card-period alias (got \(m.offset), score \(String(format: "%.3f", m.score)))")
} else {
    check(false, "no match found on repetitive content")
}

// Something animating inside the overlap — a spinner, a video, a live badge —
// must not stop the frames from being recognised as overlapping.
print("\n[9] Dynamic content inside the overlap")
var mutatedPage = page
for y in 1000..<1100 {
    var local = SplitMix(seed: UInt64(y) &* 77)
    for x in 0..<screenW {
        let v = UInt8(local.next() % 255)
        setPixel(&mutatedPage, screenW, x, y, v, v, v)
    }
}
let dynA = FrameBitmap(cgImage: makeScreenshot(page: page, scroll: 0, clockTick: 0))!
let dynB = FrameBitmap(cgImage: makeScreenshot(page: mutatedPage, scroll: 500, clockTick: 1))!
if let m = OverlapMatcher.align(reference: dynA, next: dynB) {
    check(m.offset == 500, "still found offset 500 with ~100 changed rows (got \(m.offset), score \(String(format: "%.3f", m.score)))")
    // The matcher locks onto the longest *unbroken* run, so the animating band
    // splits the overlap and the run is necessarily shorter than the full
    // overlap — yet the offset it yields is still exactly right.
    let fullOverlap = contentH - 500
    check(m.matchedRows < fullOverlap,
          "run stopped at the animating band (\(m.matchedRows) of \(fullOverlap) rows) but still gave the right offset")
} else {
    check(false, "dynamic content defeated the matcher")
}

// Unrelated screenshots must not be forced together.
print("\n[10] Unrelated screenshots")
var otherPage = makeBuffer(width: screenW, height: pageH)
for y in 0..<pageH {
    var local = SplitMix(seed: UInt64(y) &* 999_331)
    for x in 0..<screenW {
        let v = UInt8(local.next() % 255)
        setPixel(&otherPage, screenW, x, y, v, v, v)
    }
}
let unrelatedA = FrameBitmap(cgImage: makeScreenshot(page: page, scroll: 0, clockTick: 0))!
let unrelatedB = FrameBitmap(cgImage: makeScreenshot(page: otherPage, scroll: 0, clockTick: 1))!
let unrelatedMatch = OverlapMatcher.align(reference: unrelatedA, next: unrelatedB)
check(unrelatedMatch == nil, "refused to invent an overlap between unrelated content")

print("\n" + (failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED"))

// Write the stitched result so it can be eyeballed.
// Debug artefact so a failure can be eyeballed as well as measured.
let outURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snap-stitched.png")
if let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) {
    CGImageDestinationAddImage(dest, output, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(outURL.path) (\(output.width)x\(output.height))")
}

exit(failures == 0 ? 0 : 1)
