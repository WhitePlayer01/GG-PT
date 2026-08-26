import Foundation
import AppKit

enum FileCategory: String, CaseIterable, Identifiable {
    case images = "图片"
    case documents = "文档"
    case videos = "视频"
    case audio = "音频"
    case archives = "压缩包"
    case code = "代码"
    case folders = "文件夹"
    case other = "其他"

    var id: String { rawValue }

    var extensions: Set<String> {
        switch self {
        case .images: return ["jpg", "jpeg", "png", "gif", "webp", "heic", "tiff", "bmp", "svg", "raw"]
        case .documents: return ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "md", "rtf", "csv", "webloc"]
        case .videos: return ["mp4", "mov", "mkv", "avi", "webm", "m4v"]
        case .audio: return ["mp3", "m4a", "wav", "aac", "flac", "ogg"]
        case .archives: return ["zip", "rar", "7z", "tar", "gz", "bz2", "dmg", "pkg"]
        case .code: return ["swift", "js", "ts", "tsx", "jsx", "py", "java", "kt", "go", "rs", "c", "cpp", "h", "html", "css", "json", "yaml", "yml", "xml", "sh", "sql"]
        case .folders, .other: return []
        }
    }

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
final class SettingsStore: ObservableObject {
    @Published var baseDirectory: String { didSet { defaults.set(baseDirectory, forKey: "baseDirectory") } }
    @Published var subfolders: [String: String] { didSet { defaults.set(subfolders, forKey: "subfolders") } }
    @Published var petScale: Double { didSet { defaults.set(petScale, forKey: "petScale") } }

    private let defaults = UserDefaults.standard

    init() {
        baseDirectory = UserDefaults.standard.string(forKey: "baseDirectory")
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/二爷收着").path
        subfolders = UserDefaults.standard.dictionary(forKey: "subfolders") as? [String: String]
            ?? Dictionary(uniqueKeysWithValues: FileCategory.allCases.map { ($0.rawValue, $0.rawValue) })
        let savedScale = UserDefaults.standard.double(forKey: "petScale")
        petScale = savedScale == 0 ? 1.0 : min(max(savedScale, 0.55), 1.45)
    }

    func subfolder(for category: FileCategory) -> String {
        let value = subfolders[category.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? category.rawValue : value
    }

    func updateSubfolder(_ value: String, for category: FileCategory) {
        subfolders[category.rawValue] = value
    }

    func chooseBaseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择文件收纳位置"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            baseDirectory = url.path
        }
    }

    func revealBaseDirectory() {
        let url = URL(fileURLWithPath: baseDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
