import SwiftUI
import AppKit
import UniformTypeIdentifiers

/* 外观编辑器只修改草稿；保存、启用、复制均通过 SettingsStore 提交。
 草稿暂存于设置对象，因此离开分区再返回也不会丢失未保存内容。 */
struct AppearanceSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @State private var draft: AppearanceProfile
    @State private var slot: Int
    @State private var tab = 1
    @State private var scene: ArtworkScene = .idle
    @State private var variant: ListeningAnimationVariant = .sway
    @State private var background = 0
    @State private var playing = true
    @State private var previewsPlaylist = false
    @State private var previewID = UUID()
    private var importing: Bool { settings.isImportingArtwork }
    @State private var message = ""
    @State private var error = ""
    @State private var pendingSlot: Int?
    @State private var copyTarget: Int?
    @State private var confirmSwitch = false
    @State private var confirmCopy = false
    @State private var confirmReset = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var undoLibrary: AppearanceLibrary?
    @State private var isTargeted = false

    init(settings: SettingsStore, selectedScene: ArtworkScene = .idle) {
        self.settings = settings
        _scene = State(initialValue: selectedScene)
        let index = settings.appearanceEditingIndex ?? settings.appearanceLibrary.activeIndex
        _slot = State(initialValue: index)
        _draft = State(initialValue: settings.appearanceDraft ?? settings.appearanceLibrary.profiles[index])
    }
    private var key: String { scene.key(variant: variant) }
    private var asset: CustomArtwork? { draft.artworks[key] }
    private var dirty: Bool { draft != settings.appearanceLibrary.profiles[slot] }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("外观设置", selection: $tab) {
                Text("基础外观").tag(0)
                Text("场景素材").tag(1)
            }.pickerStyle(.segmented).frame(width: 230)
            profileBar
            if !settings.appearanceError.isEmpty {
                Label(settings.appearanceError, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
            }
            if tab == 0 { baseEditor } else { sceneEditor }
            if importing { ProgressView("正在检查并导入素材…").controlSize(.small) }
            if !error.isEmpty { Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled) }
            HStack {
                Text(message.isEmpty ? (dirty ? "有未应用的更改，桌面保持当前方案" : "内置原始素材始终保留，可随时恢复") : message)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if undoLibrary != nil {
                    Button("撤销上次提交") {
                        guard let previous = undoLibrary, settings.saveAppearance(previous) else { return }
                        undoLibrary = nil
                        loadSlot(slot)
                        message = "已撤销上次提交"
                    }
                }
            }
            Divider()
            HStack {
                Button("恢复整套默认…") { confirmReset = true }
                Spacer()
                if dirty { Button("放弃更改") { loadSlot(slot) } }
                Button("应用更改") { commit(activate: false) }.disabled(!dirty)
                if settings.appearanceLibrary.activeIndex != slot {
                    Button("使用此方案") { commit(activate: true) }.buttonStyle(.borderedProminent)
                }
            }
        }
        .disabled(importing || !settings.appearanceError.isEmpty)
        .onChange(of: settings.appearanceLibrary) { library in
            // 右键快捷修改没有草稿冲突时，同步当前正在展示的方案。
            if let savedDraft = settings.appearanceDraft, savedDraft == library.profiles[slot] {
                draft = savedDraft
            }
        }
        .onChange(of: draft) { value in
            settings.appearanceDraft = value
            settings.appearanceEditingIndex = slot
        }
        .alert("保存当前方案的更改？", isPresented: $confirmSwitch) {
            Button("保存并切换") { if commit(activate: false), let index = pendingSlot { loadSlot(index) } }
            Button("放弃并切换", role: .destructive) { if let index = pendingSlot { loadSlot(index) } }
            Button("取消", role: .cancel) { pendingSlot = nil }
        } message: { Text("切换方案前，请处理当前未应用的修改。") }
        .alert("覆盖目标方案？", isPresented: $confirmCopy) {
            Button("覆盖", role: .destructive) { copyProfile() }
            Button("取消", role: .cancel) { copyTarget = nil }
        } message: {
            if let target = copyTarget {
                Text("将覆盖“\(settings.appearanceLibrary.profiles[target].name)”的全部配置。\(target == settings.appearanceLibrary.activeIndex ? "该方案正在使用，桌面外观也会更新。" : "")")
            }
        }
        .alert("恢复整套内置外观？", isPresented: $confirmReset) {
            Button("恢复默认", role: .destructive) {
                draft = AppearanceProfile(name: draft.name)
                message = "默认外观已载入预览，点击应用更改后生效"
            }
            Button("取消", role: .cancel) {}
        } message: { Text("清除此方案所有场景的自定义素材并恢复基础外观；其他两套方案不受影响。") }
        .alert("重命名方案", isPresented: $renaming) {
            TextField("方案名称", text: $newName)
            Button("确定") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { draft.name = String(name.prefix(24)) }
            }
            Button("取消", role: .cancel) {}
        } message: { Text("最多 24 个字，名称随方案一起保存。") }
    }

    private var profileBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("方案", selection: Binding(get: { slot }, set: { index in
                    if dirty { pendingSlot = index; confirmSwitch = true } else { loadSlot(index) }
                })) {
                    ForEach(0..<3, id: \.self) { index in
                        Text("\(index + 1). \(settings.appearanceLibrary.profiles[index].name)\(settings.appearanceLibrary.profiles[index].isConfigured ? "" : " · 空位")").tag(index)
                    }
                }.frame(maxWidth: 310)
                Button("重命名") { newName = draft.name; renaming = true }
                Menu("复制到…") {
                    ForEach((0..<3).filter { $0 != slot }, id: \.self) { index in
                        Button(settings.appearanceLibrary.profiles[index].name) {
                            copyTarget = index
                            if settings.appearanceLibrary.profiles[index].isConfigured { confirmCopy = true }
                            else { copyProfile() }
                        }
                    }
                }.fixedSize()
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Image(systemName: slot == settings.appearanceLibrary.activeIndex ? "checkmark.circle.fill" : "square.stack")
                    .foregroundStyle(SettingsPalette.accent)
                Text(slot == settings.appearanceLibrary.activeIndex ? "当前使用" : "正在编辑，尚未启用")
                Text("· 三套独立保存 · 每个场景单独配置").foregroundStyle(.secondary)
            }.font(.caption)
            Divider()
            HStack(spacing: 12) {
                Text(draft.artworks.isEmpty ? "当前方案使用默认素材" : "恢复本方案全部场景的图片与动画")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("恢复默认素材") {
                    // 只清除草稿的素材覆盖，基础外观和其他两个方案保持原值。
                    draft.artworks.removeAll()
                    previewID = UUID()
                    error = ""
                    message = "已恢复默认素材预览，点击“应用更改”后生效"
                }
                .disabled(draft.artworks.isEmpty)
                .help("恢复当前方案的全部内置素材，保留大小、透明度等基础设置")
            }
        }
        .padding(16)
        .background(SettingsPalette.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var baseEditor: some View {
        HStack(alignment: .top, spacing: 20) {
            GroupBox("基础外观") {
                VStack(alignment: .leading, spacing: 18) {
                    valueSlider("宠物大小", value: $draft.scale, range: 0.55...1.45, percentage: true)
                    valueSlider("桌宠透明度", value: $draft.opacity, range: 0.35...1, percentage: true)
                    Divider()
                    SettingsToggleRow(title: "播放状态音效", isOn: $draft.sound)
                    SettingsToggleRow(title: "节气与节日限定表现", isOn: $draft.seasonal)
                    SettingsToggleRow(title: "安静模式", detail: "关闭声音，降低动画幅度", isOn: $draft.quiet)
                }
            }
            VStack(spacing: 12) {
                let idle = draft.artworks[ArtworkScene.idle.key()]
                Group {
                    if let idle {
                        CustomArtworkView(asset: idle, quiet: draft.quiet, showsErrors: true) { PetArtwork() }
                    } else { PetArtwork() }
                }
                .scaledToFit().frame(width: 170, height: 245)
                .scaleEffect(0.8 * draft.scale).opacity(draft.opacity)
                Text("素材预览").font(.headline)
                Text("应用更改后更新桌面").font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 190).padding(.vertical, 24)
            .background(SettingsPalette.surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var sceneEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 22) {
                    sceneList.frame(width: 130)
                    detailEditor.frame(minWidth: 365)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Picker("场景", selection: $scene) {
                        ForEach(ArtworkScene.editableScenes) { Text($0.title).tag($0) }
                    }
                    detailEditor
                }
            }
        }
        .onChange(of: scene) { _ in previewID = UUID(); playing = true; error = "" }
        .onChange(of: variant) { _ in previewID = UUID(); playing = true; previewsPlaylist = false; error = "" }
    }

    private var sceneList: some View {
        VStack(spacing: 6) {
            ForEach(ArtworkScene.editableScenes) { item in
                Button { scene = item } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item == .listening ? "headphones" : (item == .sword ? "film" : "photo"))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.system(size: 13, weight: .medium))
                            let prefix = item == .listening ? "listening" : item.key()
                            Text(draft.artworks.keys.contains(where: { $0 == prefix || $0.hasPrefix(prefix + "/") }) ? "已自定义" : "内置素材")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 12)
                    .background(scene == item ? SettingsPalette.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(scene == item ? SettingsPalette.accent : .primary)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(scene == item ? .isSelected : [])
            }
        }
    }

    private var detailEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(scene.title).font(.system(size: 20, weight: .semibold))
                Spacer()
                Text(asset == nil ? "内置" : "自定义").font(.caption).foregroundStyle(.secondary)
            }
            Text(scene.detail).font(.caption).foregroundStyle(.secondary)
            if scene == .listening {
                Toggle("轮播预览全部五款", isOn: $previewsPlaylist).font(.caption)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ListeningAnimationVariant.allCases) { item in
                            Button { variant = item } label: {
                                VStack(spacing: 5) {
                                    ListeningPetFrame(time: 0, still: true, variant: item)
                                        .scaleEffect(0.18).frame(width: 57, height: 50)
                                    Text(item.title).font(.system(size: 10))
                                }.padding(5)
                                    .background(variant == item ? SettingsPalette.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain).accessibilityAddTraits(variant == item ? .isSelected : [])
                        }
                    }
                }
            }
            preview
            HStack {
                Button { playing.toggle() } label: { Label(playing ? "暂停" : "播放", systemImage: playing ? "pause.fill" : "play.fill") }
                Button("重播") { previewID = UUID(); playing = true }
                Spacer()
                Picker("预览背景", selection: $background) {
                    Text("浅色").tag(0); Text("深色").tag(1); Text("透明").tag(2)
                }.labelsHidden().pickerStyle(.segmented).frame(width: 170)
            }.controlSize(.small)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset?.name ?? "使用内置素材").lineLimit(1).truncationMode(.middle).font(.system(size: 13, weight: .medium))
                    Text(asset.map { $0.video != nil ? "视频 · \(String(format: "%.1f", $0.duration)) 秒 · 静音" : ($0.isAnimated ? "动画 · \($0.durations.count) 帧 · \(String(format: "%.1f", $0.duration)) 秒" : "静态图片") } ?? "原始素材不会被覆盖")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu("替换素材…") {
                    Button("选择图片、动画或视频…") { chooseFile(sequence: false) }
                    Button("选择 PNG 序列文件夹…") { chooseFile(sequence: true) }
                }.fixedSize()
            }
            Text("支持 PNG、JPEG、GIF、MOV、MP4 和 PNG 序列文件夹。视频静音播放，最长 120 秒、最大 64 MB。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let asset {
                if scene == .listening && asset.duration > ListeningAnimationVariant.segmentDuration {
                    Text("此动画超过 9.6 秒，轮播时到时会切换下一款。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !asset.isAnimated {
                    Toggle("保留场景动作", isOn: assetBinding(\.preservesMotion, fallback: true))
                        .font(.callout)
                }
                DisclosureGroup("画面调整") {
                    VStack(spacing: 12) {
                        valueSlider("缩放", value: assetBinding(\.scale, fallback: 1), range: 0.25...1.5, percentage: true)
                        valueSlider("水平位置", value: assetBinding(\.offsetX, fallback: 0), range: -80...80)
                        valueSlider("垂直位置", value: assetBinding(\.offsetY, fallback: 0), range: -80...80)
                        Button("重置位置与缩放") {
                            draft.artworks[key]?.scale = 1; draft.artworks[key]?.offsetX = 0; draft.artworks[key]?.offsetY = 0
                        }
                    }.padding(.top, 12)
                }
                Button(scene == .listening ? "恢复此款听歌动作" : "恢复此场景") { draft.artworks.removeValue(forKey: key) }
                    .controlSize(.small)
            }
        }
    }

    private var preview: some View {
        ZStack {
            if background == 2 {
                Canvas { context, size in
                    // 棋盘格只标识透明区域，不会写入导出的角色素材。
                    for row in 0..<Int(ceil(size.height / 16)) {
                        for column in 0..<Int(ceil(size.width / 16)) {
                            context.fill(Path(CGRect(x: column * 16, y: row * 16, width: 16, height: 16)),
                                         with: .color((row + column).isMultiple(of: 2) ? Color(white: 0.9) : .white))
                        }
                    }
                }
            } else { (background == 0 ? Color(white: 0.96) : Color(white: 0.12)) }
            Group {
                if scene == .listening && previewsPlaylist {
                    ListeningPetArtwork(quiet: draft.quiet, playing: playing, customArtworks: draft.artworks)
                } else {
                    SceneArtworkPreview(scene: scene, variant: variant, asset: asset,
                                        playing: playing, quiet: draft.quiet)
                }
            }
            .frame(width: 245, height: 275).opacity(draft.opacity).id(previewID)
        }
        .frame(height: 292).frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isTargeted ? SettingsPalette.accent : SettingsPalette.line, lineWidth: isTargeted ? 2 : 1))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            guard !importing, let provider = providers.first else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in startImport(url) }
            }
            return true
        }
        .accessibilityLabel("\(scene.title)素材预览，可拖入文件替换")
    }

    private func valueSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, percentage: Bool = false) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue * (percentage ? 100 : 1)).rounded()))\(percentage ? "%" : "")")
                    .monospacedDigit().foregroundStyle(SettingsPalette.accent)
            }.font(.callout)
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }
    private func assetBinding<Value>(_ path: WritableKeyPath<CustomArtwork, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { draft.artworks[key]?[keyPath: path] ?? fallback }, set: { draft.artworks[key]?[keyPath: path] = $0 })
    }

    /// 文件选择结束后交给后台导入；记录导入时的场景，避免异步结果写错位置。
    private func chooseFile(sequence: Bool) {
        let panel = NSOpenPanel()
        panel.title = sequence ? "选择 PNG 序列文件夹" : "选择图片、动画或视频"
        panel.canChooseDirectories = sequence; panel.canChooseFiles = !sequence
        panel.allowsMultipleSelection = false
        if !sequence { panel.allowedContentTypes = [.png, .jpeg, .gif, .quickTimeMovie, .mpeg4Movie] }
        panel.begin { response in
            if response == .OK, let url = panel.url { startImport(url) }
        }
    }
    private func startImport(_ url: URL) {
        guard !importing else { return }
        settings.isImportingArtwork = true; error = ""; message = ""
        let importKey = key
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { try await ArtworkImporter.importArtwork(from: url) }.result
            settings.isImportingArtwork = false
            switch result {
            case .success(let imported):
                draft.artworks[importKey] = imported
                settings.appearanceDraft = draft
                settings.appearanceEditingIndex = slot
                previewID = UUID(); playing = true
                message = "已载入预览，点击应用更改后保存"
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }
    private func loadSlot(_ index: Int) {
        slot = index; draft = settings.appearanceLibrary.profiles[index]
        settings.appearanceEditingIndex = index; settings.appearanceDraft = draft
        error = ""; message = ""; previewID = UUID()
    }
    @discardableResult
    private func commit(activate: Bool) -> Bool {
        var library = settings.appearanceLibrary
        var saved = draft; saved.isConfigured = true
        library.profiles[slot] = saved
        if activate { library.activeIndex = slot }
        let previous = settings.appearanceLibrary
        guard settings.saveAppearance(library) else { return false }
        undoLibrary = previous
        draft = saved
        message = activate ? "已使用“\(saved.name)”" : "已保存“\(saved.name)”"
        return true
    }
    private func copyProfile() {
        guard let target = copyTarget else { return }
        var library = settings.appearanceLibrary
        var copy = draft; copy.name = "\(String(draft.name.prefix(18))) · 副本"; copy.isConfigured = true
        library.profiles[target] = copy
        let previous = settings.appearanceLibrary
        guard settings.saveAppearance(library) else { return }
        undoLibrary = previous; copyTarget = nil
        message = "已复制到第 \(target + 1) 套方案"
    }
}

