import Foundation

/// Works out how two consecutive screenshots line up.
///
/// The offset `k` means content sitting at row `r` in `reference` has moved to
/// row `r - k` in `next`, so `next[i]` shows what `reference[i + k]` showed.
///
/// Candidates are scored by the **longest contiguous run** of visually matching
/// rows rather than by a plain match count. A genuine scroll yields one unbroken
/// run spanning the whole shared band; a coincidental agreement inside a uniform
/// navigation or tab bar yields only a short one, however many rows it covers.
enum OverlapMatcher {
    struct Alignment {
        /// Pixels of new content revealed in `next`.
        let offset: Int
        /// First and last+1 overlapping row, in `next` coordinates. The frozen
        /// chrome falls outside this run, which is what makes it usable for
        /// working out the sticky bands.
        let contentTop: Int
        let contentBottom: Int
        let matchedRows: Int
        /// Mean pixel-level similarity across the run, 0...1.
        let score: Double
    }

    /// Below this, a "scroll" is really just noise or a uniform band sliding
    /// against itself.
    private static let minimumOffset = 40
    /// A run shorter than this is not enough evidence of a real overlap.
    private static let minimumRunFraction = 0.055
    /// The run must genuinely correspond, not merely look similar in outline.
    private static let minimumPixelSimilarity = 0.95
    /// Candidates worth the cost of full verification.
    private static let candidatesToVerify = 12

    static func align(reference: FrameBitmap, next: FrameBitmap) -> Alignment? {
        let height = reference.height
        guard next.height == height, next.width == reference.width else { return nil }
        let minimumRun = max(90, Int(Double(height) * minimumRunFraction))

        // Pass 1 — cheap scan over every plausible offset, keeping the best runs.
        var candidates: [(offset: Int, run: Int, start: Int, end: Int)] = []
        var longestSeen = 0
        var offset = minimumOffset
        while offset < height {
            // No later offset can beat what we already have: the overlap can be
            // at most `height - offset` rows and that only shrinks from here.
            if height - offset <= longestSeen { break }

            var runStart = -1
            var best = 0, bestStart = 0, bestEnd = 0
            for i in 0..<(height - offset) {
                if FrameBitmap.signaturesMatch(reference, i + offset, next, i) {
                    if runStart < 0 { runStart = i }
                    let length = i - runStart + 1
                    if length > best { best = length; bestStart = runStart; bestEnd = i + 1 }
                } else {
                    runStart = -1
                }
            }
            if best >= minimumRun {
                candidates.append((offset, best, bestStart, bestEnd))
                longestSeen = max(longestSeen, best)
            }
            offset += 1
        }
        guard !candidates.isEmpty else { return nil }

        // Pass 2 — verify the most promising candidates properly, strongest first.
        candidates.sort { $0.run > $1.run }
        for candidate in candidates.prefix(candidatesToVerify) {
            guard hasEnoughDetail(reference, from: candidate.start + candidate.offset, to: candidate.end + candidate.offset) else {
                continue
            }
            var total = 0.0
            for i in candidate.start..<candidate.end {
                total += FrameBitmap.rowSimilarity(reference, i + candidate.offset, next, i)
            }
            let score = total / Double(max(1, candidate.end - candidate.start))
            guard score >= minimumPixelSimilarity else { continue }

            return Alignment(
                offset: candidate.offset,
                contentTop: candidate.start,
                contentBottom: candidate.end,
                matchedRows: candidate.run,
                score: score
            )
        }
        return nil
    }

    /// Number of distinct rows a run must contain to be believable.
    ///
    /// This only has to separate "a blank or uniform stretch agreeing with
    /// itself", which carries no positional information at all, from real
    /// content. It must stay low: a legitimately repetitive feed — identical
    /// card after identical card — contains very few distinct rows across
    /// hundreds of them, and is still a perfectly valid match.
    private static let minimumDistinctRows = 8

    private static func hasEnoughDetail(_ frame: FrameBitmap, from: Int, to: Int) -> Bool {
        guard from >= 0, to <= frame.height, to > from else { return false }
        var distinct = Set<UInt64>()
        for row in from..<to {
            distinct.insert(frame.rowHashes[row])
            if distinct.count >= minimumDistinctRows { return true }
        }
        return false
    }
}
