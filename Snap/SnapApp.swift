import SwiftUI

@main
struct SnapApp: App {
    init() {
        AppLog.write("===== App launched =====")
        AppLog.write("Documents: \(AppLog.fileURL.path)")
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}
