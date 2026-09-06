import Foundation

/* 一套方案包含基础外观和按场景保存的素材。
 三个槽位始终存在；空槽位使用内置外观起步，应用资源不被改写。 */
enum ArtworkScene: String, CaseIterable, Identifiable, Codable {
    case idle, receiving, sword, complete, failure, listening
    var id: String { rawValue }
    // 完成状态保留用于旧配置兼容和内置反馈，不再作为可替换场景。
    static var editableScenes: [ArtworkScene] { allCases.filter { $0 != .complete } }
    var title: String {
        switch self {
        case .idle: return "待机"
        case .receiving: return "拖入接收"
        case .sword: return "收纳挥刀"
        case .complete: return "收纳完成"
        case .failure: return "操作失败"
        case .listening: return "听歌陪伴"
        }
    }
    var detail: String {
        switch self {
        case .idle: return "没有操作时显示，持续循环"
        case .receiving: return "与收纳挥刀共用素材，拖入文件时播放"
        case .sword: return "拖入、收到文件时统一播放一次；听歌期间也优先挥刀"
        case .complete: return "收纳完成时显示，随后恢复待机"
        case .failure: return "操作失败时显示，随后恢复待机"
        case .listening: return "每款停留 9.6 秒，五款随机轮播"
        }
    }
    var loops: Bool { self == .idle || self == .listening }
    func key(variant: ListeningAnimationVariant = .sway) -> String {
        // 接收只作为界面入口，始终读写同一份挥刀素材。
        let assetScene = self == .receiving ? ArtworkScene.sword : self
        return assetScene.rawValue + (self == .listening ? "/\(variant.rawValue)" : "")
    }
}

/// 文件只记录本机素材目录的编号，不依赖用户原文件的位置。
struct CustomArtwork: Codable, Equatable {
    var directory: String
    var name: String
    var durations: [Double]
    var scale = 1.0
    var offsetX = 0.0
    var offsetY = 0.0
    var preservesMotion = true
    var video: VideoArtwork? = nil
    var isAnimated: Bool { video != nil || durations.count > 1 }
    var duration: Double { video?.duration ?? durations.reduce(0, +) }

    func frameIndex(at elapsed: Double, loops: Bool) -> Int {
        guard duration > 0, !durations.isEmpty else { return 0 }
        // 一次性反馈停在最后一帧，只有常驻场景才循环。
        var remaining = loops ? max(0, elapsed).truncatingRemainder(dividingBy: duration) : max(0, elapsed)
        for (index, seconds) in durations.enumerated() {
            if remaining < seconds { return index }
            remaining -= seconds
        }
        return durations.count - 1
    }
}

struct AppearanceProfile: Codable, Equatable {
    var name = "经典关羽"
    var isConfigured = true
    var scale = 1.0
    var opacity = 1.0
    var quiet = false
    var seasonal = true
    var sound = true
    var artworks: [String: CustomArtwork] = [:]
    private enum CodingKeys: String, CodingKey {
        case name, isConfigured, scale, opacity, quiet, seasonal, sound, artworks
    }
}

/* 旧版本使用角色前缀保存素材。读取时仅迁移选中角色的素材，
 新配置不再保存皮肤、兵器或主题字段；原始素材文件无需移动。 */
extension AppearanceProfile {
    private enum LegacyKeys: String, CodingKey { case skin }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        let oldPrefix = (try legacy.decodeIfPresent(String.self, forKey: .skin) ?? "classic") + "/"
        let stored = try values.decodeIfPresent([String: CustomArtwork].self, forKey: .artworks) ?? [:]
        var migrated: [String: CustomArtwork] = [:]
        for scene in ArtworkScene.allCases {
            let variants: [ListeningAnimationVariant] = scene == .listening ? ListeningAnimationVariant.allCases : [.sway]
            for variant in variants {
                let key = scene.key(variant: variant)
                // 新格式优先，其次使用旧方案选中的角色素材。
                if let asset = stored[key] ?? stored[oldPrefix + key] ?? stored["classic/" + key] {
                    migrated[key] = asset
                }
            }
        }
        self.init(name: try values.decodeIfPresent(String.self, forKey: .name) ?? "经典关羽",
                  isConfigured: try values.decodeIfPresent(Bool.self, forKey: .isConfigured) ?? true,
                  scale: try values.decodeIfPresent(Double.self, forKey: .scale) ?? 1,
                  opacity: try values.decodeIfPresent(Double.self, forKey: .opacity) ?? 1,
                  quiet: try values.decodeIfPresent(Bool.self, forKey: .quiet) ?? false,
                  seasonal: try values.decodeIfPresent(Bool.self, forKey: .seasonal) ?? true,
                  sound: try values.decodeIfPresent(Bool.self, forKey: .sound) ?? true,
                  artworks: migrated)
    }
}

struct AppearanceLibrary: Codable, Equatable {
    var version = 1
    var activeIndex = 0
    var profiles: [AppearanceProfile]

    init(initial: AppearanceProfile = AppearanceProfile()) {
        profiles = [initial, AppearanceProfile(name: "方案二", isConfigured: false),
                    AppearanceProfile(name: "方案三", isConfigured: false)]
    }

    /// 解码后检查数量和数值，损坏配置保留原件，由设置页报告错误。
    var isValid: Bool {
        version == 1 && profiles.count == 3 && profiles.indices.contains(activeIndex)
            && profiles.allSatisfy { profile in
                (0.55...1.45).contains(profile.scale) && (0.35...1).contains(profile.opacity)
                    && profile.artworks.values.allSatisfy { asset in
                        UUID(uuidString: asset.directory) != nil && (1...120).contains(asset.durations.count)
                            && (asset.video?.isValid ?? true)
                            && asset.durations.allSatisfy { $0.isFinite && (0.02...10).contains($0) }
                            && (0.25...1.5).contains(asset.scale)
                            && (-80...80).contains(asset.offsetX) && (-80...80).contains(asset.offsetY)
                    }
            }
    }
}
