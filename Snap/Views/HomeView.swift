import Photos
import SwiftUI

struct HomeView: View {
    @State private var status: PHAuthorizationStatus = .notDetermined
    @State private var groups: [ScreenshotGroup] = []
    @State private var isLoading = true
    @State private var showingImportFlow = false

    /// 手动导入流程的中间数据：选中的图片与创建时间。
    @State private var importedImages: [UIImage] = []
    @State private var importedDates: [Date] = []

    var body: some View {
        NavigationStack {
            Group {
                switch status {
                case .authorized, .limited:
                    groupList
                case .notDetermined:
                    ProgressView("正在请求相册权限…")
                default:
                    permissionDenied
                }
            }
            .navigationTitle("长截图")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .sheet(isPresented: $showingImportFlow) {
                ImportFlowView(
                    images: $importedImages,
                    dates: $importedDates,
                    onFinish: { showingImportFlow = false },
                    onCancel: { showingImportFlow = false }
                )
            }
        }
        .task {
            status = await PhotoLibraryService.requestAuthorization()
            reload()
        }
    }

    private var groupList: some View {
        List {
            Section {
                Text("在任意 App 里一边滚动一边连续截图，回到这里选择那一组截图即可拼接。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if isLoading {
                HStack { ProgressView(); Text("正在查找截图…") }
            } else if groups.isEmpty {
                VStack(spacing: 16) {
                    Button {
                        AppLog.write(">>> User tapped 选择更多图片")
                        showingImportFlow = true
                    } label: {
                        Label("选择更多图片", systemImage: "photo.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    ContentUnavailableView(
                        "没有找到成组的截图",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("连续拍摄的两张以上、尺寸相同的截图会显示在这里。也可以点上方按钮手动选择图片拼接。")
                    )
                }
                .listRowInsets(EdgeInsets())
            } else {
                ForEach(groups) { group in
                    NavigationLink {
                        StitchEditorView(group: group)
                    } label: {
                        GroupRow(group: group)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var permissionDenied: some View {
        ContentUnavailableView {
            Label("需要相册访问权限", systemImage: "lock")
        } description: {
            Text("Snap 需要读取相册里的截图才能拼接。请在「设置 → 隐私与安全性 → 照片」中允许访问。")
        } actions: {
            Button("打开设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    private func reload() {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let found = PhotoLibraryService.fetchScreenshotGroups()
            await MainActor.run {
                groups = found
                isLoading = false
            }
        }
    }
}

private struct GroupRow: View {
    let group: ScreenshotGroup
    @State private var thumbnails: [UIImage] = []

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: -18) {
                ForEach(Array(thumbnails.prefix(3).enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color(.systemBackground), lineWidth: 1.5)
                        )
                }
            }
            .frame(width: 84, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(group.count) 张截图")
                    .font(.body)
                Text(group.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            guard thumbnails.isEmpty else { return }
            var loaded: [UIImage] = []
            for item in group.items.prefix(3) {
                if let image = await PhotoLibraryService.loadThumbnail(
                    for: item, targetSize: CGSize(width: 120, height: 186)
                ) {
                    loaded.append(image)
                }
            }
            thumbnails = loaded
        }
    }
}
