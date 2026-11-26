import Photos
import PhotosUI
import SwiftUI

/// 系统图片选择器的 SwiftUI 封装。
/// 通过 itemProvider 直接加载用户选中的图片数据，不依赖 assetIdentifier，
/// 因此在「有限访问」相册权限或 iOS 27 上也能可靠工作。
/// 同时尽量读取每张图的真实创建时间——截图时间才是正确的上下顺序依据。
struct ImagePicker: UIViewControllerRepresentable {
    /// 图片加载完成后回传（按真实创建时间从早到晚排序）。
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

            // 尽量读取每张图的真实创建时间。用户刚选中的图，其元数据在本地可用，
            // 因此通常能取到；取不到的再用选择顺序兜底。
            let identifiers = results.compactMap { $0.assetIdentifier }
            var datesByIdentifier: [String: Date] = [:]
            if !identifiers.isEmpty {
                let fetched = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
                fetched.enumerateObjects { asset, _, _ in
                    datesByIdentifier[asset.localIdentifier] = asset.creationDate ?? .distantPast
                }
            }

            let group = DispatchGroup()
            let lock = NSLock()
            var loaded: [(index: Int, image: UIImage, date: Date)] = []

            for (index, result) in results.enumerated() {
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    defer { group.leave() }
                    guard let image = object as? UIImage else { return }

                    // 有真实创建时间就用它（截图时间 = 正确上下顺序）；
                    // 否则按选择顺序排在后面。
                    let date: Date
                    if let id = result.assetIdentifier, let real = datesByIdentifier[id] {
                        date = real
                    } else {
                        date = Date.distantFuture.addingTimeInterval(-Double(index))
                    }

                    lock.lock()
                    loaded.append((index, image, date))
                    lock.unlock()
                }
            }

            // 直接捕获闭包，避免加载期间 Coordinator 被释放导致回调丢失。
            let callback = onPick
            group.notify(queue: .main) {
                // 按创建时间从早到晚：最早的（最上面）排在前。
                let ordered = loaded.sorted { $0.date < $1.date }
                callback(ordered.map { $0.image }, ordered.map { $0.date })
            }
        }
    }
}
