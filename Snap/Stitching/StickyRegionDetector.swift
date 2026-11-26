import Foundation

/// Finds the bands at the top and bottom of the screen that do not scroll —
/// status bar, navigation bar, search field, tab bar, chat input box, home
/// indicator.
///
/// These are excluded from the scrolling content, so the finished long image
/// shows them once instead of repeating them at every seam. That holds even
/// when two screenshots do not overlap at all: the chrome is still chrome.
enum StickyRegionDetector {
    struct Regions: Equatable {
        var top: Int
        var bottom: Int

        static let none = Regions(top: 0, bottom: 0)
    }

    /// Rows this similar count as unchanged. Well below 1.0 on purpose: the
    /// status bar clock ticks over, and app chrome often carries a rotating
    /// search placeholder or a live badge. Demanding byte equality stops the
    /// scan on the very first such row and leaves the whole navigation bar
    /// classified as scrolling content.
    private static let frozenRowSimilarity = 0.80

    /// How many consecutive changed rows end the band. Isolated changed rows
    /// inside the chrome are tolerated; a sustained block of them is content.
    private static let sustainedChangeRows = 24

    /// Chrome never plausibly covers this much of the screen; beyond it we are
    /// reading a blank content area as if it were a bar.
    private static let maxBandFraction = 0.35

    static func detect(frames: [FrameBitmap], alignments: [OverlapMatcher.Alignment?]) -> Regions {
        let inPlace = detectFrozenInPlace(frames: frames)
        guard let fromMotion = detectFromMotion(frames: frames, alignments: alignments) else {
            return inPlace
        }
        // The two estimates fail in opposite directions: the in-place scan can
        // over-reach across uniform content, while the motion-derived one falls
        // short when its matching run was cut off by something animating.
        //
        // We take the LARGER of each. Under-estimating a frozen band is much
        // worse than over-estimating it: a missed bottom band (e.g. Safari's
        // address bar) makes that chrome count as scrolling content, so it gets
        // drawn again at every seam. Over-estimating only risks dropping a thin
        // strip of uniform content, and `maxBandFraction` already caps how far
        // either estimate can reach.
        return Regions(
            top: max(inPlace.top, fromMotion.top),
            bottom: max(inPlace.bottom, fromMotion.bottom)
        )
    }

    /// Derives the bands from where the content actually moved: the matching run
    /// spans exactly the scrolling region, so everything outside it is chrome.
    private static func detectFromMotion(
        frames: [FrameBitmap], alignments: [OverlapMatcher.Alignment?]
    ) -> Regions? {
        guard let height = frames.first?.height else { return nil }
        var tops: [Int] = []
        var bottoms: [Int] = []
        for alignment in alignments.compactMap({ $0 }) {
            tops.append(alignment.contentTop)
            bottoms.append(max(0, height - alignment.offset - alignment.contentBottom))
        }
        guard let top = tops.min(), let bottom = bottoms.min() else { return nil }
        return Regions(top: top, bottom: bottom)
    }

    /// Scans for rows that stay put across every screenshot. This is the only
    /// signal available when nothing overlaps, and it is the more accurate of
    /// the two for tab bars, which really are pixel-identical.
    private static func detectFrozenInPlace(frames: [FrameBitmap]) -> Regions {
        guard let reference = frames.first, frames.count >= 2 else { return .none }
        let others = Array(frames.dropFirst())
        guard others.allSatisfy({
            $0.height == reference.height && $0.bytesPerRow == reference.bytesPerRow
        }) else { return .none }

        let limit = Int(Double(reference.height) * maxBandFraction)

        func isFrozen(_ row: Int) -> Bool {
            others.allSatisfy {
                FrameBitmap.rowSimilarity(reference, row, $0, row) >= frozenRowSimilarity
            }
        }

        func bandLength(rowAt: (Int) -> Int) -> Int {
            var lastFrozen = -1
            var changed = 0
            var index = 0
            while index < limit {
                if isFrozen(rowAt(index)) {
                    lastFrozen = index
                    changed = 0
                } else {
                    changed += 1
                    if changed >= sustainedChangeRows { break }
                }
                index += 1
            }
            return lastFrozen + 1
        }

        let top = bandLength { $0 }
        let bottom = bandLength { reference.height - 1 - $0 }

        guard top + bottom < reference.height else { return .none }
        return Regions(top: top, bottom: bottom)
    }
}
