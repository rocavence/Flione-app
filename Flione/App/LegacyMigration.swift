import Foundation
import Security

/// 從舊名稱 Finify 搬到 Flione（D52）。bundle id 由 `app.finify.Finify` 改為 `com.rocavence.Flione`，
/// macOS 會把它當成另一個 App：設定、Application Support、快取、WebKit（YouTube 的登入 cookie）與鑰匙圈都在舊名稱底下。
/// 第一次啟動新版時，在任何東西讀取這些資料之前搬過來，使用者不用重新設定或登入。
///
/// - 設定：舊網域的每個鍵複製到新網域，鍵名開頭的 `Finify` 換成 `Flione`；新網域已有的值不覆蓋
/// - 檔案：Application Support、WebKit、HTTPStorages 用複製（舊版還能開）；快取用搬移（可能數百 MB，舊版會自己重新下載）。
///   新位置已有的東西以舊資料取代（搬移前只可能是開發、測試時建立的空資料）
/// - 鑰匙圈：Jellyfin 的登入在 `KeychainSessionStore.load()` 找不到新項目時讀舊的、存成新的（系統可能會問一次是否允許）
/// 只做一次；失敗的項目略過，最壞的情況是那一項要重新設定。
enum LegacyMigration {
    static let oldID = "app.finify.Finify"
    static let newID = "com.rocavence.Flione"
    static let oldKeychainService = "app.finify.Finify.session"
    private static let doneKey = "FlioneMigratedFromFinify"

    static func runIfNeeded() {
        // 測試時不碰使用者的資料
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              Bundle.main.bundleIdentifier == newID else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        migrateDefaults(defaults)
        migrateFiles()
        defaults.set(true, forKey: doneKey)
    }

    static func renamedKey(_ key: String) -> String {
        key.hasPrefix("Finify") ? "Flione" + key.dropFirst("Finify".count) : key
    }

    private static func migrateDefaults(_ defaults: UserDefaults) {
        guard let old = defaults.persistentDomain(forName: oldID) else { return }
        // 只看新網域自己有沒有這個鍵：object(forKey:) 也會讀到系統的全域值（例如 AppleLanguages），會誤以為已經設過
        let current = defaults.persistentDomain(forName: newID) ?? [:]
        for (key, value) in old {
            let key = renamedKey(key)
            if current[key] == nil { defaults.set(value, forKey: key) }
        }
    }

    private static func migrateFiles() {
        let fm = FileManager.default
        let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        func carry(_ folder: String, suffix: String = "", move: Bool = false) {
            let from = library.appending(path: "\(folder)/\(oldID)\(suffix)")
            let to = library.appending(path: "\(folder)/\(newID)\(suffix)")
            guard fm.fileExists(atPath: from.path) else { return }
            // 搬移前新位置若已經有東西，只會是開發或測試時建立的空資料（使用者的新版還沒啟動過）：以舊資料為準
            if fm.fileExists(atPath: to.path) { try? fm.removeItem(at: to) }
            try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            if move { try? fm.moveItem(at: from, to: to) } else { try? fm.copyItem(at: from, to: to) }
        }
        carry("Application Support")
        carry("WebKit")
        carry("HTTPStorages")
        carry("HTTPStorages", suffix: ".binarycookies")
        carry("Caches", move: true)
    }

    /// 舊名稱存在鑰匙圈的 Jellyfin 登入（KeychainSessionStore 找不到新項目時呼叫）
    static func legacySessionData(account: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: oldKeychainService,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
