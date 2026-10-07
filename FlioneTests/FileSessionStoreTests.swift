import CryptoKit
import XCTest
@testable import Flione

/// Jellyfin 登入改存檔案（D57）：從鑰匙圈搬過來、只搬一次、權限 600、加密、登出時刪除
final class FileSessionStoreTests: XCTestCase {
    /// 假的鑰匙圈：記錄被讀了幾次、是否被清掉
    final class FakeLegacy: SessionStore, @unchecked Sendable {
        var session: JellyfinSession?
        var loads = 0
        func load() -> JellyfinSession? { loads += 1; return session }
        func save(_ session: JellyfinSession) throws { self.session = session }
        func clear() { session = nil }
    }

    private var directory: URL!
    private var key: String!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appending(path: "FileSessionStoreTests-\(UUID().uuidString)")
        key = "FlioneTestSessionMoved-\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func session(_ token: String) -> JellyfinSession {
        JellyfinSession(serverURL: URL(string: "http://mediabox:8096")!, serverName: "MediaBox", userID: "u1", userName: "roca", accessToken: token)
    }

    private func store(_ legacy: FakeLegacy) -> FileSessionStore {
        FileSessionStore(file: directory.appending(path: "jellyfin-session.json"), legacy: legacy, movedKey: key)
    }

    func testMovesKeychainLoginToFileOnce() throws {
        let legacy = FakeLegacy()
        legacy.session = session("old-token")
        let store = store(legacy)

        XCTAssertEqual(store.load()?.accessToken, "old-token")
        XCTAssertNil(legacy.session, "搬完要清掉鑰匙圈裡的")
        // 之後都讀檔案，不再碰鑰匙圈
        XCTAssertEqual(store.load()?.accessToken, "old-token")
        XCTAssertEqual(legacy.loads, 1)

        let attributes = try FileManager.default.attributesOfItem(atPath: store.file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testChecksKeychainOnlyOnceWhenEmpty() {
        let legacy = FakeLegacy()
        let store = store(legacy)
        XCTAssertNil(store.load())
        XCTAssertNil(store.load())
        // 鑰匙圈沒有（或使用者拒絕）：之後不再問
        XCTAssertEqual(legacy.loads, 1)
    }

    func testFileIsEncryptedAndBoundToThisMac() throws {
        let store = store(FakeLegacy())
        try store.save(session("secret-token-123"))
        let raw = try Data(contentsOf: store.file)
        XCTAssertNil(raw.range(of: Data("secret-token-123".utf8)), "檔案裡不能有明文的 token")
        XCTAssertNil(raw.range(of: Data("mediabox".utf8)))

        // 別台 Mac（另一把金鑰）解不開：當作沒登入
        var other = store
        other.key = SymmetricKey(size: .bits256)
        XCTAssertNil(other.load())

        // 被改過：當作沒登入
        var tampered = raw
        tampered[tampered.count - 1] ^= 0xFF
        try tampered.write(to: store.file)
        XCTAssertNil(store.load())
    }

    func testDeviceKeyIsStable() {
        // 每次啟動推導出同一把金鑰，否則重開 App 就讀不到登入
        XCTAssertFalse(FileSessionStore.platformUUID.isEmpty, "讀不到硬體 UUID")
        let first = FileSessionStore.deriveDeviceKey().withUnsafeBytes { Data($0) }
        let second = FileSessionStore.deriveDeviceKey().withUnsafeBytes { Data($0) }
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 32)
    }

    func testSaveAndSignOut() throws {
        let store = store(FakeLegacy())
        try store.save(session("new-token"))
        XCTAssertEqual(store.load()?.accessToken, "new-token")
        let leftovers = (try FileManager.default.contentsOfDirectory(atPath: directory.path)).filter { $0.hasPrefix(".") }
        XCTAssertTrue(leftovers.isEmpty, "暫存檔要換上，不能留下")
        store.clear()
        XCTAssertNil(store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.file.path))
    }

    func testSignOutAlsoClearsLeftoverKeychainCopy() throws {
        // 搬過了，但鑰匙圈裡的沒刪成功：登出時要一起清掉
        let legacy = FakeLegacy()
        let store = store(legacy)
        _ = store.load()
        legacy.session = session("leftover")
        try store.save(session("current"))
        store.clear()
        XCTAssertNil(legacy.session)
    }
}
