import SwiftUI

/// 让用户确认/调整截图的上下顺序。
/// 顺序：从上到下，即拼接后长图从顶部到底部。
/// 作为纯内容视图，由外层 NavigationStack 管理导航。
struct OrderConfirmView: View {
    @State private var items: [Item]
    /// 确认后按当前顺序回传（从早到晚、从上到下）。
    let onConfirm: ([UIImage], [Date]) -> Void
    let onCancel: () -> Void

    init(images: [UIImage], dates: [Date], onConfirm: @escaping ([UIImage], [Date]) -> Void, onCancel: @escaping () -> Void) {
        _items = State(initialValue: zip(images, dates).map { Item(image: $0.0, date: $0.1) })
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    private struct Item: Identifiable {
        let id = UUID()
        let image: UIImage
        let date: Date
    }

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
                            .font(.caption.monospacedDigit.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        Image(uiImage: item.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 66)
                            .clipShape(RoundedRectangle(cornerRadius: 5))

                        Text(item.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
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
                Button("取消") { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("下一步") {
                    // 重新赋予严格递增的日期，保证后续按创建时间排序时顺序不变。
                    let now = Date()
                    let orderedDates = items.indices.map { now.addingTimeInterval(Double($0)) }
                    onConfirm(items.map { $0.image }, orderedDates)
                }
            }
        }
    }
}
