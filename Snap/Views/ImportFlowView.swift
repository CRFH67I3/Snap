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
                            images = orderedImages
                            dates = orderedDates
                            if let group = PhotoLibraryService.group(fromPickedImages: images, creationDates: dates) {
                                AppLog.write("group created with \(group.count) items -> editing")
                                phase = .editing(group)
                            } else {
                                AppLog.write("group creation FAILED (<2 images) -> cancel")
                                onCancel()
                            }
                        },
                        onCancel: {
                            AppLog.write("OrderConfirm cancelled")
                            onCancel()
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
