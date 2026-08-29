import Photos
import UIKit

struct ScreenshotItem: Identifiable, Hashable {
    let id: String
    let asset: PHAsset
    let creationDate: Date
    let pixelWidth: Int
    let pixelHeight: Int

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.creationDate = asset.creationDate ?? .distantPast
        self.pixelWidth = asset.pixelWidth
        self.pixelHeight = asset.pixelHeight
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
