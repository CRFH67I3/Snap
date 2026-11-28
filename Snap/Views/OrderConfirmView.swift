import SwiftUI

/// 让用户确认/调整截图的上下顺序。
/// 顺序：从上到下，即拼接后长图从顶部到底部。
/// 作为纯内容视图，由外层 NavigationStack 管理导航。
struct OrderConfirmView: View {
    @State private var items: [Item]
    /// 下一步：按当前顺序回传，由外层保存为唯一组并进入编辑器。
    let onConfirm: ([UIImage], [Date]) -> Void
    /// 取消：同样回传当前图片，由外层保存为唯一组但不进入编辑器。
    let onCancel: ([UIImage], [Date]) -> Void

    init(images: [UIImage], dates: [Date],
         onConfirm: @escaping ([UIImage], [Date]) -> Void,
         onCancel: @escaping ([UIImage], [Date]) -> Void) {
        _items = State(initialValue: zip(images, dates).map { Item(image: $0.0, date: $0.1) })
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    private struct Item: Identifiable {
        let id = UUID()
        let image: UIImage
        let date: Date
    }

    /// 显示到毫秒（3 位小数秒），便于区分相邻截图的先后顺序。
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            Text("拖动调整顺序，从上到下即长图从上到下")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

            List {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        Image(uiImage: item.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 66)
                            .clipShape(RoundedRectangle(cornerRadius: 5))

                        Text(Self.timeFormatter.string(from: item.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                }
                .onMove { source, destination in
                    items.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
        }
        .navigationTitle("确认顺序")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    // 取消也把当前选中的图片回传，外层保存为唯一组后直接返回。
                    onCancel(currentImages(), currentDates())
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("下一步") {
                    onConfirm(currentImages(), currentDates())
                }
            }
        }
    }

    /// 当前顺序的图片。
    private func currentImages() -> [UIImage] { items.map { $0.image } }

    /// 重新赋予严格递增的日期，保证后续按创建时间排序时顺序不变。
    private func currentDates() -> [Date] {
        let now = Date()
        return items.indices.map { now.addingTimeInterval(Double($0)) }
    }
}
