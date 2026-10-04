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
