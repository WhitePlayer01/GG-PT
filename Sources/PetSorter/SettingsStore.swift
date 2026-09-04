import Foundation
import AppKit

/// 一条可排序的自定义军令；所有已填写条件之间采用“并且”关系。
struct SortingRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "新军令"
    // 新建军令先保持关闭，避免推荐条件未经确认就开始移动文件。
    var isEnabled = false
    var fileNameContains = ""
    var extensions = ""
    var sourcePathContains = ""
    var minimumSizeMB = 0.0
    // 推荐模板覆盖最近 30 天内、100 MB 以下的日常文件。
    var maximumSizeMB = 100.0
    var createdWithinDays = 30
    var olderThanDays = 0
    var destinationFolder = "待整理"

    /// 判断军令是否至少配置了一个有效匹配条件。
    var hasCondition: Bool {
        !fileNameContains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !extensions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !sourcePathContains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || minimumSizeMB > 0
            || maximumSizeMB > 0
            || createdWithinDays > 0
            || olderThanDays > 0
    }

    /// 创建带默认名称和默认目标目录的新军令。
    init() {}

    private enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, fileNameContains, extensions, sourcePathContains
        case minimumSizeMB, maximumSizeMB, createdWithinDays, olderThanDays, destinationFolder
    }

    /// 兼容旧版本缺少时间条件等字段的已保存军令。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "新军令"
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        fileNameContains = try values.decodeIfPresent(String.self, forKey: .fileNameContains) ?? ""
        extensions = try values.decodeIfPresent(String.self, forKey: .extensions) ?? ""
        sourcePathContains = try values.decodeIfPresent(String.self, forKey: .sourcePathContains) ?? ""
        minimumSizeMB = try values.decodeIfPresent(Double.self, forKey: .minimumSizeMB) ?? 0
        maximumSizeMB = try values.decodeIfPresent(Double.self, forKey: .maximumSizeMB) ?? 0
        createdWithinDays = try values.decodeIfPresent(Int.self, forKey: .createdWithinDays) ?? 0
        olderThanDays = try values.decodeIfPresent(Int.self, forKey: .olderThanDays) ?? 0
        destinationFolder = try values.decodeIfPresent(String.self, forKey: .destinationFolder) ?? "自定义"
    }
}

/// 定义整理后的文件名生成方案。
enum SmartNamingStyle: String, CaseIterable, Identifiable {
    case original
    case dateOriginal
    case sourceDateOriginal
    case typeDateOriginal

    /// 使用枚举原始值作为 SwiftUI 列表稳定标识。
    var id: String { rawValue }

    /// 返回设置界面显示的中文方案名。
    var label: String {
        switch self {
        case .original: return "保留原名"
        case .dateOriginal: return "日期 + 原名"
        case .sourceDateOriginal: return "来源 + 日期 + 原名"
        case .typeDateOriginal: return "类型 + 日期 + 原名"
        }
    }
}

/// 定义应用内置的八种文件分类。
enum FileCategory: String, CaseIterable, Identifiable {
    case images = "图片"
    case documents = "文档"
    case videos = "视频"
    case audio = "音频"
    case archives = "压缩包"
    case code = "代码"
    case folders = "文件夹"
    case other = "其他"

    /// 使用分类中文名作为 SwiftUI 列表稳定标识。
    var id: String { rawValue }

    /// 返回当前分类可以识别的全部小写扩展名。
    var extensions: Set<String> {
        switch self {
        case .images: return ["jpg", "jpeg", "jfif", "png", "gif", "webp", "avif", "heic", "tiff", "bmp", "svg", "raw"]
        case .documents: return ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "md", "rtf", "csv", "webloc"]
        case .videos: return ["mp4", "mov", "mkv", "avi", "webm", "m4v"]
        case .audio: return ["mp3", "m4a", "wav", "aac", "flac", "ogg"]
        case .archives: return ["zip", "rar", "7z", "tar", "gz", "bz2", "dmg", "pkg"]
        case .code: return ["swift", "js", "ts", "tsx", "jsx", "py", "java", "kt", "go", "rs", "c", "cpp", "h", "html", "css", "json", "yaml", "yml", "xml", "sh", "sql"]
        case .folders, .other: return []
        }
    }

    /// 返回分类设置行使用的 SF Symbols 图标名。
    var symbol: String {
        switch self {
        case .images: return "photo"
        case .documents: return "doc.text"
        case .videos: return "film"
        case .audio: return "music.note"
        case .archives: return "archivebox"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .folders: return "folder"
        case .other: return "tray"
        }
    }
}

