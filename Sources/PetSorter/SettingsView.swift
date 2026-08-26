import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var history: OperationHistoryStore

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                PetArtwork()
                    .scaledToFit()
                    .frame(width: 76, height: 82)
                VStack(alignment: .leading, spacing: 5) {
                    Text("二爷收着")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("把文件拖到桌宠身上，关将军会按类型收好。")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("总收纳位置") {
                HStack {
                    Image(systemName: "externaldrive.fill")
                        .foregroundStyle(.secondary)
                    Text(settings.baseDirectory)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("选择…") { settings.chooseBaseDirectory() }
                    Button("打开") { settings.revealBaseDirectory() }
                }
                .padding(8)
            }

            GroupBox("宠物大小") {
                HStack(spacing: 12) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Slider(value: $settings.petScale, in: 0.55...1.45, step: 0.05)
                    Image(systemName: "person.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("\(Int(settings.petScale * 100))%")
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                .padding(8)
            }

            GroupBox("分类子目录") {
                VStack(spacing: 8) {
                    ForEach(FileCategory.allCases) { category in
                        HStack(spacing: 10) {
                            Image(systemName: category.symbol)
                                .frame(width: 20)
                                .foregroundStyle(.secondary)
                            Text(category.rawValue)
                                .frame(width: 56, alignment: .leading)
                            TextField(
                                category.rawValue,
                                text: Binding(
                                    get: { settings.subfolder(for: category) },
                                    set: { settings.updateSubfolder($0, for: category) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding(8)
            }

            GroupBox("最近收纳") {
                HStack(spacing: 12) {
                    if let operation = history.lastOperation {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(operation.source) · \(operation.items.count) 件")
                                .fontWeight(.medium)
                            Text(Self.historyDateFormatter.string(from: operation.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("撤回上次收纳") { _ = history.undoLast() }
                    } else {
                        Label("还没有收纳记录", systemImage: "tray")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .padding(8)
            }

            HStack {
                Label("同名文件会自动加 -2、-3，不会覆盖原文件", systemImage: "checkmark.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("退出桌宠") { NSApp.terminate(nil) }
            }
        }
        .padding(24)
        .frame(minWidth: 570, minHeight: 700)
    }
}
