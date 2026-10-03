import XCTest
@testable import Finify

final class MagicSortTests: XCTestCase {
    private func album(_ id: String, year: Int? = nil, genre: String? = nil) -> Album {
        Album(id: id, name: id, artistName: "A", artistID: nil, year: year, artwork: nil, dateAdded: nil, genres: genre.map { [$0] })
    }

    func testTimeTravelGoesOldestFirstAndPutsUnknownYearsLast() {
        let albums = [album("a", year: 2001), album("b"), album("c", year: 1972), album("d", year: 2001)]
        XCTAssertEqual(MagicSort.timeTravel.apply(to: albums).map(\.id), ["c", "a", "d", "b"])
    }

    func testGenreGroupsAndKeepsOriginalOrderWithinGroup() {
        let albums = [album("a", genre: "Jazz"), album("b", genre: "Electronic"), album("c"), album("d", genre: "Jazz")]
        XCTAssertEqual(MagicSort.genre.apply(to: albums).map(\.id), ["b", "a", "d", "c"])
    }

    func testShuffleKeepsEveryAlbum() {
        let albums = (0..<50).map { album("\($0)") }
        XCTAssertEqual(Set(MagicSort.shuffle.apply(to: albums).map(\.id)), Set(albums.map(\.id)))
    }
}