/// 使用现有原生立绘与动作预览；此组件不触发收纳或音乐服务。
struct SceneArtworkPreview: View {
    let scene: ArtworkScene
    let variant: ListeningAnimationVariant
    let asset: CustomArtwork?
    var playing = true
    var quiet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var elapsed = 0.0
    private var paused: Bool { !playing || reduceMotion }
    var body: some View {
        TimelineView(.animation(minimumInterval: quiet ? 1.0 / 12 : 1.0 / 24, paused: paused)) { context in
            let time = reduceMotion ? 0 : elapsed + (playing ? context.date.timeIntervalSince(start) : 0)
            let moves = !reduceMotion && asset?.isAnimated != true && asset?.preservesMotion != false
            let phase = max(0, time) * 2
            Group {
                if scene == .listening {
                    ListeningPetFrame(time: time, still: reduceMotion, variant: variant, intensity: quiet ? 0.35 : 1, customArtwork: asset, showsCustomErrors: true, customPlaying: playing)
                } else if let asset {
                    CustomArtworkView(asset: asset, loops: scene.loops, playing: playing, quiet: quiet, showsErrors: true) {
                        StatePetArtwork(state: PetVisualState(rawValue: scene.rawValue) ?? .idle)
                    }
                } else if scene == .sword || scene == .receiving {
                    SwordAnimationArtwork(frameIndex: min(72, Int(max(0, time) * 12) * 2))
                } else {
                    StatePetArtwork(state: PetVisualState(rawValue: scene.rawValue) ?? .idle)
                }
            }
            .scaledToFit()
            .scaleEffect(moves && scene == .idle ? 1 + sin(phase) * (quiet ? 0.002 : 0.008) : 1)
            .rotationEffect(.degrees(moves && scene == .failure ? sin(phase * 5) * (quiet ? 1 : 3) : 0))
            .offset(y: moves && scene == .complete ? -abs(sin(phase)) * (quiet ? 2 : 6) : 0)
        }
        .onChange(of: paused) { value in
            if value { elapsed += Date().timeIntervalSince(start) } else { start = Date() }
        }
    }
}
