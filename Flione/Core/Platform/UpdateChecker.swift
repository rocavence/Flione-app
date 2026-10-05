import Foundation
import Observation

/// 新版通知（D53）：查 GitHub 上最新的 release，比目前新就在畫面右下角提示，使用者自己下載安裝（不自動更新）。
/// 啟動時最多一天查一次；設定 → 關於可以手動檢查。只連 api.github.com，不送出任何使用資料
@MainActor @Observable
final class UpdateChecker {
    struct Release: Equatable, Sendable {
        let version: String
        let notes: String
        let pageURL: URL
        /// 這台 Mac 對應的 dmg（Apple 晶片或 Intel）；找不到時為 nil，改開 release 頁面
        let downloadURL: URL?
    }

    enum State: Equatable {
        case idle, checking, upToDate, failed
        case available(Release)
    }

    private(set) var state: State = .idle
    /// 右下角的提示：有新版、沒被略過、這次啟動還沒關掉
    var prompt: Release?

    static let latestURL = URL(string: "https://api.github.com/repos/rocavence/Flione-app/releases/latest")!
    private static let lastCheckKey = "FlioneUpdateLastCheck"
    private static let skippedKey = "FlioneUpdateSkippedVersion"

    static var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    /// 啟動時：距離上次檢查超過一天才查
    func checkIfDue() {
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 24 * 60 * 60 else { return }
        Task { await check(manual: false) }
    }

    /// 設定的「檢查更新」：不論多久前查過都查，也不管是否略過過這個版本
    func check(manual: Bool) async {
        state = .checking
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        do {
            var request = URLRequest(url: Self.latestURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let release = Self.parse(data) else {
                state = .failed
                return
            }
            guard Self.isNewer(release.version, than: Self.currentVersion) else {
                state = .upToDate
                return
            }
            state = .available(release)
            let skipped = UserDefaults.standard.string(forKey: Self.skippedKey)
            if manual || skipped != release.version { prompt = release }
        } catch {
            state = .failed
        }
    }

    func skip(_ release: Release) {
        UserDefaults.standard.set(release.version, forKey: Self.skippedKey)
        prompt = nil
    }

    // MARK: - 解析與比較（純函式，測試用）

    static func parse(_ data: Data) -> Release? {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Payload: Decodable { let tag_name: String; let body: String?; let html_url: URL; let assets: [Asset]?; let draft: Bool?; let prerelease: Bool? }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.draft != true, payload.prerelease != true else { return nil }
        let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        #if arch(arm64)
        let flavor = "AppleSilicon"
        #else
        let flavor = "Intel"
        #endif
        let dmg = payload.assets?.first { $0.name.hasSuffix(".dmg") && $0.name.contains(flavor) }?.browser_download_url
        return Release(version: version, notes: summary(payload.body ?? ""), pageURL: payload.html_url, downloadURL: dmg)
    }

    /// 「1.10.0」比「1.9.3」新：逐段比數字
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 更新內容的前幾點（release 說明的條列，去掉 Markdown 記號），提示卡只放得下幾行
    static func summary(_ body: String, limit: Int = 3) -> String {
        body.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") || $0.hasPrefix("* ") }
            .prefix(limit)
            .map { line in
                var text = String(line.dropFirst(2))
                for mark in ["**", "`"] { text = text.replacingOccurrences(of: mark, with: "") }
                return "• " + text
            }
            .joined(separator: "\n")
    }
}