@MainActor
/// 管理所有用户设置，并在属性变更时持久化到 UserDefaults。
final class SettingsStore: ObservableObject {
    // 基础收纳、外观和引导设置。
    @Published var baseDirectory: String { didSet { defaults.set(baseDirectory, forKey: "baseDirectory") } }
    @Published var subfolders: [String: String] { didSet { defaults.set(subfolders, forKey: "subfolders") } }
    @Published var petScale: Double { didSet { defaults.set(petScale, forKey: "petScale") } }
    @Published private(set) var onboardingDirectoryChosen: Bool
    @Published private(set) var onboardingSampleDropped: Bool
    @Published private(set) var hasCompletedOnboarding: Bool
    @Published var automaticallyChecksForUpdates: Bool {
        didSet { defaults.set(automaticallyChecksForUpdates, forKey: "automaticallyChecksForUpdates") }
    }
    @Published var sortingRules: [SortingRule] { didSet { saveRules() } }
    @Published var detectDuplicates: Bool { didSet { defaults.set(detectDuplicates, forKey: "detectDuplicates") } }
    @Published var organizeByMonthFolder: Bool {
        didSet { defaults.set(organizeByMonthFolder, forKey: "organizeByMonthFolder") }
    }
    @Published var neteaseTrackingEnabled: Bool { didSet { defaults.set(neteaseTrackingEnabled, forKey: "neteaseTrackingEnabled") } }
    @Published var musicListeningAppearanceEnabled: Bool { didSet { defaults.set(musicListeningAppearanceEnabled, forKey: "musicListeningAppearanceEnabled") } }
    @Published var musicTrackingEnabled: Bool { didSet { defaults.set(musicTrackingEnabled, forKey: "musicTrackingEnabled") } }
    @Published var monitorDesktop: Bool { didSet { defaults.set(monitorDesktop, forKey: "monitorDesktop") } }
    @Published var monitorDownloads: Bool { didSet { defaults.set(monitorDownloads, forKey: "monitorDownloads") } }
    @Published var monitorIntervalMinutes: Int { didSet { defaults.set(monitorIntervalMinutes, forKey: "monitorIntervalMinutes") } }
    @Published var lastPatrolDate: Date? { didSet { defaults.set(lastPatrolDate, forKey: "lastPatrolDate") } }
    @Published var smartNamingStyle: SmartNamingStyle {
        didSet { defaults.set(smartNamingStyle.rawValue, forKey: "smartNamingStyle") }
    }
    @Published var showsSettingsButton: Bool {
        didSet { defaults.set(showsSettingsButton, forKey: "showsSettingsButton") }
    }
    @Published var petSkin: PetSkin {
        didSet { defaults.set(petSkin.rawValue, forKey: "petSkin") }
    }
    @Published var petWeapon: PetWeapon {
        didSet { defaults.set(petWeapon.rawValue, forKey: "petWeapon") }
    }
    @Published var petTheme: PetTheme {
        didSet { defaults.set(petTheme.rawValue, forKey: "petTheme") }
    }
    @Published var soundEffectsEnabled: Bool {
        didSet { defaults.set(soundEffectsEnabled, forKey: "soundEffectsEnabled") }
    }
    @Published var quietMode: Bool {
        didSet { defaults.set(quietMode, forKey: "quietMode") }
    }
    @Published var seasonalEffectsEnabled: Bool {
        didSet { defaults.set(seasonalEffectsEnabled, forKey: "seasonalEffectsEnabled") }
    }
    @Published var snapToScreenEdges: Bool {
        didSet { defaults.set(snapToScreenEdges, forKey: "snapToScreenEdges") }
    }
    @Published var showsDailyBadge: Bool {
        didSet { defaults.set(showsDailyBadge, forKey: "showsDailyBadge") }
    }
    // 使用屏幕标识和可见区域归一化坐标保存位置，显示器分辨率变化后仍可恢复。
    private(set) var savedPetScreenID: String
    private(set) var savedPetPositionX: Double
    private(set) var savedPetPositionY: Double
    // 拖动滑杆时实时发布桌宠窗口透明度，结束拖动后再统一持久化。
    @Published var petOpacity: Double

