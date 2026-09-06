import SwiftUI
import AppKit

/// 设置窗口独立采用青绿强调色，原生语义色随系统深浅外观切换。
enum SettingsPalette {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.43, green: 0.79, blue: 0.65, alpha: 1)
            : NSColor(srgbRed: 0.13, green: 0.40, blue: 0.31, alpha: 1)
    })
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let line = Color.primary.opacity(0.08)
}

/// 组标题置于表面之外，使标题层级与可操作区域一眼可分。
struct SettingsGroupStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            configuration.content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(SettingsPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(SettingsPalette.line, lineWidth: 1))
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    var detail: String = ""
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 3)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        GroupBox("总收纳位置") {
            HStack(spacing: 14) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 25))
                    .foregroundStyle(SettingsPalette.accent)
                    .frame(width: 44, height: 44)
                    .background(SettingsPalette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    Text(URL(fileURLWithPath: settings.baseDirectory).lastPathComponent)
                        .font(.system(size: 14, weight: .semibold))
                    Text((settings.baseDirectory as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).help(settings.baseDirectory)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("选择…") { settings.chooseBaseDirectory() }
                Button("打开") { settings.revealBaseDirectory() }
            }
        }

        // 外观配置已移到独立编辑器，常规页只保留基础行为。
        GroupBox("桌宠行为") {
            VStack(spacing: 14) {
                SettingsToggleRow(title: "显示设置图标", detail: "桌宠右上角的快捷入口", isOn: $settings.showsSettingsButton)
                SettingsToggleRow(title: "自动吸附屏幕边缘", isOn: $settings.snapToScreenEdges)
                SettingsToggleRow(title: "显示今日数量与连续天数", isOn: $settings.showsDailyBadge)
            }
        }

        GroupBox("分类子目录") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(FileCategory.allCases) { category in
                    HStack(spacing: 10) {
                        Image(systemName: category.symbol)
                            .frame(width: 20).foregroundStyle(SettingsPalette.accent)
                        Text(category.rawValue).frame(width: 44, alignment: .leading)
                        TextField(category.rawValue, text: Binding(
                            get: { settings.subfolder(for: category) },
                            set: { settings.updateSubfolder($0, for: category) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("\(category.rawValue)子目录")
                    }
                }
            }
        }
    }

}
