import XCTest
@testable import Finify

final class LRCLibTests: XCTestCase {
    func testParsesTimestampsAndSkipsMetadata() throws {
        let lrc = """
        [ar:Air]
        [ti:Le Voyage]
        [00:12.50] First line
        [00:05.00][01:00.25]Chorus
        [00:20.00]
        """
        let lyrics = try XCTUnwrap(LRCLib.parseLRC(lrc))
        XCTAssertEqual(lyrics.lines.map(\.text), ["Chorus", "First line", "", "Chorus"])
        XCTAssertEqual(lyrics.lines.map(\.start), [5, 12.5, 20, 60.25])
        XCTAssertTrue(lyrics.isSynced)
    }

    func testPlainTextIsNotSynced() {
        XCTAssertNil(LRCLib.parseLRC("no timestamps here"))
        let result = LRCLib.Result(duration: 200, instrumental: false, plainLyrics: "a\nb", syncedLyrics: nil)
        XCTAssertEqual(LRCLib.lyrics(from: result)?.isSynced, false)
    }

    func testPicksClosestDurationAndSkipsInstrumental() {
        let results = [
            LRCLib.Result(duration: 180, instrumental: false, plainLyrics: "far", syncedLyrics: nil),
            LRCLib.Result(duration: 211, instrumental: true, plainLyrics: nil, syncedLyrics: nil),
            LRCLib.Result(duration: 215, instrumental: false, plainLyrics: "close", syncedLyrics: nil),
        ]
        XCTAssertEqual(LRCLib.best(results, duration: 212)?.plainLyrics, "close")
    }
}
