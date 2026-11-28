import Foundation

/// 轻量日志：追加写入 App 的 Documents/SnapLog.txt。
/// 通过 Info.plist 的 UIFileSharingEnabled，该文件在 iOS「文件」App 中可见，
/// 方便在没有 Xcode 控制台的情况下排查选图流程。
enum AppLog {
    /// 日志文件位置（Documents 根目录，便于「文件」App 找到）。
    static let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("SnapLog.txt")
    }()

    private static let lock = NSLock()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// 追加一行日志。线程安全，失败静默（日志不应影响主流程）。
    static func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        // DateFormatter 不是线程安全的，必须在锁内使用。
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        let path = fileURL.path
        if FileManager.default.fileExists(atPath: path) {
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// 清空日志。
    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
