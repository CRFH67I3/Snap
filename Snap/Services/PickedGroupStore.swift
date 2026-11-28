import Foundation
import UIKit

/// 持久化保存用户手动选择的截图组。
/// 图片以 PNG 无损写入 Documents/PickedGroups/<groupID>/，
/// 元数据（时间、创建顺序）写入同目录的 meta.json。
/// 这样刷新、重启 App 后，手动组依然显示在主界面列表中。
enum PickedGroupStore {
    private static let root: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("PickedGroups", isDirectory: true)
    }()

    private struct Meta: Codable {
        let creationDate: Date
        let dates: [Date]
    }

    /// 保存一组手动选择的图片，返回可用于构建的 ScreenshotGroup。
    @discardableResult
    static func save(images: [UIImage], dates: [Date]) -> ScreenshotGroup? {
        guard images.count >= 2 else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)

        let groupID = "g\(Int(Date().timeIntervalSince1970 * 1000))"
        let dir = root.appendingPathComponent(groupID, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        var ids: [String] = []
        for (i, image) in images.enumerated() {
            let name = "\(i).png"
            let url = dir.appendingPathComponent(name)
            if let data = image.pngData() {
                try? data.write(to: url, options: .atomic)
                ids.append(url.path)
            }
        }
        guard ids.count == images.count else {
            try? fm.removeItem(at: dir)
            return nil
        }

        let meta = Meta(creationDate: Date(), dates: dates)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: dir.appendingPathComponent("meta.json"), options: .atomic)
        }

        AppLog.write("PickedGroupStore saved group \(groupID) with \(images.count) images")
        return makeGroup(dir: dir, meta: meta)
    }

    /// 读取所有已保存的手动组，按保存时间从新到旧。
    static func loadAll() -> [ScreenshotGroup] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var result: [(date: Date, group: ScreenshotGroup)] = []
        for dir in entries where dir.isDirectory {
            guard let group = loadGroup(dir: dir) else { continue }
            let meta = loadMeta(dir: dir)
            result.append((meta?.creationDate ?? .distantPast, group))
        }
        result.sort { $0.date > $1.date }
        AppLog.write("PickedGroupStore loaded \(result.count) groups")
        return result.map { $0.group }
    }

    private static func loadMeta(dir: URL) -> Meta? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("meta.json")) else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }

    private static func loadGroup(dir: URL) -> ScreenshotGroup? {
        guard let meta = loadMeta(dir: dir) else { return nil }
        let items: [ScreenshotItem] = meta.dates.enumerated().compactMap { index, date in
            let url = dir.appendingPathComponent("\(index).png")
            guard let image = UIImage(contentsOfFile: url.path) else { return nil }
            return ScreenshotItem(image: image, id: "saved-\(dir.lastPathComponent)-\(index)", creationDate: date)
        }
        guard items.count >= 2, items.count == meta.dates.count else { return nil }
        return ScreenshotGroup(items: items)
    }

    /// 从磁盘刚保存的目录构造组（避免重新解码一遍）。
    private static func makeGroup(dir: URL, meta: Meta) -> ScreenshotGroup? {
        loadGroup(dir: dir)
    }
}
