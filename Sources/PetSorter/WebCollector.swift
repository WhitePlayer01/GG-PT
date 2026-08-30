import Foundation
import UniformTypeIdentifiers
import Darwin

/// 网页投递解析或下载阶段可能返回的用户可读错误。
enum WebCollectorError: LocalizedError {
    case invalidLink
    case unsupportedAddress
    case downloadFailed

    /// 将内部错误映射为桌宠气泡使用的中文说明。
    var errorDescription: String? {
        switch self {
        case .invalidLink: return "投递链接不完整"
        case .unsupportedAddress: return "只支持 http 或 https 网页"
        case .downloadFailed: return "网页素材下载失败"
        }
    }
}

/// 浏览器批量图片参数中的单条素材。
private struct WebBatchItem: Decodable {
    let url: String
    let kind: String?
    let title: String?
    let source: String?
}

/// 写入文件扩展属性的网页来源信息，后续版本可直接读取并展示。
private struct WebSourceMetadata: Codable {
    let file: String
    let source: String
    let title: String
    let capturedAt: String
    let tags: [String]
}

@MainActor
/// 解析浏览器扩展深链，把网页书签或远程媒体交给本地整理引擎。
enum WebCollector {
    /// 校验 `erye://collect` 参数，在临时目录生成文件并自动分类。
    static func collect(
        deepLink: URL,
        settings: SettingsStore,
        history: OperationHistoryStore
    ) async throws -> SortResult {
        guard deepLink.scheme == "erye", deepLink.host == "collect",
              let components = URLComponents(url: deepLink, resolvingAgainstBaseURL: false) else {
            throw WebCollectorError.invalidLink
        }
        // 外部深链可能包含重复参数；逐项覆盖可以避免恶意 URL 触发字典崩溃。
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] { values[item.name] = item.value ?? "" }
        let kind = values["kind"] ?? "page"
        let title = values["title"] ?? ""
        let pageTitle = values["pageTitle"] ?? title
        let source = values["source"] ?? values["url"] ?? ""
        let capturedAt = values["capturedAt"] ?? ISO8601DateFormatter().string(from: Date())
        let tags = (values["tags"] ?? "")
            .components(separatedBy: CharacterSet(charactersIn: "，,"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let destination = values["destination"] ?? ""
        // 每次投递使用独立临时目录，结束时无论成功失败都清理。
        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("erye-web-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }

        let stagedFiles: [URL]
        if kind == "batch" {
            stagedFiles = try await stageBatch(values["items"] ?? "", into: stagingDirectory)
        } else if kind == "image-data" {
            stagedFiles = [try stageEmbeddedImage(
                values["content"] ?? "",
                mimeType: values["mimeType"] ?? "",
                title: title,
                into: stagingDirectory
            )]
        } else if kind == "markdown" {
            let target = try validatedNetworkURL(values["url"] ?? source)
            stagedFiles = [try makeMarkdown(
                values["content"] ?? "",
                target: target,
                title: title,
                capturedAt: capturedAt,
                tags: tags,
                in: stagingDirectory
            )]
        } else {
            let target = try validatedNetworkURL(values["url"] ?? "")
            if ["image", "media"].contains(kind) {
                stagedFiles = [try await download(target, title: title, into: stagingDirectory)]
            } else {
                stagedFiles = [try makeWebloc(target, title: title, in: stagingDirectory)]
            }
        }

        let result = FileOrganizer.organize(
            stagedFiles,
            settings: settings,
            forcedDestinationFolder: destination
        )
        for item in result.movedItems {
            let file = URL(fileURLWithPath: item.destinationPath)
            try? writeSourceMetadata(
                to: file,
                source: source,
                title: pageTitle,
                capturedAt: capturedAt,
                tags: tags
            )
        }
        history.record(
            result,
            source: "网页投递",
            discardsOnUndo: true,
            sourceTitle: pageTitle,
            sourceURL: source
        )
        return result
    }

    /// 拒绝本地文件、脚本和浏览器内部页面，仅允许远程网页素材。
    private static func validatedNetworkURL(_ value: String) throws -> URL {
        guard let target = URL(string: value), !value.isEmpty else { throw WebCollectorError.invalidLink }
        guard ["http", "https"].contains(target.scheme?.lowercased() ?? "") else {
            throw WebCollectorError.unsupportedAddress
        }
        return target
    }

    /// 解析批量参数并依次下载，单次最多接受 30 张图片。
    private static func stageBatch(_ encodedItems: String, into directory: URL) async throws -> [URL] {
        guard let data = encodedItems.data(using: .utf8),
              let items = try? JSONDecoder().decode([WebBatchItem].self, from: data),
              !items.isEmpty else {
            throw WebCollectorError.invalidLink
        }
        var staged: [URL] = []
        for item in items.prefix(30) {
            let target = try validatedNetworkURL(item.url)
            let file = try await download(target, title: item.title ?? "网页图片", into: directory)
            staged.append(file)
        }
        return staged
    }

    /// 将扩展从浏览器会话中读取的图片 Data URL 写入暂存目录。
    private static func stageEmbeddedImage(
        _ dataURL: String,
        mimeType: String,
        title: String,
        into directory: URL
    ) throws -> URL {
        guard dataURL.hasPrefix("data:"),
              let comma = dataURL.firstIndex(of: ",") else {
            throw WebCollectorError.downloadFailed
        }
        let metadata = String(dataURL[dataURL.index(dataURL.startIndex, offsetBy: 5)..<comma])
        guard metadata.lowercased().contains(";base64") else {
            throw WebCollectorError.downloadFailed
        }
        let encoded = String(dataURL[dataURL.index(after: comma)...])
        guard let data = Data(base64Encoded: encoded, options: [.ignoreUnknownCharacters]), !data.isEmpty else {
            throw WebCollectorError.downloadFailed
        }

        let detectedMIME = mimeType.isEmpty ? (metadata.split(separator: ";").first.map(String.init) ?? "image/png") : mimeType
        let fallbackExtension = UTType(mimeType: detectedMIME)?.preferredFilenameExtension ?? "png"
        var candidate = cleanFileName(title, fallback: "网页图片")
        if URL(fileURLWithPath: candidate).pathExtension.isEmpty {
            candidate += ".\(fallbackExtension)"
        }
        let destination = availableStagingDestination(named: candidate, in: directory)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    /// 把浏览器抽取的正文写成带 YAML 来源头的 Markdown 文件。
    private static func makeMarkdown(
        _ content: String,
        target: URL,
        title: String,
        capturedAt: String,
        tags: [String],
        in directory: URL
    ) throws -> URL {
        let rawName = title.isEmpty ? (target.host ?? "网页正文") : title
        let destination = directory.appendingPathComponent(cleanFileName(rawName, fallback: "网页正文") + ".md")
        let safeTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let safeURL = target.absoluteString.replacingOccurrences(of: "\"", with: "\\\"")
        let tagText = tags.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ", ")
        let document = """
        ---
        title: "\(safeTitle)"
        source: "\(safeURL)"
        captured_at: "\(capturedAt)"
        tags: [\(tagText)]
        ---

        \(content)
        """
        try document.write(to: destination, atomically: true, encoding: .utf8)
        return destination
    }

    /// 将来源、采集时间和标签写进文件自身，不额外制造会参与分类的旁车文件。
    private static func writeSourceMetadata(
        to file: URL,
        source: String,
        title: String,
        capturedAt: String,
        tags: [String]
    ) throws {
        let metadata = WebSourceMetadata(
            file: file.lastPathComponent,
            source: source,
            title: title,
            capturedAt: capturedAt,
            tags: tags
        )
        let data = try JSONEncoder().encode(metadata)
        let result = data.withUnsafeBytes { bytes in
            setxattr(
                file.path,
                "com.yunchangwei.web-source",
                bytes.baseAddress,
                bytes.count,
                0,
                0
            )
        }
        if result != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    /// 下载远程媒体，并根据响应文件名或 MIME 类型补全安全文件名。
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
        let destination = availableStagingDestination(named: candidate, in: directory)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    /// 批量页面里常有同名图片，暂存阶段也使用编号避免相互覆盖。
    private static func availableStagingDestination(named name: String, in directory: URL) -> URL {
        let manager = FileManager.default
        let original = directory.appendingPathComponent(name)
        guard manager.fileExists(atPath: original.path) else { return original }
        let value = URL(fileURLWithPath: name)
        let stem = value.deletingPathExtension().lastPathComponent
        let ext = value.pathExtension
        var number = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem)-\(number)" : "\(stem)-\(number).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !manager.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }

    /// 生成 macOS 可双击打开的 XML `.webloc` 文件。
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

    /// 替换文件系统保留字符，并把过长网页标题限制在 120 个字符内。
    private static func cleanFileName(_ value: String, fallback: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = value.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? fallback : cleaned).prefix(120))
    }
}
