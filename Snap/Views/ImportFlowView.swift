import PhotosUI
import SwiftUI

/// 手动导入的完整流程：选图 → 确认顺序 → 拼接预览。
/// 用三段式 sheet 状态机，避免多个 sheet 切换的时序问题。
struct ImportFlowView: View {
    @Binding var images: [UIImage]
    @Binding var dates: [Date]
    let onFinish: () -> Void
    let onCancel: () -> Void

    private enum Phase {
        case picking
        case ordering
        case editing(ScreenshotGroup)
    }

    @State private var phase: Phase = .picking

    /// 保存为唯一的一组（清空旧组），成功返回可用于编辑器的组。
    private func saveAsOnlyGroup(_ imgs: [UIImage], _ ds: [Date]) -> ScreenshotGroup? {
        images = imgs
        dates = ds
        guard let saved = PickedGroupStore.save(images: imgs, dates: ds) else {
            AppLog.write("group save FAILED (<2 images)")
            return nil
        }
        AppLog.write("group saved with \(saved.count) items")
        return saved
    }

    var body: some View {
        Group {
            switch phase {
            case .picking:
                // 选图 sheet 覆盖时的占位页。
                Color.clear
                    .onAppear { /* picker 由下面的 sheet 呈现 */ }
            case .ordering:
                NavigationStack {
                    OrderConfirmView(
                        images: images,
                        dates: dates,
                        onConfirm: { orderedImages, orderedDates in
                            AppLog.write("OrderConfirm onConfirm: \(orderedImages.count) images")
                            if let saved = saveAsOnlyGroup(orderedImages, orderedDates) {
                                phase = .editing(saved)
                            } else {
                                onCancel()
                            }
                        },
                        onCancel: { orderedImages, orderedDates in
                            AppLog.write("OrderConfirm cancelled -> still save as only group")
                            // 取消也当作唯一一次选择：保存后直接返回主界面。
                            if saveAsOnlyGroup(orderedImages, orderedDates) != nil {
                                onFinish()
                            } else {
                                onCancel()
                            }
                        }
                    )
                }
            case .editing(let group):
                NavigationStack {
                    StitchEditorView(group: group)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("完成") { onFinish() }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { if case .picking = phase { return true } else { return false } },
            set: { if !$0 { if case .picking = phase { onCancel() } } }
        )) {
            ImagePicker(
                onPick: { pickedImages, pickedDates in
                    AppLog.write("ImportFlow onPick received \(pickedImages.count) images")
                    guard !pickedImages.isEmpty else {
                        AppLog.write("onPick empty -> cancel")
                        onCancel()
                        return
                    }
                    images = pickedImages
                    dates = pickedDates
                    // 延迟一帧切换，让 sheet 先关闭再换内容，转场更稳。
                    DispatchQueue.main.async {
                        AppLog.write("switching phase -> ordering")
                        phase = .ordering
                    }
                },
                onDismiss: {}
            )
        }
    }
}
