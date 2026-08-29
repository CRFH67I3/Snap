import SwiftUI

struct StitchEditorView: View {
    let group: ScreenshotGroup

    @StateObject private var model = StitchViewModel()
    @State private var showingAdjustments = false
    @State private var showingDecoration = false

    var body: some View {
        Group {
            switch model.stage {
            case .loading:
                ProgressView("正在读取截图…")
            case .failed(let message):
                ContentUnavailableView("无法拼接", systemImage: "exclamationmark.triangle", description: Text(message))
            case .ready:
                editor
            }
        }
        .navigationTitle("拼接预览")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if case .ready = model.stage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.saveToPhotos() }
                    } label: {
                        if model.isSaving { ProgressView() } else { Text("保存") }
                    }
                    .disabled(model.isSaving)
                }
            }
        }
        .task { await model.load(items: group.items) }
        .alert(
            model.saveMessage ?? "",
            isPresented: Binding(
                get: { model.saveMessage != nil },
                set: { if !$0 { model.saveMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { model.saveMessage = nil }
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            previewArea
            Divider()
            controls
        }
        .sheet(isPresented: $showingAdjustments) {
            model.focusedJoinID = nil
        } content: {
            SeamAdjustmentView(model: model)
                .presentationDetents([.medium, .large])
                // Keeps the preview above the sheet live and scrollable while a
                // seam is being adjusted.
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(isPresented: $showingDecoration) {
            DecorationView(model: model)
                .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        if let closeUp = model.seamCloseUp {
            // While a seam is being adjusted, the preview becomes a magnified
            // window onto that seam, anchored at the very top of the screen so
            // the adjustment sheet cannot cover it.
            SeamInspector(
                closeUp: closeUp,
                seamCount: model.plan?.joins.count ?? 1,
                onSwitch: { model.focusAdjacentSeam(by: $0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.secondarySystemBackground))
        } else {
            ScrollView {
                Group {
                    if let preview = model.preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                    } else {
                        ProgressView().padding(40)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .background(Color(.secondarySystemBackground))
        }
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 12) {
            if let plan = model.plan {
                HStack {
                    Label("\(plan.frameCount) 张", systemImage: "photo.stack")
                    Spacer()
                    Text("\(plan.frameWidth) × \(plan.totalHeight)")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)

                if plan.hasUnmatchedJoins {
                    let count = plan.joins.filter { !$0.matched }.count
                    Label(
                        "有 \(count) 处接缝找不到重叠内容，说明截图时滚动超过了一屏，中间内容已缺失。下次每滚动约半屏截一张会更稳。",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Toggle("自动去除重复的导航栏 / 输入框", isOn: $model.detectStickyRegions)
                .font(.subheadline)
                .onChange(of: model.detectStickyRegions) { _, _ in model.rebuildPlan() }

            HStack(spacing: 12) {
                Button {
                    showingAdjustments = true
                } label: {
                    Label("微调接缝", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showingDecoration = true
                } label: {
                    Label("水印 / 外框", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.bar)
    }
}

/// A magnified look at one join: the tail of the previous screenshot above the
/// line, the head of the next one below it. Content that lines up reads as one
/// continuous image across the marker.
private struct SeamInspector: View {
    let closeUp: StitchViewModel.SeamCloseUp
    let seamCount: Int
    let onSwitch: (Int) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(
                seamCount > 1
                    ? "接缝 \(closeUp.joinIndex + 1) / \(seamCount)　上下应当连成一体　左右滑动切换"
                    : "接缝 \(closeUp.joinIndex + 1)　上下应当连成一体"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            Image(uiImage: closeUp.image)
                .resizable()
                .scaledToFit()
                .overlay {
                    GeometryReader { geometry in
                        let y = geometry.size.height * closeUp.seamFraction
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(.separator), lineWidth: 0.5)
                }
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            onSwitch(value.translation.width < 0 ? 1 : -1)
                        }
                )
        }
        .padding(.top, 8)
    }
}

private struct SeamAdjustmentView: View {
    @ObservedObject var model: StitchViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showFrozenRegions = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let plan = model.plan, !plan.joins.isEmpty {
                    seamPicker(plan: plan)
                    Divider()
                    if let index = focusedIndex(in: plan) {
                        seamPanel(plan: plan, index: index)
                        Divider()
                    }
                    frozenRegions(plan: plan)
                }
                Spacer(minLength: 0)
            }
            .navigationTitle("微调接缝")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                if model.focusedJoinID == nil {
                    model.focusedJoinID = model.plan?.joins.first?.id
                }
            }
        }
    }

    private func focusedIndex(in plan: StitchPlan) -> Int? {
        guard let id = model.focusedJoinID else { return nil }
        return plan.joins.firstIndex { $0.id == id }
    }

    /// One chip per seam, pinned above the controls. Only one seam's controls are
    /// ever shown, so they keep a fixed position no matter how many screenshots
    /// were stitched — the previous vertical list pushed later seams off the
    /// bottom of the sheet.
    private func seamPicker(plan: StitchPlan) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(plan.joins.enumerated()), id: \.element.id) { index, join in
                        chip(index: index, join: join)
                            .id(join.id)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: model.focusedJoinID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .padding(.vertical, 10)
    }

    private func chip(index: Int, join: StitchPlan.Join) -> some View {
        let selected = model.focusedJoinID == join.id
        return Button {
            model.focusedJoinID = join.id
        } label: {
            HStack(spacing: 4) {
                Text("接缝 \(index + 1)")
                if !join.matched {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
                } else if join.isEdited {
                    Image(systemName: "slider.horizontal.3").font(.caption2)
                }
            }
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(chipBackground(selected: selected, matched: join.matched), in: Capsule())
            .foregroundStyle(chipForeground(selected: selected, matched: join.matched))
        }
        .buttonStyle(.plain)
    }

    private func chipBackground(selected: Bool, matched: Bool) -> Color {
        guard selected else { return Color(.secondarySystemFill) }
        return matched ? Color.accentColor : Color.orange
    }

    private func chipForeground(selected: Bool, matched: Bool) -> Color {
        if selected { return .white }
        return matched ? .primary : .orange
    }

    private func seamPanel(plan: StitchPlan, index: Int) -> some View {
        let join = plan.joins[index]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("第 \(index + 2) 张新增")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(join.advance) px")
                    .font(.title3.monospacedDigit().weight(.medium))
                if join.isEdited {
                    Button("重置") { model.resetAdvance(joinID: join.id) }
                        .font(.footnote)
                        .buttonStyle(.borderless)
                }
            }

            HStack(spacing: 10) {
                NudgeButton(systemImage: "minus") {
                    model.nudgeAdvance(joinID: join.id, by: -1)
                }
                Slider(
                    value: Binding(
                        get: { Double(join.advance) },
                        set: { model.updateAdvance(joinID: join.id, to: Int($0.rounded())) }
                    ),
                    in: 0...Double(max(join.maximumAdvance, 1))
                )
                NudgeButton(systemImage: "plus") {
                    model.nudgeAdvance(joinID: join.id, by: 1)
                }
            }

            statusLine(join)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func statusLine(_ join: StitchPlan.Join) -> some View {
        if !join.matched {
            Label("这两张之间没有重叠内容，中间有一段没被截到", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            Text("自动对齐 · 吻合度 \(Int((join.score * 100).rounded()))%　滑块粗调，± 每次 1 像素（可按住）")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func frozenRegions(plan: StitchPlan) -> some View {
        DisclosureGroup(isExpanded: $showFrozenRegions) {
            VStack(spacing: 12) {
                frozenRow("顶部", value: plan.sticky.top, edge: .top)
                frozenRow("底部", value: plan.sticky.bottom, edge: .bottom)
                Text("导航栏、标签栏这类不滚动的部分，在成品里只保留一次。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Text("冻结区域").font(.subheadline)
                Spacer()
                Text("顶 \(plan.sticky.top) · 底 \(plan.sticky.bottom)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func frozenRow(_ title: String, value: Int, edge: StitchViewModel.StickyEdge) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.subheadline)
            Spacer()
            Text("\(value) px")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            NudgeButton(systemImage: "minus") { model.nudgeSticky(edge, by: -2) }
            NudgeButton(systemImage: "plus") { model.nudgeSticky(edge, by: 2) }
        }
    }
}

/// A ± button that keeps firing while held, speeding up the longer it is down,
/// so a seam can be walked several tens of pixels without tapping that many times.
private struct NudgeButton: View {
    let systemImage: String
    let action: () -> Void

    @State private var repeatTask: Task<Void, Never>?
    @State private var isPressed = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 40, height: 32)
            .background(
                Color.accentColor.opacity(isPressed ? 0.28 : 0.13),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
            // A plain Button inside a sheet swallows the press state needed for
            // auto-repeat, so the press is tracked directly.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isPressed { begin() } }
                    .onEnded { _ in end() }
            )
            .accessibilityLabel(systemImage == "plus" ? "增加" : "减少")
            .onDisappear { end() }
    }

    private func begin() {
        isPressed = true
        action()
        repeatTask = Task { @MainActor in
            // Hold before repeating, so a quick tap stays a single step.
            try? await Task.sleep(nanoseconds: 420_000_000)
            var interval: UInt64 = 110_000_000
            while !Task.isCancelled {
                action()
                try? await Task.sleep(nanoseconds: interval)
                interval = max(22_000_000, interval - 9_000_000)
            }
        }
    }

    private func end() {
        isPressed = false
        repeatTask?.cancel()
        repeatTask = nil
    }
}


private struct DecorationView: View {
    @ObservedObject var model: StitchViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("水印") {
                    TextField("水印文字（留空则不加）", text: $model.decoration.watermarkText)
                    Toggle("平铺水印", isOn: $model.decoration.watermarkTiled)
                        .disabled(model.decoration.watermarkText.isEmpty)
                }
                Section("外框") {
                    Toggle("圆角外框", isOn: $model.decoration.roundedFrame)
                }
            }
            .navigationTitle("水印 / 外框")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onChange(of: model.decoration) { _, _ in
                model.refreshPreviewForDecorationChange()
            }
        }
    }
}
