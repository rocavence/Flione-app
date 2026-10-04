import XCTest
@testable import Flione

/// 藝人頁面的專輯排序：沒有年份的排最後，同年份維持原本順序
final class ArtistAlbumSortTests: XCTestCase {
    private func album(_ name: String, _ year: Int?, added: Double = 0) -> Album {
        Album(id: name, name: name, artistName: "A", artistID: nil, year: year, artwork: nil, dateAdded: Date(timeIntervalSince1970: added))
    }

    func testSorts() {
        let albums = [album("b", 2010, added: 3), album("a", nil, added: 1), album("c", 2020, added: 2), album("d", 2010, added: 4)]
        XCTAssertEqual(ArtistAlbumSort.newest.apply(to: albums).map(\.name), ["c", "b", "d", "a"])
        XCTAssertEqual(ArtistAlbumSort.oldest.apply(to: albums).map(\.name), ["b", "d", "c", "a"])
        XCTAssertEqual(ArtistAlbumSort.title.apply(to: albums).map(\.name), ["a", "b", "c", "d"])
        XCTAssertEqual(ArtistAlbumSort.recentlyAdded.apply(to: albums).map(\.name), ["d", "b", "c", "a"])
    }
}

/// YouTube Music 依介面語言回傳不同的年份寫法
final class YouTubeYearTests: XCTestCase {
    func testYearFormats() {
        XCTAssertEqual(Parse.year(in: [["text": "2024"]]), 2024)
        XCTAssertEqual(Parse.year(in: [["text": "2024年"]]), 2024)
        XCTAssertEqual(Parse.year(in: [["text": "專輯"], ["text": " • "], ["text": "1999 年"]]), 1999)
        XCTAssertNil(Parse.year(in: [["text": "The 1975 Live"]]))
    }
}
