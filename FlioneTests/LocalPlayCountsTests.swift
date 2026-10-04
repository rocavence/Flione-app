import XCTest
@testable import Flione

/// YouTube Music 的本機播放次數：計次規則與存檔
@MainActor
final class LocalPlayCountsTests: XCTestCase {
    private func track(_ id: String, duration: TimeInterval) -> Track {
        Track(id: id, name: id, albumID: nil, albumName: "", artistName: "A", artistID: nil,
              trackNumber: nil, discNumber: nil, duration: duration, container: nil, artwork: nil)
    }

    func testCountRuleAndPersistence() {
        let file = FileManager.default.temporaryDirectory.appending(path: "flione-plays-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let counts = LocalPlayCounts(file: file)
        let song = track("v1", duration: 200)
        counts.record(song, position: 10)                                // 不到 30 秒，不算
        counts.record(song, position: 45, at: Date(timeIntervalSince1970: 100))
        counts.record(song, position: 199, at: Date(timeIntervalSince1970: 200))
        counts.record(track("v2", duration: 40), position: 21)          // 短歌聽一半就算
        XCTAssertEqual(counts.entry(for: "v1")?.count, 2)
        XCTAssertEqual(counts.entry(for: "v1")?.last, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(counts.entry(for: "v2")?.count, 1)
        XCTAssertNil(counts.entry(for: "v3"))
        // 重新開啟後讀得回來
        XCTAssertEqual(LocalPlayCounts(file: file).entry(for: "v1")?.count, 2)
    }
}
