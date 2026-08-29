import Photos
import UIKit

enum PhotoLibraryService {
    /// Screenshots taken more than this far apart belong to different attempts.
    private static let groupingWindow: TimeInterval = 90

    static func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Recent screenshots, newest first, clustered into runs.
    static func fetchScreenshotGroups(limit: Int = 120) -> [ScreenshotGroup] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "(mediaSubtypes & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        options.fetchLimit = limit

        let result = PHAsset.fetchAssets(with: .image, options: options)
        var items: [ScreenshotItem] = []
        result.enumerateObjects { asset, _, _ in items.append(ScreenshotItem(asset: asset)) }

        return group(items: items)
    }

    /// Splits newest-first screenshots into runs, returning each run in reading
    /// order (oldest first) because that is the order they stitch in.
    static func group(items: [ScreenshotItem]) -> [ScreenshotGroup] {
        var groups: [ScreenshotGroup] = []
        var current: [ScreenshotItem] = []

        for item in items {
            if let previous = current.last {
                let sameSize = previous.pixelWidth == item.pixelWidth
                    && previous.pixelHeight == item.pixelHeight
                let closeInTime = previous.creationDate.timeIntervalSince(item.creationDate) <= groupingWindow
                if !(sameSize && closeInTime) {
                    groups.append(ScreenshotGroup(items: current.reversed()))
                    current = []
                }
            }
            current.append(item)
        }
        if !current.isEmpty { groups.append(ScreenshotGroup(items: current.reversed())) }

        return groups.filter { $0.count >= 2 }
    }

    static func loadThumbnail(for item: ScreenshotItem, targetSize: CGSize) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: item.asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // Opportunistic delivery can call back twice; only the final,
                // non-degraded result should complete the continuation.
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded, !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }

    /// Loads the untouched, full-resolution pixels. Exactness matters here — the
    /// whole stitching approach depends on identical content producing identical
    /// bytes, so no resizing or re-encoding may happen on the way in.
    static func loadFullResolutionImage(for item: ScreenshotItem) async -> CGImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isNetworkAccessAllowed = true
        options.version = .current

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(
                for: item.asset,
                options: options
            ) { data, _, _, _ in
                guard let data,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    static func save(image: CGImage) async throws {
        let uiImage = UIImage(cgImage: image)
        guard let data = uiImage.pngData() else {
            throw NSError(
                domain: "Snap", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无法编码长截图"]
            )
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }
}
