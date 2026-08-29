import Photos
import SwiftUI

@MainActor
final class StitchViewModel: ObservableObject {
    enum Stage: Equatable {
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var stage: Stage = .loading
    @Published private(set) var plan: StitchPlan?
    @Published private(set) var preview: UIImage?

    /// A magnified window onto the seam being adjusted, shown pinned at the top
    /// of the screen. Scrolling a very tall preview to the right spot cannot
    /// work while a sheet covers the lower half, so the seam comes to the user
    /// instead — and close up, where misalignment is actually visible.
    struct SeamCloseUp {
        let image: UIImage
        /// Where the seam sits within `image`, 0...1 from the top.
        let seamFraction: Double
        let joinIndex: Int
    }
    @Published private(set) var seamCloseUp: SeamCloseUp?

    /// The seam currently being adjusted.
    @Published var focusedJoinID: UUID? {
        didSet { if focusedJoinID != oldValue { scheduleRender() } }
    }
    @Published var decoration = DecorationOptions()
    @Published var detectStickyRegions = true
    @Published private(set) var isSaving = false
    @Published var saveMessage: String?

    private var frames: [FrameBitmap] = []
    private var alignments: [OverlapMatcher.Alignment?] = []
    private var previewTask: Task<Void, Never>?
    private var closeUpTask: Task<Void, Never>?

    /// Preview renders at a fraction of full resolution so seam edits stay
    /// interactive on a capture that may be tens of thousands of pixels tall.
    private let previewScale: CGFloat = 0.28

    func load(items: [ScreenshotItem]) async {
        stage = .loading
        var loaded: [FrameBitmap] = []

        for item in items {
            guard let image = await PhotoLibraryService.loadFullResolutionImage(for: item) else {
                stage = .failed("有截图读取失败，请重试。")
                return
            }
            guard let bitmap = FrameBitmap(cgImage: image) else {
                stage = .failed("有截图无法解析。")
                return
            }
            loaded.append(bitmap)
        }

        guard loaded.count >= 2 else {
            stage = .failed("至少需要两张截图才能拼接。")
            return
        }
        guard let first = loaded.first,
              loaded.allSatisfy({ $0.width == first.width && $0.height == first.height }) else {
            stage = .failed("这些截图尺寸不一致，无法拼接。")
            return
        }

        frames = loaded
        // Aligning is the expensive step and is independent of the frozen bands,
        // so it runs once here and every later adjustment reuses the result.
        alignments = await Task.detached(priority: .userInitiated) {
            StitchEngine.align(frames: loaded)
        }.value
        rebuildPlan()
        stage = .ready
    }

    func rebuildPlan() {
        guard let newPlan = StitchEngine.makePlan(
            frames: frames, alignments: alignments, detectSticky: detectStickyRegions
        ) else {
            stage = .failed("无法分析这组截图。")
            return
        }
        plan = newPlan
        schedulePreview()
    }

    func updateAdvance(joinID: UUID, to value: Int) {
        guard var current = plan,
              let index = current.joins.firstIndex(where: { $0.id == joinID }) else { return }
        current.joins[index].advance = min(max(value, 0), current.joins[index].maximumAdvance)
        plan = current
        schedulePreview()
    }

    /// Applies a relative nudge, reading the current value from the model rather
    /// than from a captured one.
    ///
    /// This matters for the hold-to-repeat buttons: the repeating task holds the
    /// closure captured when the press began, so anything computed from a value
    /// captured at view-build time would stay frozen at its original reading and
    /// the seam would move exactly one step no matter how long the button is held.
    func nudgeAdvance(joinID: UUID, by delta: Int) {
        guard var current = plan,
              let index = current.joins.firstIndex(where: { $0.id == joinID }) else { return }
        let join = current.joins[index]
        let updated = min(max(join.advance + delta, 0), join.maximumAdvance)
        guard updated != join.advance else { return }
        current.joins[index].advance = updated
        plan = current
        scheduleRender()
    }

    enum StickyEdge { case top, bottom }

    func nudgeSticky(_ edge: StickyEdge, by delta: Int) {
        guard let current = plan else { return }
        switch edge {
        case .top: updateSticky(top: current.sticky.top + delta)
        case .bottom: updateSticky(bottom: current.sticky.bottom + delta)
        }
    }

