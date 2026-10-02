import Foundation
import Security

/// 登入資訊存在 macOS Keychain（server URL、user ID、access token）。不存密碼，不用 UserDefaults。
protocol SessionStore: Sendable {
    func load() -> JellyfinSession?
    func save(_ session: JellyfinSession) throws
    func clear()
}

struct KeychainSessionStore: SessionStore {
    private let service = "app.finify.Finify.session"
    private let account = "jellyfin"

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() -> JellyfinSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(JellyfinSession.self, from: data)
    }

    func save(_ session: JellyfinSession) throws {
        let data = try JSONEncoder().encode(session)
        SecItemDelete(baseQuery as CFDictionary)
        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

#if DEBUG || BENCHMARK
/// 開發用：從 `.secrets/` 讀取登入資訊，避免無人值守測試時 Keychain 跳出授權視窗。
/// 啟動參數：`-FinifySecrets <repo>/.secrets`
struct DevelopmentSessionStore: SessionStore {
    let directory: URL

    func load() -> JellyfinSession? {
        var env: [String: String] = [:]
        for name in ["jellyfin.env", "session.env"] {
            guard let text = try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 { env[parts[0]] = parts[1] }
            }
        }
        guard let url = env["JELLYFIN_URL"].flatMap(URL.init(string:)),
              let token = env["JELLYFIN_TOKEN"], let userID = env["JELLYFIN_USER_ID"] else { return nil }
        return JellyfinSession(serverURL: url, serverName: "MediaBox", userID: userID,
                               userName: env["JELLYFIN_USER"] ?? "", accessToken: token)
    }

    func save(_ session: JellyfinSession) throws {}
    func clear() {}
}
#endif
