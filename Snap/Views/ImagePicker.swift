import PhotosUI
import SwiftUI

/// 系统图片选择器的 SwiftUI 封装。
/// 通过 itemProvider 直接加载用户选中的图片数据，不依赖 assetIdentifier，
/// 因此在「有限访问」相册权限或 iOS 27 上也能可靠工作。
struct ImagePicker: UIViewControllerRepresentable {
    /// 图片加载完成后回传（用户选择顺序即阅读顺序）。
    let onPick: ([UIImage], [Date]) -> Void
    /// 立即关闭选择器，由外层切换 presenting 状态。
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 0 // 不限制选择数量
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onDismiss: onDismiss)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPick: ([UIImage], [Date]) -> Void
        private let onDismiss: () -> Void

        init(onPick: @escaping ([UIImage], [Date]) -> Void, onDismiss: @escaping () -> Void) {
            self.onPick = onPick
            self.onDismiss = onDismiss
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // 先让外层关闭选择器，避免手动 dismiss 与状态切换冲突。
            onDismiss()
            guard !results.isEmpty else { return }

            let group = DispatchGroup()
            let lock = NSLock()
            var loaded: [(Int, UIImage)] = []

            for (index, result) in results.enumerated() {
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    defer { group.leave() }
                    guard let image = object as? UIImage else { return }
                    lock.lock()
                    loaded.append((index, image))
                    lock.unlock()
                }
            }

            // 直接捕获闭包，避免加载期间 Coordinator 被释放导致回调丢失。
            let callback = onPick
            group.notify(queue: .main) {
                // 按用户选择顺序排列；赋予递增时间，保证按创建时间排序后顺序不变。
                let ordered = loaded.sorted { $0.0 < $1.0 }.map { $0.1 }
                let now = Date()
                let dates = ordered.indices.map { now.addingTimeInterval(Double($0)) }
                callback(ordered, dates)
            }
        }
    }
}
