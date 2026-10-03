import Foundation
import Observation
import WebKit

/// YouTube Music 帳號：登入狀態與 Premium 檢查（docs/youtube/DESIGN.md）。
/// 只開放 YouTube Premium 帳號使用。
@MainActor @Observable
final class YouTubeAccount {
    enum State: Equatable {
        case signedOut
        case checking
        /// 已確認是 Premium
        case premium(name: String)
        /// 已確認不是 Premium：顯示說明，不放行
        case notPremium(name: String)
        /// 已登入，但 Premium 的判斷方式還沒確定（第一階段，等分析真實帳號的回應）
        case unverified(name: String)
        case failed(message: String)
    }

    private(set) var state: State = .signedOut

    var isActive: Bool {
        if case .premium = state { return true }
        return false
    }

    /// 啟動時：之前登入過（cookie 還在）就重新檢查
    func restore() async {
        guard await InnerTube.sapisid() != nil else { return }
        await check()
    }

    /// 登入視窗完成後呼叫
    func didSignIn() async {
        await check()
    }

    func check() async {
        state = .checking
        do {
            let menu = try await InnerTube.post("account/account_menu")
            let name = Self.accountName(in: menu) ?? "YouTube"
            switch Self.premiumStatus(in: menu) {
            case true?: state = .premium(name: name)
            case false?: state = .notPremium(name: name)
            case nil: state = .unverified(name: name)
            }
        } catch InnerTube.Failure.signedOut {
            state = .signedOut
        } catch {
            state = .failed(message: String(localized: "Couldn't reach YouTube Music. Check your internet connection and try again."))
        }
    }

    /// 登出：清除 Google 與 YouTube 的 cookie 與網站資料
    func signOut() async {
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let google = records.filter { record in
            ["google", "youtube", "gstatic", "ggpht", "googleusercontent"].contains { record.displayName.contains($0) }
        }
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: google)
        state = .signedOut
    }

    // MARK: - 解析帳號選單

    /// 帳號名稱：header.activeAccountHeaderRenderer.accountName.runs[0].text
    private static func accountName(in menu: [String: Any]) -> String? {
        let header = (find("activeAccountHeaderRenderer", in: menu) as? [String: Any])
        let name = header?["accountName"] as? [String: Any]
        return ((name?["runs"] as? [[String: Any]])?.first?["text"] as? String) ?? (name?["simpleText"] as? String)
    }

    /// Premium 判斷。第一階段還不知道標記在哪裡，一律回傳 nil（待確認）；
    /// 用真實帳號登入後，從 /tmp/flione-youtube-account-account_menu.json 找出標記再補上。
    private static func premiumStatus(in menu: [String: Any]) -> Bool? {
        nil
    }

    /// 遞迴找第一個指定 key 的值
    static func find(_ key: String, in value: Any) -> Any? {
        if let dict = value as? [String: Any] {
            if let hit = dict[key] { return hit }
            for child in dict.values { if let hit = find(key, in: child) { return hit } }
        } else if let array = value as? [Any] {
            for child in array { if let hit = find(key, in: child) { return hit } }
        }
        return nil
    }
}
