import Photos
import UIKit

struct ScreenshotItem: Identifiable, Hashable {
    let id: String
    /// 自动分组时来自相册；手动选图时为 nil（直接用 image）。
    let asset: PHAsset?
    /// 手动选图时由系统图片选择器直接加载的图片。
    let image: UIImage?
    let creationDate: Date
    let pixelWidth: Int
    let pixelHeight: Int

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.image = nil
        self.creationDate = asset.creationDate ?? .distantPast
        self.pixelWidth = asset.pixelWidth
        self.pixelHeight = asset.pixelHeight
    }

    init(image: UIImage, id: String, creationDate: Date) {
        self.id = id
        self.asset = nil
        self.image = image
        self.creationDate = creationDate
        self.pixelWidth = Int(image.size.width * image.scale)
        self.pixelHeight = Int(image.size.height * image.scale)
    }

    static func == (lhs: ScreenshotItem, rhs: ScreenshotItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A run of screenshots taken close together — almost always one long-screenshot
/// attempt, which is what lets the app offer the right group without the user
/// hunting through their camera roll.
struct ScreenshotGroup: Identifiable {
    let id = UUID()
    var items: [ScreenshotItem]

    var startDate: Date { items.first?.creationDate ?? .distantPast }
    var count: Int { items.count }
}
