import SwiftUI
import AppKit

/// 设置页的六个任务导向分区。
private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "常规"
    case automation = "自动化"
    case rules = "高级军令"
    case report = "战报"
    case history = "收纳记录"
    case updates = "版本更新"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .automation: return "clock.arrow.2.circlepath"
        case .rules: return "list.bullet.rectangle.portrait"
        case .report: return "chart.bar.xaxis"
        case .history: return "clock.arrow.circlepath"
        case .updates: return "arrow.down.app"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "收纳位置、桌宠外观与基础分类"
        case .automation: return "让桌面和下载目录按计划保持整洁"
        case .rules: return "用来源、类型、大小和时间定义精确军令"
        case .report: return "查看今日行动和最近一次可撤回记录"
        case .history: return "查看最近三天的收纳结果与文件去向"
        case .updates: return "管理版本检查与应用下载"
        }
    }
}

/// 集中配置收纳位置、桌宠外观、自动巡查、军令、历史和应用更新。
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var history: OperationHistoryStore
    @ObservedObject var updates: UpdateService
    @ObservedObject var patrol: FolderPatrolService
    @State private var rulePreviewText = ""
    @State private var selectedSection: SettingsSection = .general

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    /// 构建可滚动的完整设置页面，避免规则数量增加时撑破窗口。
    var body: some View {
        HStack(spacing: 0) {
        settingsSidebar
        Divider()
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            detailHeader

            if selectedSection == .general {
            GroupBox("总收纳位置") {
                // 路径使用中间省略，长目录仍能保留开头和末尾信息。
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
                VStack(spacing: 12) {
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
                    // 齿轮隐藏后仍可通过桌宠右键菜单进入设置。
                    Toggle("在桌宠右上角显示设置图标", isOn: $settings.showsSettingsButton)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
            }

            GroupBox("桌宠外观") {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Label("桌宠透明度", systemImage: "circle.lefthalf.filled")
                            .frame(width: 110, alignment: .leading)
                        Slider(value: $settings.petOpacity, in: 0.35...1.0, step: 0.05) { editing in
                            // 拖动期间实时更新桌宠，结束后再保存最终值。
                            if !editing {
                                settings.persistPetOpacity()
                            }
                        }
                        Text("\(Int(settings.petOpacity * 100))%")
                            .monospacedDigit()
                            .frame(width: 46, alignment: .trailing)
                        Button("恢复默认") {
                            settings.petOpacity = 1.0
                            settings.persistPetOpacity()
                        }
                    }
                    HStack {
                        Toggle("靠近屏幕边缘时自动吸附", isOn: $settings.snapToScreenEdges)
                        Spacer()
                        Toggle("显示今日数量与连续天数", isOn: $settings.showsDailyBadge)
                    }
                }
                .padding(8)
            }

            GroupBox("角色、兵器与主题") {
                HStack(alignment: .top, spacing: 18) {
                    PetArtwork(skin: settings.petSkin)
                        .scaledToFit()
                        .frame(width: 104, height: 124)
                        .padding(8)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    VStack(spacing: 11) {
                        appearancePicker("角色皮肤", selection: $settings.petSkin) {
                            ForEach(PetSkin.allCases) { skin in
                                Text("\(skin.label) · \(skin.detail)").tag(skin)
                            }
                        }
                        appearancePicker("兵器光效", selection: $settings.petWeapon) {
                            ForEach(PetWeapon.allCases) { weapon in
                                Text(weapon.label).tag(weapon)
                            }
                        }
                        appearancePicker("桌宠主题", selection: $settings.petTheme) {
                            ForEach(PetTheme.allCases) { theme in
                                Text(theme.label).tag(theme)
                            }
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Toggle("播放状态音效", isOn: $settings.soundEffectsEnabled)
                        Spacer()
                        Toggle("节气与节日限定表现", isOn: $settings.seasonalEffectsEnabled)
                    }
                    Toggle("安静模式（关闭声音，并降低常驻与结果动画幅度）", isOn: $settings.quietMode)
                    if let moment = SeasonalMoment.current(), settings.seasonalEffectsEnabled {
                        Label("当前限定：\(moment.name) · \(moment.greeting)", systemImage: moment.symbol)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
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
            }

            if selectedSection == .automation {
            GroupBox("自动巡查") {
                // 自动巡查默认关闭，只有用户主动启用目录后按钮才可用。
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("巡查桌面", isOn: $settings.monitorDesktop)
                    Toggle("巡查下载目录", isOn: $settings.monitorDownloads)
                    HStack {
                        Toggle("按文件日期建立 年/月 目录", isOn: $settings.organizeByYearMonth)
                        Spacer()
                        Toggle("拦截内容重复的文件", isOn: $settings.detectDuplicates)
                    }
                    HStack {
                        Text("智能命名")
                        Picker("智能命名", selection: $settings.smartNamingStyle) {
                            ForEach(SmartNamingStyle.allCases) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        Spacer()
                    }
                    HStack {
                        Text("巡查间隔")
                        Picker("巡查间隔", selection: $settings.monitorIntervalMinutes) {
                            Text("5 分钟").tag(5)
                            Text("15 分钟").tag(15)
                            Text("30 分钟").tag(30)
                            Text("1 小时").tag(60)
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        Spacer()
                        Text(patrolStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(patrol.isRunning ? "巡查中…" : "立即巡查") { patrol.patrolNow() }
                            .disabled(patrol.isRunning || (!settings.monitorDesktop && !settings.monitorDownloads))
                    }
                    Text("自动巡查默认关闭；只处理目录第一层的文件，并跳过文件夹、隐藏文件、未完成下载和刚修改的文件。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !patrol.cleanupSuggestion.isEmpty {
                        Label(cleanupSuggestionText, systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(8)
            }
            }

            if selectedSection == .rules {
            GroupBox("自定义军令（从上到下优先匹配）") {
                VStack(spacing: 12) {
                    if settings.sortingRules.isEmpty {
                        Text("还没有自定义规则，未命中的文件继续使用八大分类。")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach($settings.sortingRules) { $rule in
                        AdvancedRuleEditor(
                            rule: $rule,
                            isFirst: settings.sortingRules.first?.id == rule.id,
                            isLast: settings.sortingRules.last?.id == rule.id,
                            moveUp: { settings.moveRule(id: rule.id, offset: -1) },
                            moveDown: { settings.moveRule(id: rule.id, offset: 1) },
                            remove: { settings.removeRule(id: rule.id) }
                        )
                    }
                    HStack {
                        Button { settings.addRule() } label: {
                            Label("新增军令", systemImage: "plus")
                        }
                        Button(action: previewRuleMatch) {
                            Label("预览文件命中", systemImage: "scope")
                        }
                        Spacer()
                    }
                    if !rulePreviewText.isEmpty {
                        Text(rulePreviewText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
            }

            if selectedSection == .report {
            GroupBox("今日战报") {
                // 战报由历史记录实时计算，不维护第二份易失真的统计数据。
                let summary = history.todaySummary
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 18) {
                        reportValue("已收", value: summary.movedCount, suffix: "件")
                        reportValue("行动", value: summary.operationCount, suffix: "次")
                        reportValue("连续", value: history.currentStreak, suffix: "天")
                        reportValue("重复", value: summary.duplicateCount, suffix: "件")
                        reportTextValue("节省", value: readableByteCount(summary.savedBytes))
                        reportValue("失败", value: summary.failureCount, suffix: "件")
                    }
                    if !summary.categoryCounts.isEmpty {
                        Divider()
                        Text(summary.categoryCounts.map { "\($0.name) \($0.count)" }.joined(separator: "  ·  "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            }

            if selectedSection == .history {
            GroupBox {
                HStack(spacing: 12) {
                    Label("仅保留最近 \(OperationHistoryStore.retentionDays) 天", systemImage: "calendar.badge.clock")
                        .fontWeight(.medium)
                    Spacer()
                    Text("共 \(history.operations.count) 次行动")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            if history.operations.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("近三天还没有收纳记录")
                        .fontWeight(.medium)
                    Text("拖放、自动巡查和网页投递都会记录在这里。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 70)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(history.operations) { operation in
                        HistoryOperationCard(
                            operation: operation,
                            baseDirectory: settings.baseDirectory
                        )
                    }
                }
            }
            }

            if selectedSection == .updates {
            GroupBox("版本与更新") {
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("云长卫 \(UpdateService.currentVersion)")
                                .fontWeight(.medium)
                            Text(updateStatusText)
                                .font(.caption)
                                .foregroundStyle(updateStatusColor)
                        }
                        Spacer()
                        if case .updateAvailable(let release) = updates.status {
                            Button("获取 \(release.version)") { updates.openDownload(for: release) }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("检查更新") { updates.check() }
                                .disabled(updates.status == .checking)
                        }
                    }
                    Toggle("启动时自动检查更新", isOn: $settings.automaticallyChecksForUpdates)
                }
                .padding(8)
            }
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
        }
        .id(selectedSection)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .frame(minWidth: 860, minHeight: 700)
        .groupBoxStyle(TasteGroupBoxStyle())
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: selectedSection) { section in
            if section == .history { history.pruneExpiredHistory() }
        }
    }

    /// 左侧任务导航使用低对比暖色表面，让当前分区成为唯一强调色。
    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                PetArtwork()
                    .scaledToFit()
                    .frame(width: 44, height: 50)
                VStack(alignment: .leading, spacing: 1) {
                    Text("云长卫")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("配置中军帐")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 22)

            VStack(spacing: 5) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            selectedSection = section
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.icon)
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 20)
                            Text(section.rawValue)
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            if selectedSection == section {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .foregroundStyle(selectedSection == section ? Color.primary : Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(selectedSection == section ? Color.primary.opacity(0.075) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)

            Spacer()

            VStack(alignment: .leading, spacing: 5) {
                Text("收纳位置")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text((settings.baseDirectory as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Button("在 Finder 中打开") { settings.revealBaseDirectory() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            .padding(16)
        }
        .frame(width: 190)
        .background(Color.primary.opacity(0.025))
    }

    /// 右侧宽标题根据当前任务切换，保持页面定位清晰。
    private var detailHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(selectedSection.rawValue)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                Text(selectedSection.subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: selectedSection.icon)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
        }
        .id(selectedSection)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .padding(.bottom, 3)
    }

    /// 格式化上次巡查时间；从未执行时显示明确空状态。
    private var patrolStatusText: String {
        guard let date = settings.lastPatrolDate else { return "尚未巡查" }
        return "上次：\(Self.historyDateFormatter.string(from: date))"
    }

    /// 统一角色外观选择行的标签宽度和菜单尺寸。
    private func appearancePicker<Value: Hashable, Content: View>(
        _ title: String,
        selection: Binding<Value>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Picker(title, selection: selection, content: content)
                .labelsHidden()
                .frame(maxWidth: .infinity)
        }
    }

    /// 构建带单位的整数战报指标。
    private func reportValue(_ title: String, value: Int, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)").font(.title2.bold()).monospacedDigit()
                Text(suffix).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 构建已经预格式化为文本的战报指标，例如文件容量。
    private func reportTextValue(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 将清理建议的非零项目合并成一条中文提示。
    private var cleanupSuggestionText: String {
        let suggestion = patrol.cleanupSuggestion
        var parts: [String] = []
        if suggestion.emptyFolderCount > 0 { parts.append("\(suggestion.emptyFolderCount) 个空文件夹") }
        if suggestion.oldInstallerCount > 0 { parts.append("\(suggestion.oldInstallerCount) 个 30 天前安装包") }
        if suggestion.oldArchiveCount > 0 { parts.append("\(suggestion.oldArchiveCount) 个 30 天前压缩包") }
        return "清理提醒：" + parts.joined(separator: "、")
    }

    /// 选择单个文件并展示军令命中、智能名称和目标路径，不执行移动。
    private func previewRuleMatch() {
        let panel = NSOpenPanel()
        panel.title = "选择一个文件预览收纳结果"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let preview = FileOrganizer.preview(url, settings: settings)
        let rule = preview.matchedRuleName.map { "命中军令“\($0)”" } ?? "未命中军令，使用“\(preview.categoryName)”分类"
        rulePreviewText = "\(rule)；将保存为 \(preview.preferredName) → \(preview.destinationPath)"
    }

    /// 使用系统文件容量格式将字节数转换为 KB、MB 或 GB。
    private func readableByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// 把更新服务状态转换为设置页的中文说明。
    private var updateStatusText: String {
        switch updates.status {
        case .idle: return "尚未检查更新"
        case .checking: return "正在检查…"
        case .upToDate: return "当前已是最新版本"
        case .failed(let message): return "检查失败：\(message)"
        case .updateAvailable(let release): return "发现新版本：\(release.displayName)"
        }
    }

    /// 根据更新状态选择普通、错误或强调色。
    private var updateStatusColor: Color {
        switch updates.status {
        case .failed: return .red
        case .updateAvailable: return .accentColor
        default: return .secondary
        }
    }
}

/// 统一设置页表面：轻背景、细描边和更宽松的标题间距。
private struct TasteGroupBoxStyle: GroupBoxStyle {
    /// 将原生 GroupBox 转换为低噪声设置表面，同时保留系统深浅色适配。
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
                .font(.system(size: 14, weight: .semibold))
            configuration.content
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.075), lineWidth: 1)
        )
    }
}

/// 在收纳记录页展示一次行动的状态、文件去向、重复与失败详情。
private struct HistoryOperationCard: View {
    let operation: SortOperation
    let baseDirectory: String

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: status.icon)
                    .foregroundStyle(status.color)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(operation.source)
                        .font(.system(size: 15, weight: .semibold))
                    Text(Self.dateFormatter.string(from: operation.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(status.color.opacity(0.1), in: Capsule())
            }

            if !operation.sourceURL.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(operation.sourceTitle.isEmpty ? "来源网页" : operation.sourceTitle)
                            .lineLimit(1)
                        Text(operation.sourceURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("打开来源") { openSource() }
                        .buttonStyle(.borderless)
                }
            }

            if !operation.items.isEmpty || !operation.duplicateFileNames.isEmpty || !operation.failureMessages.isEmpty || !operation.sourceURL.isEmpty {
                Divider()
            }

            ForEach(operation.items) { item in
                HStack(spacing: 10) {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.fileName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("去向：\(relativePath(item.destinationPath))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let originalPath = item.originalPath, !originalPath.isEmpty {
                            Text("来源：\((originalPath as NSString).abbreviatingWithTildeInPath)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer()
                    Text(item.categoryName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if FileManager.default.fileExists(atPath: item.destinationPath) {
                        Button("显示") { reveal(item.destinationPath) }
                            .buttonStyle(.borderless)
                    } else {
                        Text("文件已移动")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            ForEach(Array(operation.duplicateFileNames.enumerated()), id: \.offset) { _, name in
                detailRow(
                    icon: "doc.on.doc.fill",
                    title: name,
                    detail: "目标目录已有相同内容，未重复保存",
                    color: .orange
                )
            }

            ForEach(Array(operation.failureMessages.enumerated()), id: \.offset) { _, message in
                detailRow(
                    icon: "exclamationmark.triangle.fill",
                    title: "收纳失败",
                    detail: message,
                    color: .red
                )
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.075), lineWidth: 1)
        )
    }

    private var status: (label: String, icon: String, color: Color) {
        if operation.failureCount > 0, operation.items.isEmpty {
            return ("失败", "xmark.circle.fill", .red)
        }
        if operation.failureCount > 0 {
            return ("部分完成", "exclamationmark.circle.fill", .orange)
        }
        if operation.items.isEmpty, operation.duplicateCount > 0 {
            return ("已跳过重复", "doc.on.doc.fill", .orange)
        }
        return ("成功", "checkmark.circle.fill", .green)
    }

    private var summary: String {
        var parts: [String] = []
        if !operation.items.isEmpty { parts.append("收纳 \(operation.items.count) 件") }
        if operation.duplicateCount > 0 { parts.append("重复 \(operation.duplicateCount) 件") }
        if operation.failureCount > 0 { parts.append("失败 \(operation.failureCount) 件") }
        return parts.joined(separator: " · ")
    }

    private func relativePath(_ path: String) -> String {
        let base = URL(fileURLWithPath: baseDirectory, isDirectory: true).standardizedFileURL.path
        let destination = URL(fileURLWithPath: path).standardizedFileURL.path
        guard destination.hasPrefix(base + "/") else { return destination }
        return String(destination.dropFirst(base.count + 1))
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func openSource() {
        guard let url = URL(string: operation.sourceURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        NSWorkspace.shared.open(url)
    }

    private func detailRow(icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).lineLimit(1).truncationMode(.middle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
    }
}

/// 使用位置选择器和推荐预设编辑一条高级军令。
private struct AdvancedRuleEditor: View {
    @Binding var rule: SortingRule
    let isFirst: Bool
    let isLast: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    @State private var showsPreciseRange = false

    /// 构建分层军令卡片：先配置常用条件，需要时再展开精确范围。
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            Divider()

            HStack(spacing: 10) {
                labeledTextField(
                    title: "文件名",
                    icon: "text.magnifyingglass",
                    placeholder: "包含关键词，例如：发票",
                    text: $rule.fileNameContains
                )
                labeledTextField(
                    title: "文件类型",
                    icon: "doc.badge.gearshape",
                    placeholder: "pdf, jpg, docx",
                    text: $rule.extensions
                )
            }

            sourceLocationRow

            HStack(spacing: 10) {
                presetPanel(
                    title: "文件大小",
                    icon: "externaldrive",
                    value: sizePresetLabel,
                    isRecommended: rule.minimumSizeMB == 0 && rule.maximumSizeMB == 100,
                    menu: { sizePresetMenu }
                )
                presetPanel(
                    title: "创建时间",
                    icon: "calendar",
                    value: datePresetLabel,
                    isRecommended: rule.createdWithinDays == 30 && rule.olderThanDays == 0,
                    menu: { datePresetMenu }
                )
            }

            DisclosureGroup("精确设置大小与时间范围", isExpanded: $showsPreciseRange) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("大小")
                            .frame(width: 72, alignment: .leading)
                        TextField("最小", value: $rule.minimumSizeMB, formatter: Self.sizeFormatter)
                            .frame(width: 82)
                        Text("MB 至").foregroundStyle(.secondary)
                        TextField("最大", value: $rule.maximumSizeMB, formatter: Self.sizeFormatter)
                            .frame(width: 82)
                        Text("MB").foregroundStyle(.secondary)
                        Text("0 表示不限")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("创建时间")
                            .frame(width: 72, alignment: .leading)
                        TextField("最近天数", value: $rule.createdWithinDays, formatter: Self.integerFormatter)
                            .frame(width: 82)
                        Text("天内，且早于").foregroundStyle(.secondary)
                        TextField("早于天数", value: $rule.olderThanDays, formatter: Self.integerFormatter)
                            .frame(width: 82)
                        Text("天").foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            }
            .font(.subheadline)

            HStack(spacing: 10) {
                Label("收纳到", systemImage: "tray.full")
                    .foregroundStyle(.secondary)
                    .frame(width: 82, alignment: .leading)
                TextField("目标目录，例如：工作/发票", text: $rule.destinationFolder)
                Text("相对于总收纳位置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            footerHint
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    rule.isEnabled
                        ? Color.accentColor.opacity(0.085)
                        : Color(nsColor: .controlBackgroundColor).opacity(0.46)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(rule.isEnabled ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.08))
        )
        .animation(.easeInOut(duration: 0.18), value: rule.isEnabled)
    }

    /// 显示启用开关、军令名称、排序操作和删除入口。
    private var header: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $rule.isEnabled)
                .labelsHidden()
                .help(rule.isEnabled ? "停用这条军令" : "启用这条军令")
            TextField("军令名称", text: $rule.name)
                .font(.system(size: 15, weight: .semibold))
            Text(rule.isEnabled ? "执行中" : "未启用")
                .font(.caption.weight(.medium))
                .foregroundStyle(rule.isEnabled ? Color.accentColor : Color.secondary)
            Spacer()
            Button(action: moveUp) { Image(systemName: "arrow.up") }
                .disabled(isFirst)
                .help("提高优先级")
            Button(action: moveDown) { Image(systemName: "arrow.down") }
                .disabled(isLast)
                .help("降低优先级")
            Button(role: .destructive, action: remove) { Image(systemName: "trash") }
                .help("删除军令")
        }
        .buttonStyle(.borderless)
    }

    /// 显示当前来源目录，并提供常用目录、系统选择器和清空操作。
    private var sourceLocationRow: some View {
        HStack(spacing: 10) {
            Label("来源位置", systemImage: "folder")
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(sourceLocationLabel)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(rule.sourcePathContains.isEmpty ? Color.secondary : Color.primary)
            Menu("常用位置") {
                Button("桌面") { rule.sourcePathContains = homeDirectory("Desktop") }
                Button("下载") { rule.sourcePathContains = homeDirectory("Downloads") }
                Button("文稿") { rule.sourcePathContains = homeDirectory("Documents") }
                Divider()
                Button("不限来源") { rule.sourcePathContains = "" }
            }
            Button("选择…", action: chooseSourceDirectory)
            if !rule.sourcePathContains.isEmpty {
                Button { rule.sourcePathContains = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("清除来源限制")
            }
        }
    }

    /// 构建带标题和图标的文本输入区。
    private func labeledTextField(
        title: String,
        icon: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: icon)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    /// 构建文件大小或创建时间的预设选择面板。
    private func presetPanel<MenuContent: View>(
        title: String,
        icon: String,
        value: String,
        isRecommended: Bool,
        @ViewBuilder menu: () -> MenuContent
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    if isRecommended {
                        Text("推荐")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(value).font(.subheadline.weight(.medium)).monospacedDigit()
            }
            Spacer()
            Menu(content: menu) {
                Image(systemName: "chevron.up.chevron.down")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }

    /// 提供日常、小文件、大文件、不限和自定义大小范围。
    @ViewBuilder
    private var sizePresetMenu: some View {
        Button("日常文件 · 0–100 MB（推荐）") { applySize(minimum: 0, maximum: 100) }
        Button("小文件 · 0–10 MB") { applySize(minimum: 0, maximum: 10) }
        Button("大文件 · 100 MB 以上") { applySize(minimum: 100, maximum: 0) }
        Button("不限大小") { applySize(minimum: 0, maximum: 0) }
        Divider()
        Button("自定义精确范围…") { showsPreciseRange = true }
    }

    /// 提供最近日期、较早文件、不限和自定义创建时间范围。
    @ViewBuilder
    private var datePresetMenu: some View {
        Button("最近 30 天（推荐）") { applyDate(within: 30, olderThan: 0) }
        Button("最近 7 天") { applyDate(within: 7, olderThan: 0) }
        Button("30 天前") { applyDate(within: 0, olderThan: 30) }
        Button("90 天前") { applyDate(within: 0, olderThan: 90) }
        Button("不限时间") { applyDate(within: 0, olderThan: 0) }
        Divider()
        Button("自定义精确范围…") { showsPreciseRange = true }
    }

    /// 提示条件关系，并在配置不完整时给出明确错误状态。
    private var footerHint: some View {
        HStack {
            if rule.maximumSizeMB > 0 && rule.minimumSizeMB > rule.maximumSizeMB {
                Label("最小大小不能大于最大大小", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if rule.createdWithinDays > 0 && rule.olderThanDays > rule.createdWithinDays {
                Label("创建时间范围没有交集", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if !rule.sourcePathContains.isEmpty && !FileManager.default.fileExists(atPath: rule.sourcePathContains) {
                Label("来源位置当前不可用", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if !rule.hasCondition {
                Label("至少选择一个匹配条件", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if rule.destinationFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("请填写目标目录", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("已填写条件需同时满足", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !rule.isEnabled {
                Text("确认设置后再开启")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    /// 使用系统目录选择器写入可靠的绝对来源路径。
    private func chooseSourceDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择军令来源位置"
        panel.prompt = "使用此位置"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rule.sourcePathContains = url.standardizedFileURL.path
    }

    /// 返回用户主目录下常用文件夹的标准路径。
    private func homeDirectory(_ component: String) -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(component, isDirectory: true)
            .standardizedFileURL.path
    }

    /// 将绝对路径缩写为以波浪号开头的易读文本。
    private var sourceLocationLabel: String {
        guard !rule.sourcePathContains.isEmpty else { return "不限位置" }
        return (rule.sourcePathContains as NSString).abbreviatingWithTildeInPath
    }

    /// 返回当前大小范围对应的预设名称。
    private var sizePresetLabel: String {
        switch (rule.minimumSizeMB, rule.maximumSizeMB) {
        case (0, 0): return "不限大小"
        case (0, 10): return "0–10 MB"
        case (0, 100): return "0–100 MB"
        case (100, 0): return "100 MB 以上"
        default:
            let minimum = compactNumber(rule.minimumSizeMB)
            let maximum = rule.maximumSizeMB == 0 ? "不限" : compactNumber(rule.maximumSizeMB)
            return "\(minimum)–\(maximum) MB"
        }
    }

    /// 返回当前创建时间范围对应的预设名称。
    private var datePresetLabel: String {
        switch (rule.createdWithinDays, rule.olderThanDays) {
        case (0, 0): return "不限时间"
        case (7, 0): return "最近 7 天"
        case (30, 0): return "最近 30 天"
        case (0, 30): return "30 天前"
        case (0, 90): return "90 天前"
        default:
            if rule.createdWithinDays > 0 && rule.olderThanDays > 0 {
                return "\(rule.olderThanDays)–\(rule.createdWithinDays) 天前"
            }
            return "自定义时间"
        }
    }

    /// 应用大小预设并保持数值非负。
    private func applySize(minimum: Double, maximum: Double) {
        rule.minimumSizeMB = max(0, minimum)
        rule.maximumSizeMB = max(0, maximum)
    }

    /// 应用日期预设并保持天数非负。
    private func applyDate(within: Int, olderThan: Int) {
        rule.createdWithinDays = max(0, within)
        rule.olderThanDays = max(0, olderThan)
    }

    /// 去除整数容量末尾的小数点，保留必要的小数位。
    private func compactNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// 文件大小精确输入格式，允许一位小数且不接受负数。
    private static let sizeFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimum = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    /// 时间天数精确输入格式，只允许非负整数。
    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimum = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
