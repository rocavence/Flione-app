import XCTest
@testable import Flione

/// YouTube Music 的本機播放次數：計次門檻與存檔
@MainActor
final class LocalPlayCountsTests: XCTestCase {
    private func track(_ id: String, duration: TimeInterval) -> Track {
        Track(id: id, name: id, albumID: nil, albumName: "", artistName: "A", artistID: nil,
              trackNumber: nil, discNumber: nil, duration: duration, container: nil, artwork: nil)
    }

    func testThreshold() {
        XCTAssertFalse(LocalPlayCounts.counts(track("a", duration: 200), position: 29))
        XCTAssertTrue(LocalPlayCounts.counts(track("a", duration: 200), position: 30))
        XCTAssertTrue(LocalPlayCounts.counts(track("b", duration: 40), position: 20))   // 短歌聽一半就算
        XCTAssertFalse(LocalPlayCounts.counts(track("b", duration: 40), position: 19))
    }

    func testRecordAndPersistence() {
        let file = FileManager.default.temporaryDirectory.appending(path: "flione-plays-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let counts = LocalPlayCounts(file: file)
        counts.record(track("v1", duration: 200), at: Date(timeIntervalSince1970: 100))
        counts.record(track("v1", duration: 200), at: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(counts.entry(for: "v1")?.count, 2)
        XCTAssertEqual(counts.entry(for: "v1")?.last, Date(timeIntervalSince1970: 200))
        XCTAssertNil(counts.entry(for: "v2"))
        XCTAssertEqual(LocalPlayCounts(file: file).entry(for: "v1")?.count, 2)
    }
}

/// iCloud 同步：每台 Mac 一個檔案，顯示時加總
@MainActor
final class LocalPlayCountsSyncTests: XCTestCase {
    func testMergesOtherMacs() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "flione-sync-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
            UserDefaults.standard.removeObject(forKey: LocalPlayCounts.syncKey)
        }
        let cloud = root.appending(path: "cloud")
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        // 另一台 Mac 的檔案
        let other: [String: LocalPlayCounts.Entry] = ["v1": .init(count: 3, last: Date(timeIntervalSince1970: 500)),
                                                       "v9": .init(count: 1, last: Date(timeIntervalSince1970: 50))]
        try JSONEncoder().encode(other).write(to: cloud.appending(path: "Other Mac (abcd1234).json"))

        let counts = LocalPlayCounts(file: root.appending(path: "local.json"), cloudFolder: cloud)
        counts.setSyncing(false)
        let song = Track(id: "v1", name: "S", albumID: nil, albumName: "", artistName: "A", artistID: nil,
                         trackNumber: nil, discNumber: nil, duration: 200, container: nil, artwork: nil)
        counts.record(song, at: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(counts.entry(for: "v1")?.count, 1)        // 關閉時只算這台
        XCTAssertNil(counts.entry(for: "v9"))

        counts.setSyncing(true)
        XCTAssertEqual(counts.entry(for: "v1")?.count, 4)        // 1 + 3
        XCTAssertEqual(counts.entry(for: "v1")?.last, Date(timeIntervalSince1970: 500))
        XCTAssertEqual(counts.entry(for: "v9")?.count, 1)
        // 打開時把這台的紀錄寫上去（自己的檔案）
        let files = try FileManager.default.contentsOfDirectory(atPath: cloud.path)
        XCTAssertEqual(files.count, 2)

        // 關掉時刪除這台的檔案，其他 Mac 的留著；這台的紀錄仍在本機
        counts.setSyncing(false)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cloud.path), ["Other Mac (abcd1234).json"])
        XCTAssertEqual(counts.entry(for: "v1")?.count, 1)
    }
}
