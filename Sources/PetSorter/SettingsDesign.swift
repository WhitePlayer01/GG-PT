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

        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 22) {
                GroupBox("宠物大小") {
                    VStack(alignment: .leading, spacing: 12) {
                        sliderHeading("缩放比例", value: settings.petScale)
                        Slider(value: $settings.petScale, in: 0.55...1.45, step: 0.05)
                            .accessibilityLabel("宠物大小")
                        SettingsToggleRow(title: "显示设置图标", detail: "桌宠右上角的快捷入口", isOn: $settings.showsSettingsButton)
                    }
                }
                GroupBox("桌宠外观") {
                    VStack(alignment: .leading, spacing: 12) {
                        sliderHeading("桌宠透明度", value: settings.petOpacity)
                        Slider(value: $settings.petOpacity, in: 0.35...1, step: 0.05) { editing in
                            if !editing { settings.persistPetOpacity() }
                        }
                        .accessibilityLabel("桌宠透明度")
                        HStack {
                            Text("调节后立即生效").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("恢复默认") {
                                settings.petOpacity = 1
                                settings.persistPetOpacity()
                            }.controlSize(.small)
                        }
                        Divider()
                        SettingsToggleRow(title: "自动吸附屏幕边缘", isOn: $settings.snapToScreenEdges)
                        SettingsToggleRow(title: "显示今日数量与连续天数", isOn: $settings.showsDailyBadge)
                    }
                }
            }
            GroupBox("角色预览") {
                VStack(spacing: 8) {
                    PetArtwork(skin: settings.petSkin)
                        .scaledToFit()
                        .frame(width: 175, height: 234)
                        .scaleEffect(0.78 + (settings.petScale - 0.55) * 0.22)
                        .opacity(settings.petOpacity)
                        .accessibilityLabel("当前角色外观预览")
                    Text(settings.petSkin.label).font(.system(size: 15, weight: .semibold))
                    Text(settings.petSkin.detail).font(.caption).foregroundStyle(.secondary)
                    Text("预览随设置实时变化")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .padding(.top, 12)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .frame(width: 225)
        }

        GroupBox("角色、兵器与主题") {
            VStack(spacing: 16) {
                picker("角色皮肤", selection: $settings.petSkin) {
                    ForEach(PetSkin.allCases) { Text("\($0.label) · \($0.detail)").tag($0) }
                }
                picker("兵器光效", selection: $settings.petWeapon) {
                    ForEach(PetWeapon.allCases) { Text($0.label).tag($0) }
                }
                picker("桌宠主题", selection: $settings.petTheme) {
                    ForEach(PetTheme.allCases) { Text($0.label).tag($0) }
                }
                Divider()
                SettingsToggleRow(title: "播放状态音效", isOn: $settings.soundEffectsEnabled)
                SettingsToggleRow(title: "节气与节日限定表现", isOn: $settings.seasonalEffectsEnabled)
                SettingsToggleRow(title: "安静模式", detail: "关闭声音，保留轻幅动画与听歌轮播", isOn: $settings.quietMode)
                if let moment = SeasonalMoment.current(), settings.seasonalEffectsEnabled {
                    Label("当前限定：\(moment.name) · \(moment.greeting)", systemImage: moment.symbol)
                        .font(.caption).foregroundStyle(SettingsPalette.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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

    private func sliderHeading(_ title: String, value: Double) -> some View {
        HStack {
            Text(title).fontWeight(.medium)
            Spacer()
            Text("\(Int((value * 100).rounded()))%")
                .monospacedDigit().fontWeight(.semibold)
                .foregroundStyle(SettingsPalette.accent)
        }
    }

    private func picker<Value: Hashable, Content: View>(_ title: String, selection: Binding<Value>,
                                                       @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).frame(width: 100, alignment: .leading)
            Spacer(minLength: 20)
            Picker(title, selection: selection, content: content).labelsHidden().frame(width: 290)
        }
    }
}
