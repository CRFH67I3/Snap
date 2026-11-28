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
        AppLog.write("ImagePicker makeUIViewController")
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
            AppLog.write("PHPicker didFinish, results=\(results.count)")
            onDismiss()
            guard !results.isEmpty else {
                AppLog.write("PHPicker results empty -> user cancelled")
                return
            }

            // 记录每张图的原始信息（选择顺序）。
            for (i, r) in results.enumerated() {
                AppLog.write("  result[\(i)] id=\(r.assetIdentifier ?? "nil") canLoadImage=\(r.itemProvider.canLoadObject(ofClass: UIImage.self))")
            }

            // 尽量读取每张图的真实创建时间。
            let identifiers = results.compactMap { $0.assetIdentifier }
            var datesByIdentifier: [String: Date] = [:]
            if !identifiers.isEmpty {
                let fetched = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
                AppLog.write("fetchAssets localIdentifiers=\(identifiers.count) -> fetched=\(fetched.count)")
                fetched.enumerateObjects { asset, _, _ in
                    datesByIdentifier[asset.localIdentifier] = asset.creationDate ?? .distantPast
                }
            } else {
                AppLog.write("no assetIdentifiers available")
            }

            let group = DispatchGroup()
            let lock = NSLock()
            var loaded: [(index: Int, image: UIImage, date: Date)] = []

            for (index, result) in results.enumerated() {
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else {
                    AppLog.write("  result[\(index)] skipped: cannot load UIImage")
                    continue
                }
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                    defer { group.leave() }
                    if let error {
                        AppLog.write("  result[\(index)] load error: \(error.localizedDescription)")
                        return
                    }
                    guard let image = object as? UIImage else {
                        AppLog.write("  result[\(index)] load returned non-UIImage")
                        return
                    }

                    let date: Date
                    if let id = result.assetIdentifier, let real = datesByIdentifier[id] {
                        date = real
                        AppLog.write("  result[\(index)] loaded image \(Int(image.size.width))x\(Int(image.size.height)), realDate=\(real)")
                    } else {
                        date = Date.distantFuture.addingTimeInterval(-Double(index))
                        AppLog.write("  result[\(index)] loaded image \(Int(image.size.width))x\(Int(image.size.height)), fallback date")
                    }

                    lock.lock()
                    loaded.append((index, image, date))
                    lock.unlock()
                }
            }

            let callback = onPick
            group.notify(queue: .main) {
                let ordered = loaded.sorted { $0.date < $1.date }
                AppLog.write("loaded \(loaded.count)/\(results.count) images, ordered \(ordered.count), calling onPick")
                callback(ordered.map { $0.image }, ordered.map { $0.date })
            }
        }
    }
}
