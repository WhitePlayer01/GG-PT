import Foundation
import Combine

struct MusicTrack: Codable, Equatable {
    var title: String
    var artist: String
    var album: String
    var source: String
    var sourceID: String
    var duration: Double?

    var key: String {
        [sourceID, title, artist, album].map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.joined(separator: "\u{1F}")
    }
}

struct ListeningRecord: Codable, Identifiable {
    var id = UUID()
    var track: MusicTrack
    var startedAt: Date
    var lastHeardAt: Date
    var listenedSeconds: Double = 0
}

/// 每次播放一条记录；暂停不计时，短时间恢复沿用同一次收听。
@MainActor
final class MusicHistoryStore: ObservableObject {
    @Published private(set) var records: [ListeningRecord] = []
    @Published private(set) var errorMessage: String?
    private let fileURL: URL
    private var activeID: UUID?
    private var previousDate: Date?
    private var previousPosition: Double?
    private var wasPlaying = false
    private var canSave = true

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("二爷收着/music-history.json")
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do {
            records = try JSONDecoder().decode([ListeningRecord].self, from: Data(contentsOf: self.fileURL))
        } catch {
            canSave = false
            errorMessage = "听歌记录读取失败，已保留原文件：\(error.localizedDescription)"
        }
    }

    func observe(_ track: MusicTrack?, playing: Bool, position: Double?, at date: Date = Date()) {
        guard canSave else { return }
        guard let track, playing, !track.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            wasPlaying = false
            previousDate = nil
            previousPosition = nil
            return
        }
        var index = records.firstIndex { $0.id == activeID }
        let replay = wasPlaying && (track.duration ?? 0) > 15
            && (previousPosition ?? 0) >= (track.duration ?? .infinity) - 10
            && (position ?? .infinity) < 3
        if let i = index, records[i].track.key != track.key || date.timeIntervalSince(records[i].lastHeardAt) > 1800 || replay {
            index = nil
        }
        if index == nil {
            let record = ListeningRecord(track: track, startedAt: date, lastHeardAt: date)
            records.insert(record, at: 0)
            activeID = record.id
            index = 0
            wasPlaying = false
        }
        guard let i = index else { return }
        if wasPlaying, let previousDate {
            let elapsed = date.timeIntervalSince(previousDate)
            // 休眠、来源失联及拖动进度条都不折算成收听时长。
            if elapsed > 0 && elapsed <= 15 {
                if let position, let oldPosition = previousPosition {
                    let progress = position - oldPosition
                    if progress >= 0 && progress <= elapsed + 2 {
                        records[i].listenedSeconds += min(elapsed, progress)
                    }
                } else {
                    records[i].listenedSeconds += elapsed
                }
            }
        }
        records[i].lastHeardAt = date
        previousDate = date
        previousPosition = position
        wasPlaying = true
        save()
    }

    func endSession() {
        activeID = nil
        wasPlaying = false
        previousDate = nil
        previousPosition = nil
    }

    func clear() {
        do {
            // 即使旧文件损坏，也只在用户主动清空后重新开始。
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            records = []
            canSave = true
            errorMessage = nil
            endSession()
        } catch { errorMessage = "清空失败：\(error.localizedDescription)" }
    }

    func export(to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(records).write(to: url, options: .atomic)
            errorMessage = nil
        } catch { errorMessage = "导出失败：\(error.localizedDescription)" }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: fileURL, options: .atomic)
            errorMessage = nil
        } catch { errorMessage = "听歌记录保存失败：\(error.localizedDescription)" }
    }
}