    private let defaults = UserDefaults.standard

    /// 从本机偏好设置加载配置，并为首次运行提供安全默认值。
    init() {
        baseDirectory = UserDefaults.standard.string(forKey: "baseDirectory")
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/云长卫").path
        subfolders = UserDefaults.standard.dictionary(forKey: "subfolders") as? [String: String]
            ?? Dictionary(uniqueKeysWithValues: FileCategory.allCases.map { ($0.rawValue, $0.rawValue) })
        let savedScale = UserDefaults.standard.double(forKey: "petScale")
        petScale = savedScale == 0 ? 1.0 : min(max(savedScale, 0.55), 1.45)
        onboardingDirectoryChosen = UserDefaults.standard.bool(forKey: "onboardingDirectoryChosen")
        onboardingSampleDropped = UserDefaults.standard.bool(forKey: "onboardingSampleDropped")
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        automaticallyChecksForUpdates = UserDefaults.standard.object(forKey: "automaticallyChecksForUpdates") as? Bool ?? true
        // 已保存的军令使用 JSON 数据存储，方便以后扩展规则字段。
        if let data = UserDefaults.standard.data(forKey: "sortingRules"),
           let decoded = try? JSONDecoder().decode([SortingRule].self, from: data) {
            sortingRules = decoded
        } else {
            sortingRules = []
        }
        detectDuplicates = UserDefaults.standard.object(forKey: "detectDuplicates") as? Bool ?? true
        // 新版改为单层年月目录；升级时沿用此前相关目录开关的状态。
        organizeByMonthFolder = UserDefaults.standard.object(forKey: "organizeByMonthFolder") as? Bool
            ?? UserDefaults.standard.object(forKey: "organizeByDateFolder") as? Bool
            ?? UserDefaults.standard.bool(forKey: "organizeByYearMonth")
        neteaseTrackingEnabled = UserDefaults.standard.bool(forKey: "neteaseTrackingEnabled")
        musicListeningAppearanceEnabled = UserDefaults.standard.object(forKey: "musicListeningAppearanceEnabled") as? Bool ?? true
        musicTrackingEnabled = UserDefaults.standard.bool(forKey: "musicTrackingEnabled")
        monitorDesktop = UserDefaults.standard.bool(forKey: "monitorDesktop")
        monitorDownloads = UserDefaults.standard.bool(forKey: "monitorDownloads")
        let savedInterval = UserDefaults.standard.integer(forKey: "monitorIntervalMinutes")
        monitorIntervalMinutes = [5, 15, 30, 60].contains(savedInterval) ? savedInterval : 30
        lastPatrolDate = UserDefaults.standard.object(forKey: "lastPatrolDate") as? Date
        smartNamingStyle = SmartNamingStyle(
            rawValue: UserDefaults.standard.string(forKey: "smartNamingStyle") ?? ""
        ) ?? .original
        showsSettingsButton = UserDefaults.standard.object(forKey: "showsSettingsButton") as? Bool ?? true
        petSkin = PetSkin(rawValue: UserDefaults.standard.string(forKey: "petSkin") ?? "") ?? .classic
        petWeapon = PetWeapon(rawValue: UserDefaults.standard.string(forKey: "petWeapon") ?? "") ?? .greenDragon
        petTheme = PetTheme(rawValue: UserDefaults.standard.string(forKey: "petTheme") ?? "") ?? .automatic
        soundEffectsEnabled = UserDefaults.standard.object(forKey: "soundEffectsEnabled") as? Bool ?? true
        quietMode = UserDefaults.standard.bool(forKey: "quietMode")
        seasonalEffectsEnabled = UserDefaults.standard.object(forKey: "seasonalEffectsEnabled") as? Bool ?? true
        snapToScreenEdges = UserDefaults.standard.object(forKey: "snapToScreenEdges") as? Bool ?? true
        showsDailyBadge = UserDefaults.standard.object(forKey: "showsDailyBadge") as? Bool ?? true
        savedPetScreenID = UserDefaults.standard.string(forKey: "savedPetScreenID") ?? ""
        savedPetPositionX = UserDefaults.standard.object(forKey: "savedPetPositionX") as? Double ?? -1
        savedPetPositionY = UserDefaults.standard.object(forKey: "savedPetPositionY") as? Double ?? -1
        let savedPetOpacity = UserDefaults.standard.double(forKey: "petOpacity")
        petOpacity = savedPetOpacity == 0 ? 1.0 : min(max(savedPetOpacity, 0.35), 1.0)
    }

