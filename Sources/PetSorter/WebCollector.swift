import Foundation
import UniformTypeIdentifiers

enum WebCollectorError: LocalizedError {
    case invalidLink
    case unsupportedAddress
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidLink: return "投递链接不完整"
        case .unsupportedAddress: return "只支持 http 或 https 网页"
        case .downloadFailed: return "网页素材下载失败"
        }
    }
}

@MainActor
enum WebCollector {
    static func collect(
        deepLink: URL,
        settings: SettingsStore,
        history: OperationHistoryStore
    ) async throws -> SortResult {
        guard deepLink.scheme == "erye", deepLink.host == "collect",
              let components = URLComponents(url: deepLink, resolvingAgainstBaseURL: false),
              let targetValue = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let target = URL(string: targetValue) else {
            throw WebCollectorError.invalidLink
        }
        guard ["http", "https"].contains(target.scheme?.lowercased() ?? "") else {
            throw WebCollectorError.unsupportedAddress
        }

        let kind = components.queryItems?.first(where: { $0.name == "kind" })?.value ?? "page"
        let title = components.queryItems?.first(where: { $0.name == "title" })?.value ?? ""
        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("erye-web-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }

        let stagedFile: URL
        if ["image", "media"].contains(kind) {
            stagedFile = try await download(target, title: title, into: stagingDirectory)
        } else {
            stagedFile = try makeWebloc(target, title: title, in: stagingDirectory)
        }

        let result = FileOrganizer.organize([stagedFile], settings: settings)
        history.record(result, source: "网页投递", discardsOnUndo: true)
        return result
    }

    private static func download(_ target: URL, title: String, into directory: URL) async throws -> URL {
        let (temporaryURL, response) = try await URLSession.shared.download(from: target)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WebCollectorError.downloadFailed
        }

        var candidate = response.suggestedFilename ?? target.lastPathComponent
        if candidate.isEmpty || candidate == "/" { candidate = cleanFileName(title, fallback: "网页素材") }
        if URL(fileURLWithPath: candidate).pathExtension.isEmpty,
           let mime = response.mimeType,
           let ext = UTType(mimeType: mime)?.preferredFilenameExtension {
            candidate += ".\(ext)"
        }
        candidate = cleanFileName(candidate, fallback: "网页素材")
        let destination = directory.appendingPathComponent(candidate)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private static func makeWebloc(_ target: URL, title: String, in directory: URL) throws -> URL {
        let rawName = title.isEmpty ? (target.host ?? "网页收藏") : title
        let name = cleanFileName(rawName, fallback: "网页收藏") + ".webloc"
        let destination = directory.appendingPathComponent(name)
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["URL": target.absoluteString],
            format: .xml,
            options: 0
        )
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private static func cleanFileName(_ value: String, fallback: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = value.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? fallback : cleaned).prefix(120))
    }
}
