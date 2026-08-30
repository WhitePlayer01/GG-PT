import Foundation
import AppKit

/// 可选角色皮肤；经典皮肤拥有完整四态立绘，限定皮肤使用专属站姿配合程序动画。
enum PetSkin: String, CaseIterable, Identifiable {
    case classic
    case crimson
    case midnight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: return "云长青"
        case .crimson: return "赤焰镇守"
        case .midnight: return "玄甲夜巡"
        }
    }

    var detail: String {
        switch self {
        case .classic: return "青袍金甲，经典四态"
        case .crimson: return "朱红战袍，暖金锋芒"
        case .midnight: return "玄青夜甲，银月冷光"
        }
    }

    var idleArtworkName: String {
        switch self {
        case .classic: return "guan-yu-idle"
        case .crimson: return "guan-yu-skin-crimson"
        case .midnight: return "guan-yu-skin-midnight"
        }
    }
}

/// 武器外观以独立光效和状态徽记呈现，避免改变角色碰撞范围。
enum PetWeapon: String, CaseIterable, Identifiable {
    case greenDragon
    case ember
    case frost

    var id: String { rawValue }

    var label: String {
        switch self {
        case .greenDragon: return "青龙偃月"
        case .ember: return "赤焰长锋"
        case .frost: return "霜华月刃"
        }
    }

    var symbol: String {
        switch self {
        case .greenDragon: return "leaf.fill"
        case .ember: return "flame.fill"
        case .frost: return "snowflake"
        }
    }
}

/// 桌宠背景主题只影响氛围、光环和消息气泡，不遮挡透明角色。
enum PetTheme: String, CaseIterable, Identifiable {
    case parchment
    case night
    case festive
    case automatic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .parchment: return "古卷暖金"
        case .night: return "夜巡玄青"
        case .festive: return "节庆朱红"
        case .automatic: return "随时令变化"
        }
    }
}

/// 服务层向桌宠发布的明确反馈类型，避免依赖文案关键词猜测状态。
enum PetEventOutcome {
    case neutral
    case failure
    case complete
}

/// 当前日期对应的节气或节日限定表现。
struct SeasonalMoment: Equatable {
    let name: String
    let greeting: String
    let symbol: String

