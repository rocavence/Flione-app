import Foundation
import Observation

/// YouTube Music 的播放次數與最後一次播放：YouTube 不提供，由 Flione 在這台 Mac 記錄。
/// 聽超過 30 秒（短於 1 分鐘的歌聽一半）算一次，與常見的 scrobble 規則相同
@MainActor @Observable
final class LocalPlayCounts {
    struct Entry: Codable, Sendable {
        var count: Int
        var last: Date
    }

    private(set) var entries: [String: Entry] = [:]
    @ObservationIgnored private let file: URL

    init(file: URL = LocalPlayCounts.defaultFile) {
        self.file = file
        if let data = try? Data(contentsOf: file), let stored = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = stored
        }
    }

    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.finify.Finify/youtube-plays.json")
    }

    static func counts(_ track: Track, position: TimeInterval) -> Bool {
        let threshold = track.duration > 0 ? min(30, track.duration / 2) : 30
        return position >= threshold
    }

    func entry(for trackID: String) -> Entry? { entries[trackID] }

    /// 播放超過門檻時由 PlayerManager 呼叫（門檻判斷在 PlayerManager，見 counts）
    func record(_ track: Track, at date: Date = .now) {
        guard !track.isPlaceholder else { return }
        var entry = entries[track.id] ?? Entry(count: 0, last: date)
        entry.count += 1
        entry.last = date
        entries[track.id] = entry
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