    /// 返回分类对应的自定义子目录；空值回退到分类中文名。
    func subfolder(for category: FileCategory) -> String {
        let value = subfolders[category.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? category.rawValue : value
    }

    /// 更新指定分类的子目录名称。
    func updateSubfolder(_ value: String, for category: FileCategory) {
        subfolders[category.rawValue] = value
    }

    /// 在规则列表末尾添加一条默认军令。
    func addRule() {
        sortingRules.append(SortingRule())
    }

    /// 按稳定 UUID 删除一条军令。
    func removeRule(id: UUID) {
        sortingRules.removeAll { $0.id == id }
    }

    /// 将军令上移或下移一位，从而改变首条命中优先级。
    func moveRule(id: UUID, offset: Int) {
        guard let source = sortingRules.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard sortingRules.indices.contains(destination) else { return }
        sortingRules.swapAt(source, destination)
    }

    @discardableResult
    /// 显示系统目录选择器，并记录首次引导的目录选择步骤。
    func chooseBaseDirectory() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "选择文件收纳位置"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            baseDirectory = url.path
            onboardingDirectoryChosen = true
            defaults.set(true, forKey: "onboardingDirectoryChosen")
            return true
        }
        return false
    }

    /// 标记首次引导的示例文件已经成功拖放整理。
    func markOnboardingSampleDropped() {
        onboardingSampleDropped = true
        defaults.set(true, forKey: "onboardingSampleDropped")
    }

    /// 完成首次引导，后续启动不再自动展示引导窗口。
    func completeOnboarding() {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: "hasCompletedOnboarding")
    }

    /// 清除引导进度，供调试或未来的“重新显示引导”功能使用。
    func resetOnboarding() {
        onboardingDirectoryChosen = false
        onboardingSampleDropped = false
        hasCompletedOnboarding = false
        defaults.set(false, forKey: "onboardingDirectoryChosen")
        defaults.set(false, forKey: "onboardingSampleDropped")
        defaults.set(false, forKey: "hasCompletedOnboarding")
    }

    /// 创建并在 Finder 中显示总收纳目录。
    func revealBaseDirectory() {
        let url = URL(fileURLWithPath: baseDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 限制并保存桌宠窗口透明度；在滑杆结束编辑或恢复默认值时调用。
    func persistPetOpacity() {
        petOpacity = min(max(petOpacity, 0.35), 1.0)
        defaults.set(petOpacity, forKey: "petOpacity")
    }

    /// 保存桌宠在当前显示器可见区域中的相对中心位置。
    func savePetPosition(screenID: String, normalizedX: Double, normalizedY: Double) {
        savedPetScreenID = screenID
        savedPetPositionX = min(max(normalizedX, 0), 1)
        savedPetPositionY = min(max(normalizedY, 0), 1)
        defaults.set(savedPetScreenID, forKey: "savedPetScreenID")
        defaults.set(savedPetPositionX, forKey: "savedPetPositionX")
        defaults.set(savedPetPositionY, forKey: "savedPetPositionY")
    }

    /// 将全部军令编码为 JSON 并保存到用户偏好设置。
    private func saveRules() {
        guard let data = try? JSONEncoder().encode(sortingRules) else { return }
        defaults.set(data, forKey: "sortingRules")
    }
}
    // 第二阶段自动整理设置；监控功能默认关闭以避免升级后自动移动文件。
