import Photos
import PhotosUI
import SwiftUI

/// 系统图片选择器的 SwiftUI 封装。
/// 用户手动选出的图片通过 PHAsset 标识符交回现有拼接流程，
/// 这里不复制、不重新编码任何图片。
struct ImagePicker: UIViewControllerRepresentable {
    let onPick: ([PHAsset]) -> Void

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
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPick: ([PHAsset]) -> Void

        init(onPick: @escaping ([PHAsset]) -> Void) {
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // 呈现由外层 .sheet(item:) 统一管理；这里只回传结果，
            // 不手动 dismiss，避免出现两个 sheet 的时序冲突。
            let identifiers = results.compactMap { $0.assetIdentifier }
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            var assets: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in assets.append(asset) }
            // 拼接流程要求按阅读顺序（时间从早到晚）排列。
            assets.sort { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
            onPick(assets)
        }
    }
}