    /// 优先识别传统节日，再识别公历节日和二十四节气的近似日期。
    static func current(on date: Date = Date(), calendar: Calendar = .current) -> SeasonalMoment? {
        let chinese = Calendar(identifier: .chinese)
        let lunar = chinese.dateComponents([.month, .day], from: date)
        if lunar.month == 1 && lunar.day == 1 {
            return SeasonalMoment(name: "新春", greeting: "新岁开营，万卷归仓。", symbol: "sparkles")
        }
        if lunar.month == 5 && lunar.day == 5 {
            return SeasonalMoment(name: "端午", greeting: "蒲风送令，案卷安康。", symbol: "leaf.fill")
        }
        if lunar.month == 8 && lunar.day == 15 {
            return SeasonalMoment(name: "中秋", greeting: "月满云仓，诸事有序。", symbol: "moon.stars.fill")
        }

        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let fixed: [(Int, Int, SeasonalMoment)] = [
            (1, 1, SeasonalMoment(name: "元旦", greeting: "新年首令，收纳开门红。", symbol: "sparkles")),
            (5, 1, SeasonalMoment(name: "劳动节", greeting: "勤整有功，今日亦从容。", symbol: "hammer.fill")),
            (10, 1, SeasonalMoment(name: "国庆", greeting: "山河锦绣，库藏井然。", symbol: "flag.fill"))
        ]
        if let holiday = fixed.first(where: { $0.0 == month && $0.1 == day })?.2 { return holiday }

        let terms: [(Int, Int, String, String)] = [
            (1, 5, "小寒", "寒意初深，卷宗宜妥藏。"), (1, 20, "大寒", "岁寒守库，诸物无虞。"),
            (2, 4, "立春", "东风解冻，新卷归仓。"), (2, 19, "雨水", "好雨知时，文卷不湿。"),
            (3, 5, "惊蛰", "春雷动，旧案醒。"), (3, 20, "春分", "昼夜均分，收纳有衡。"),
            (4, 4, "清明", "清风明净，案头亦清。"), (4, 20, "谷雨", "雨生百谷，仓纳万物。"),
            (5, 5, "立夏", "长日初启，收纳清爽。"), (5, 21, "小满", "小得盈满，归档正好。"),
            (6, 5, "芒种", "有收有种，件件归位。"), (6, 21, "夏至", "日长事简，卷卷有序。"),
            (7, 7, "小暑", "暑气初盛，案头留清凉。"), (7, 22, "大暑", "炎威正盛，收纳不乱。"),
            (8, 7, "立秋", "凉风将至，旧物入仓。"), (8, 23, "处暑", "暑气渐收，桌面亦清。"),
            (9, 7, "白露", "露白风清，文卷安放。"), (9, 23, "秋分", "秋色平分，归档有度。"),
            (10, 8, "寒露", "寒露凝光，库藏温稳。"), (10, 23, "霜降", "霜落长锋，杂物归营。"),
            (11, 7, "立冬", "冬令初至，收纳入静。"), (11, 22, "小雪", "微雪巡营，文件无忧。"),
            (12, 7, "大雪", "雪覆千门，云仓自暖。"), (12, 21, "冬至", "一阳初生，万卷归一。")
        ]
        guard let term = terms.first(where: { $0.0 == month && abs($0.1 - day) <= 2 }) else { return nil }
        let symbol = [12, 1, 2].contains(month) ? "snowflake" : ([3, 4, 5].contains(month) ? "leaf.fill" : "wind")
        return SeasonalMoment(name: term.2, greeting: term.3, symbol: symbol)
    }
}

/// 依据文件类型给出短句，控制在桌宠气泡两行内。
enum PetDialogue {
    static func receiving(category: FileCategory?) -> String {
        switch category {
        case .images: return "丹青交我，且放手。"
        case .documents: return "文书呈上，关某接令。"
        case .videos: return "影卷送来，稳稳接住。"
        case .audio: return "音律入营，交予关某。"
        case .archives: return "包裹虽重，尽管放下。"
        case .code: return "机巧之卷，且来验收。"
        case .folders: return "整营移交，关某接管。"
        case .other: return "来物尽管交来。"
        case nil: return "军令已至，关某接着。"
        }
    }

    static func completed(category: FileCategory?, count: Int) -> String {
        let suffix = count > 1 ? "共 \(count) 件。" : ""
        switch category {
        case .images: return "丹青入库，毫发无损。\(suffix)"
        case .documents: return "文书归卷，查用有序。\(suffix)"
        case .videos: return "影卷已收，妥置库中。\(suffix)"
        case .audio: return "音册归位，弦歌不乱。\(suffix)"
        case .archives: return "包裹封存，分毫未伤。\(suffix)"
        case .code: return "机巧之卷，已妥善收纳。\(suffix)"
        case .folders: return "整营归建，目录不乱。\(suffix)"
        case .other: return "来物已收，尽入其位。\(suffix)"
        case nil: return count > 0 ? "军令已成，共收 \(count) 件。" : "此令已妥善处置。"
        }
    }
}

/// 使用系统内置音效，保持安装包轻量且不访问网络。
enum PetSoundPlayer {
    static func play(outcome: PetEventOutcome, enabled: Bool, quietMode: Bool) {
        guard enabled, !quietMode else { return }
        let name: NSSound.Name
        switch outcome {
        case .complete: name = NSSound.Name("Glass")
        case .failure: name = NSSound.Name("Basso")
        case .neutral: name = NSSound.Name("Pop")
        }
        NSSound(named: name)?.play()
    }
}
