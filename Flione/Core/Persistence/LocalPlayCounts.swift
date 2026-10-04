import AppKit
import Foundation
import Observation

/// YouTube Music 的播放次數與最後一次播放：YouTube 不提供，由 Flione 在這台 Mac 記錄（D51）。
/// 聽超過 30 秒（短於 1 分鐘的歌聽一半）算一次，與常見的 scrobble 規則相同。
///
/// iCloud 同步（設定 → 音樂來源，預設關閉）：每台 Mac 只寫自己的檔案到 iCloud Drive 的
/// `Flione/YouTube Plays/<裝置>.json`，顯示時把所有檔案加總（次數相加、最後播放取最新）。
/// 各寫各的，兩台同時播放也不會互相蓋掉。用 iCloud Drive 的檔案而不是 CloudKit：不需要付費的開發者帳號
@MainActor @Observable
final class LocalPlayCounts {
    struct Entry: Codable, Sendable, Equatable {
        var count: Int
        var last: Date
    }

    static let syncKey = "FinifyYouTubePlaysICloud"
    private static let deviceKey = "FinifyDeviceID"

    /// 這台 Mac 的紀錄
    private var own: [String: Entry] = [:]
    /// 其他 Mac 的紀錄（加總後）
    private var others: [String: Entry] = [:]
    private(set) var syncError: String?

    private(set) var isSyncing = UserDefaults.standard.bool(forKey: LocalPlayCounts.syncKey)

    @ObservationIgnored private let file: URL
    @ObservationIgnored private let cloudFolder: URL?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    init(file: URL = LocalPlayCounts.defaultFile, cloudFolder: URL? = LocalPlayCounts.defaultCloudFolder) {
        self.file = file
        self.cloudFolder = cloudFolder
        if let data = try? Data(contentsOf: file), let stored = try? JSONDecoder().decode([String: Entry].self, from: data) {
            own = stored
        }
        reloadCloud()
        // 回到 Flione 時讀一次其他 Mac 的紀錄
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadCloud() }
        }
    }

    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.finify.Finify/youtube-plays.json")
    }

    /// iCloud Drive 的資料夾；沒有開 iCloud Drive 時為 nil
    static var defaultCloudFolder: URL? {
        let drive = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Mobile Documents/com~apple~CloudDocs")
        guard FileManager.default.fileExists(atPath: drive.path) else { return nil }
        return drive.appending(path: "Flione/YouTube Plays", directoryHint: .isDirectory)
    }

    static var isCloudAvailable: Bool { defaultCloudFolder != nil }

    /// 這台 Mac 在 iCloud 的檔名：電腦名稱＋固定的 id（改電腦名稱不會變成另一台）
    private static var deviceFileName: String {
        let id = UserDefaults.standard.string(forKey: deviceKey) ?? {
            let new = UUID().uuidString.prefix(8).lowercased()
            UserDefaults.standard.set(String(new), forKey: deviceKey)
            return String(new)
        }()
        let name = (Host.current().localizedName ?? "Mac").replacingOccurrences(of: "/", with: "-")
        return "\(name) (\(id)).json"
    }

    static func counts(_ track: Track, position: TimeInterval) -> Bool {
        let threshold = track.duration > 0 ? min(30, track.duration / 2) : 30
        return position >= threshold
    }

    /// 這台加上其他 Mac 的紀錄
    func entry(for trackID: String) -> Entry? {
        switch (own[trackID], others[trackID]) {
        case (nil, nil): nil
        case let (mine?, nil): mine
        case let (nil, theirs?): theirs
        case let (mine?, theirs?): Entry(count: mine.count + theirs.count, last: max(mine.last, theirs.last))
        }
    }

    /// 播放超過門檻時由 PlayerManager 呼叫（門檻判斷在 PlayerManager，見 counts）
    func record(_ track: Track, at date: Date = .now) {
        guard !track.isPlaceholder else { return }
        var entry = own[track.id] ?? Entry(count: 0, last: date)
        entry.count += 1
        entry.last = date
        own[track.id] = entry
        save()
    }

    /// 開關 iCloud 同步。打開時把這台的紀錄寫上去、讀回其他 Mac 的；關掉時只用這台的
    func setSyncing(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.syncKey)
        isSyncing = enabled
        if enabled { save() }
        reloadCloud()
    }

    func reloadCloud() {
        guard isSyncing, let cloudFolder else {
            others = [:]
            return
        }
        let mine = Self.deviceFileName
        let files = (try? FileManager.default.contentsOfDirectory(at: cloudFolder, includingPropertiesForKeys: nil)) ?? []
        var merged: [String: Entry] = [:]
        for url in files {
            // 尚未下載到這台的檔案是「.名稱.json.icloud」佔位檔：請系統下載，下次再讀
            if url.lastPathComponent.hasSuffix(".icloud") {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                continue
            }
            guard url.pathExtension == "json", url.lastPathComponent != mine,
                  let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else { continue }
            for (id, entry) in entries {
                if let current = merged[id] {
                    merged[id] = Entry(count: current.count + entry.count, last: max(current.last, entry.last))
                } else {
                    merged[id] = entry
                }
            }
        }
        if merged != others { others = merged }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(own) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        guard isSyncing, let cloudFolder else { return }
        do {
            try FileManager.default.createDirectory(at: cloudFolder, withIntermediateDirectories: true)
            try data.write(to: cloudFolder.appending(path: Self.deviceFileName), options: .atomic)
            syncError = nil
        } catch {
            syncError = error.localizedDescription
        }
    }
}
