import Foundation

/// The editable recipe for a long screenshot.
///
/// The plan is deliberately kept as plain numbers rather than baked pixels so the
/// preview can re-render instantly while the user drags a seam.
struct StitchPlan {
    /// One join per screenshot after the first.
    struct Join: Identifiable {
        let id = UUID()
        /// Rows of genuinely new content this screenshot contributes. Editable.
        var advance: Int
        /// What the matcher proposed, kept so the user can reset a manual tweak.
        let automaticAdvance: Int
        /// False when no overlap was found and the frames are simply butted
        /// together — the case most likely to need a manual fix.
        let matched: Bool
        /// Match strength, 0...1. Only meaningful when `matched`.
        let score: Double
        /// Upper bound: a screenshot cannot contribute more than its scrolling band.
        let maximumAdvance: Int

        var isEdited: Bool { advance != automaticAdvance }
    }

    var sticky: StickyRegionDetector.Regions
    var joins: [Join]
    let frameCount: Int
    let frameWidth: Int
    let frameHeight: Int

    /// Height of the scrolling band, i.e. the frame minus the frozen chrome.
    var contentHeight: Int { frameHeight - sticky.top - sticky.bottom }

    var totalHeight: Int {
        sticky.top + contentHeight + joins.reduce(0) { $0 + $1.advance } + sticky.bottom
    }

    var hasUnmatchedJoins: Bool { joins.contains { !$0.matched } }

    /// Output row where the given join's appended content begins — i.e. the
    /// visible seam where the previous screenshot's tail meets the next one's head.
    ///
    /// Note this position does *not* move while that join's own advance is being
    /// dragged: changing how much frame `index + 1` contributes only extends the
    /// image below the seam. That is what lets the preview keep the seam pinned
    /// steadily on screen during an adjustment.
    func seamRow(atJoinIndex index: Int) -> Int {
        var row = sticky.top + contentHeight
        for i in 0..<min(max(index, 0), joins.count) { row += joins[i].advance }
        return row
    }
}

enum StitchEngine {
    /// Aligns every consecutive pair. This is the expensive step, and it does not
    /// depend on the frozen bands, so callers compute it once and reuse it while
    /// the user adjusts things.
    static func align(frames: [FrameBitmap]) -> [OverlapMatcher.Alignment?] {
        zip(frames, frames.dropFirst()).map { OverlapMatcher.align(reference: $0, next: $1) }
    }

    static func makePlan(
        frames: [FrameBitmap],
        alignments: [OverlapMatcher.Alignment?],
        detectSticky: Bool
    ) -> StitchPlan? {
        guard let first = frames.first else { return nil }
        guard frames.allSatisfy({ $0.width == first.width && $0.height == first.height }) else { return nil }

        let sticky = detectSticky
            ? StickyRegionDetector.detect(frames: frames, alignments: alignments)
            : .none
        let contentHeight = first.height - sticky.top - sticky.bottom

        return StitchPlan(
            sticky: sticky,
            joins: makeJoins(alignments: alignments, contentHeight: contentHeight),
            frameCount: frames.count,
            frameWidth: first.width,
            frameHeight: first.height
        )
    }

    /// Rebuilds the joins for a given content band, e.g. after the user adjusts
    /// the frozen regions. Cheap: the alignment work is already done.
    static func makeJoins(
        alignments: [OverlapMatcher.Alignment?],
        contentHeight: Int
    ) -> [StitchPlan.Join] {
        alignments.map { alignment in
            // An offset larger than the band means the frames share nothing
            // usable, so treat it as no overlap rather than clamping it into a
            // fake alignment.
            if let alignment, alignment.offset <= contentHeight {
                return StitchPlan.Join(
                    advance: alignment.offset,
                    automaticAdvance: alignment.offset,
                    matched: true,
                    score: alignment.score,
                    maximumAdvance: contentHeight
                )
            }
            // No overlap: the user scrolled a whole screen or more, so some
            // content is genuinely missing. Contribute the full band — chrome
            // still excluded — and flag the gap rather than inventing pixels.
            return StitchPlan.Join(
                advance: contentHeight,
                automaticAdvance: contentHeight,
                matched: false,
                score: 0,
                maximumAdvance: contentHeight
            )
        }
    }
}
