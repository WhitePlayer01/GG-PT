import SwiftUI

/* 批量预览复用巡查服务的数据；勾选只控制本次，不修改自动化开关。
 执行期间禁止关闭，避免在后台移动尚未结束时恢复定时巡查。 */
struct PatrolPreviewSheet: View {
    @ObservedObject var patrol: FolderPatrolService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("确认这次整理").font(.title2.bold())
            Text("显示预计名称与目标目录；重复检测和同名编号在执行时完成。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("全选") { selectedIDs = Set(patrol.previewItems.map(\.id)) }
                Button("全不选") { selectedIDs = [] }
                Spacer()
                Text("已选 \(selectedIDs.count) / \(patrol.previewItems.count) 件")
            }.disabled(patrol.isRunning)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(patrol.previewItems) { item in
                        Toggle(isOn: Binding(get: { selectedIDs.contains(item.id) }, set: { checked in
                            // 保留路径标识，刷新时由新的候选清单重置选择。
                            if checked { selectedIDs.insert(item.id) } else { selectedIDs.remove(item.id) }
                        })) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.url.lastPathComponent).fontWeight(.medium)
                                Text("\(item.preview.matchedRuleName ?? item.preview.categoryName) → \(item.preview.preferredName)")
                                Text(item.preview.destinationPath).textSelection(.enabled)
                            }.font(.caption).lineLimit(2)
                        }.disabled(patrol.isRunning)
                        Divider()
                    }
                    if patrol.previewItems.isEmpty && !patrol.isRunning {
                        Text("没有待确认的文件").foregroundStyle(.secondary).padding(.vertical, 30)
                    }
                }
            }
            Text(patrol.previewMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Button("刷新预览") { patrol.preparePreview() }.disabled(patrol.isRunning)
                if patrol.isRunning { ProgressView().controlSize(.small) }
                Spacer()
                Button("关闭") { dismiss() }.disabled(patrol.isRunning)
                Button("整理所选文件") { patrol.confirmPreview(selectedIDs: selectedIDs) }
                    .buttonStyle(.borderedProminent)
                    .disabled(patrol.isRunning || selectedIDs.isEmpty || patrol.previewItems.isEmpty)
            }
        }
        .padding(24).frame(width: 720, height: 560)
        .interactiveDismissDisabled(patrol.isRunning)
        .onAppear { selectedIDs = Set(patrol.previewItems.map(\.id)) }
        .onChange(of: patrol.previewItems.map(\.id)) { selectedIDs = Set($0) }
    }
}
