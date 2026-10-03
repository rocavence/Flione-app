import Foundation
import Observation
import WebKit

/// YouTube Music 帳號：登入狀態（docs/youtube/DESIGN.md）。不限制 Premium，登入即可使用。
@MainActor @Observable
final class YouTubeAccount {
    enum State: Equatable {
        case signedOut
        case checking
        case connected(name: String)
        case failed(message: String)
    }

    private(set) var state: State = .signedOut

    var isActive: Bool {
        if case .connected = state { return true }
        return false
    }

    /// 啟動時：之前登入過（cookie 還在）就重新連線
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
            state = .connected(name: Self.accountName(in: menu) ?? "YouTube")
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
