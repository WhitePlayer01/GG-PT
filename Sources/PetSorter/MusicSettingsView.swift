import SwiftUI
import UniformTypeIdentifiers

struct MusicSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var music: MusicListeningService
    @ObservedObject var history: MusicHistoryStore
    @State private var confirmingClear = false

    var body: some View {
        GroupBox("让云长卫记住你听过的歌") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("自动记录正在播放的歌曲", isOn: $settings.musicTrackingEnabled)
                Text("支持 Apple Music、Spotify，以及装有新版网页扩展的网易云、QQ 音乐、Spotify、Apple Music 和 YouTube Music 网页。网页需提供歌名、歌手和播放状态。另可检测网易云音乐 3.x 桌面版的播放状态，暂不记录其歌名；QQ 音乐桌面版暂未接入。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("只读取歌曲信息或播放状态，不录音、不录屏、不上传。收听时长按约 5 秒间隔估算；暂停、休眠不计入。Apple Music、Spotify 需要自动化授权。")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Label(music.status, systemImage: "waveform")
                if let track = music.currentTrack {
                    Text(track.title).font(.title3.bold())
                    Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("立即检测") { music.poll() }.disabled(!settings.musicTrackingEnabled)
                    Text("网页端还需在扩展中开启“听歌记录”并刷新音乐页面")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
        GroupBox("网易云桌面版") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("检测网易云播放状态", isOn: $settings.neteaseTrackingEnabled)
                Text("需要辅助功能权限。读取网易云菜单的播放／暂停状态，用于切换听歌形态，无需录屏或录音。暂不读取桌面版歌名、歌手，也不生成歌曲记录；如需记录歌曲，可使用已连接扩展的网易云网页。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("连接网易云…") { music.connectNetease() }
                    Label(music.neteaseStatus, systemImage: "music.note")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(8)
        }
        GroupBox("听歌形态") {
            HStack(spacing: 16) {
                ListeningPetArtwork(quiet: settings.quietMode)
                    .scaleEffect(0.65)
                    .frame(width: 160, height: 180)
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("播放音乐时切换听歌形态", isOn: $settings.musicListeningAppearanceEnabled)
                    Text("五款动作随机轮播，每款完整播放 9.6 秒；一轮五款不重复。音乐继续时一直保持听歌形态，收纳时也不中断。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("闭眼轻晃 · 扶耳点头 · 握拳打拍 · 张臂摇摆 · 盘坐沉浸。安静模式保留轻幅动画和随机轮播；系统“减少动态效果”会停止循环动作。\n网易云状态暂时不可读时沿用最近状态，重新读到暂停或播放器退出后恢复待机。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
        GroupBox("听歌足迹") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(history.records.count) 次收听 · \(Set(history.records.map { $0.track.key }).count) 首歌曲")
                    Spacer()
                    Button("导出 JSON…", action: export)
                        .disabled(history.records.isEmpty)
                    Button("清空记录…") { confirmingClear = true }
                        .disabled(history.records.isEmpty && history.errorMessage == nil)
                }
                Text("记录歌名、歌手、专辑、来源、收听时间和时长，为后续推荐保留依据。重复播放会单独记录，暂停后恢复沿用本次收听。历史长期保留，下面展示最近 100 次。")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = history.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                if history.records.isEmpty {
                    Text("还没有听歌记录。开启后，在支持的播放器中播放一首歌吧。")
                        .foregroundStyle(.secondary).padding(.vertical, 16)
                }
                ForEach(Array(history.records.prefix(100))) { record in
                    Divider()
                    HStack(alignment: .top) {
                        Image(systemName: "music.note").foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.track.title).fontWeight(.medium)
                            Text("\(record.track.artist.isEmpty ? "未知歌手" : record.track.artist) · \(record.track.source)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(record.startedAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("约 \(Int(record.listenedSeconds)) 秒").font(.caption).monospacedDigit()
                    }
                }
            }.padding(8)
        }
        .alert("清空所有听歌记录？", isPresented: $confirmingClear) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { history.clear() }
        } message: {
            Text("此操作不可撤回。可先导出备份；自动记录开关不受影响。")
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "云长卫-听歌记录.json"
        if panel.runModal() == .OK, let url = panel.url { history.export(to: url) }
    }
}
