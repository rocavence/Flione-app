import Foundation
import Security

/// Jellyfin 的登入資訊（server URL、user ID、access token），不存密碼。
/// 存成檔案（FileSessionStore，D57）；以前存在鑰匙圈（KeychainSessionStore），第一次讀取時搬過來。
protocol SessionStore: Sendable {
    func load() -> JellyfinSession?
    func save(_ session: JellyfinSession) throws
    func clear()
}

/// 存成 Application Support 裡的檔案，只有這個 Mac 帳號能讀（權限 600）。
/// 不用鑰匙圈：公開版是 ad-hoc 簽章，鑰匙圈以每一版的 cdhash 認 App，每次更新都要使用者輸入一次密碼（D56、D57）
struct FileSessionStore: SessionStore {
    var file: URL = FileSessionStore.defaultFile
    /// 搬移用：以前存在鑰匙圈的登入；測試時換掉
    var legacy: any SessionStore = KeychainSessionStore()
    var movedKey = "FlioneSessionMovedToFile"

    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.rocavence.Flione/jellyfin-session.json")
    }

    func load() -> JellyfinSession? {
        if let data = try? Data(contentsOf: file) {
            return try? JSONDecoder().decode(JellyfinSession.self, from: data)
        }
        // 只搬一次：讀鑰匙圈可能跳出密碼視窗，使用者拒絕的話不要每次啟動都問（重新登入即可）
        guard !UserDefaults.standard.bool(forKey: movedKey) else { return nil }
        UserDefaults.standard.set(true, forKey: movedKey)
        guard let session = legacy.load() else { return nil }
        do {
            try save(session)
            legacy.clear()
        } catch {}
        return session
    }

    func save(_ session: JellyfinSession) throws {
        let data = try JSONEncoder().encode(session)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    func clear() {
        try? FileManager.default.removeItem(at: file)
        // 還沒搬過的話，鑰匙圈裡可能還有舊的；登出時一起清掉
        if !UserDefaults.standard.bool(forKey: movedKey) { legacy.clear() }
    }
}

/// 以前的存法（0.9.84 以前），只在搬到 FileSessionStore 時讀取
struct KeychainSessionStore: SessionStore {
    private let service = "com.rocavence.Flione.session"
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
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            return try? JSONDecoder().decode(JellyfinSession.self, from: data)
        }
        // 改名前（Finify）存的登入：讀出來存成新的（D52）。只在沒有新項目時讀一次
        guard !Self.checkedLegacy, let data = LegacyMigration.legacySessionData(account: account),
              let session = try? JSONDecoder().decode(JellyfinSession.self, from: data) else {
            Self.checkedLegacy = true
            return nil
        }
        Self.checkedLegacy = true
        try? save(session)
        return session
    }

    /// 舊鑰匙圈項目只查一次（每次查都可能讓系統跳出授權視窗）
    nonisolated(unsafe) private static var checkedLegacy = false

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

#if DEBUG || BENCHMARK || DEV_LOGIN
/// 開發與測試版用：從 `.secrets/` 讀取登入資訊，避免無人值守測試時 Keychain 跳出授權視窗。
/// 啟動參數：`-FlioneSecrets <repo>/.secrets`
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

#if DEBUG || BENCHMARK || DEV_LOGIN
extension DevelopmentSessionStore {
    /// 這份原始碼所在 repo 的 `.secrets/`。只記路徑，不把登入資訊打包進 app；在其他電腦上這個路徑不存在，會照常顯示登入畫面
    static var repoSecrets: URL? {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".secrets")
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("session.env").path) ? dir : nil
    }
}
#endif