    /// Moves focus to a neighbouring seam, clamped at the ends.
    func focusAdjacentSeam(by delta: Int) {
        guard let plan, !plan.joins.isEmpty else { return }
        let current = focusedJoinID.flatMap { id in plan.joins.firstIndex { $0.id == id } } ?? 0
        let next = min(max(current + delta, 0), plan.joins.count - 1)
        guard next != current else { return }
        focusedJoinID = plan.joins[next].id
    }

    func resetAdvance(joinID: UUID) {
        guard var current = plan,
              let index = current.joins.firstIndex(where: { $0.id == joinID }) else { return }
        current.joins[index].advance = current.joins[index].automaticAdvance
        plan = current
        schedulePreview()
    }

    func updateSticky(top: Int? = nil, bottom: Int? = nil) {
        guard var current = plan else { return }
        let maximum = current.frameHeight / 3
        if let top { current.sticky.top = min(max(top, 0), maximum) }
        if let bottom { current.sticky.bottom = min(max(bottom, 0), maximum) }
        // The joins are bounded by the scrolling band, so they are rebuilt
        // whenever that band changes — but the alignment work is not redone.
        current.joins = StitchEngine.makeJoins(
            alignments: alignments, contentHeight: current.contentHeight
        )
        plan = current
        schedulePreview()
    }

    private func schedulePreview() { scheduleRender() }

    /// The two renders run on their own schedules on purpose. The seam close-up
    /// is a few hundred rows and is what the user is actually watching while
    /// nudging a value, so it refreshes almost immediately. The full preview can
    /// be tens of thousands of rows, so it waits until the nudging stops —
    /// otherwise holding the − / + button would starve both.
    private func scheduleRender() {
        scheduleCloseUpRender()
        scheduleFullPreviewRender()
    }

    private func scheduleCloseUpRender() {
        closeUpTask?.cancel()
        guard let plan,
              let focusedID = focusedJoinID,
              let focusedIndex = plan.joins.firstIndex(where: { $0.id == focusedID }) else {
            seamCloseUp = nil
            return
        }
        let frames = self.frames

        closeUpTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled else { return }

            let window = await Task.detached(priority: .userInitiated) {
                StitchRenderer.renderSeamWindow(
                    plan: plan, frames: frames, joinIndex: focusedIndex, radius: Self.seamWindowRadius
                )
            }.value

            guard !Task.isCancelled, let window else { return }
            await MainActor.run {
                self?.seamCloseUp = SeamCloseUp(
                    image: UIImage(cgImage: window.image),
                    seamFraction: window.seamFraction,
                    joinIndex: focusedIndex
                )
            }
        }
    }

    private func scheduleFullPreviewRender() {
        previewTask?.cancel()
        guard let plan else { return }
        let frames = self.frames
        let scale = previewScale
        let decoration = self.decoration

        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }

            let image: UIImage? = await Task.detached(priority: .userInitiated) {
                guard var rendered = StitchRenderer.render(plan: plan, frames: frames, scale: scale) else {
                    return nil
                }
                if !decoration.isIdentity, let decorated = Decorator.apply(decoration, to: rendered) {
                    rendered = decorated
                }
                return UIImage(cgImage: rendered)
            }.value

            guard !Task.isCancelled else { return }
            await MainActor.run { self?.preview = image }
        }
    }

    /// Output rows shown either side of the seam in the close-up.
    private static let seamWindowRadius = 320

    func refreshPreviewForDecorationChange() { scheduleRender() }

    func saveToPhotos() async {
        guard let plan, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let frames = self.frames
        let decoration = self.decoration

        let result: CGImage? = await Task.detached(priority: .userInitiated) {
            guard var rendered = StitchRenderer.render(plan: plan, frames: frames, scale: 1) else {
                return nil
            }
            if !decoration.isIdentity, let decorated = Decorator.apply(decoration, to: rendered) {
                rendered = decorated
            }
            return rendered
        }.value

        guard let result else {
            saveMessage = "生成长截图失败。"
            return
        }
        do {
            try await PhotoLibraryService.save(image: result)
            saveMessage = "已保存到相册"
        } catch {
            saveMessage = "保存失败：\(error.localizedDescription)"
        }
    }
}
