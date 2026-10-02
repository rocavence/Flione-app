import XCTest
@testable import Finify

final class PlayQueueTests: XCTestCase {
    private func tracks(_ n: Int) -> [Track] {
        (0..<n).map {
            Track(id: "t\($0)", name: "Track \($0)", albumID: "a", albumName: "A", artistName: "X", artistID: nil,
                  trackNumber: $0 + 1, discNumber: 1, duration: 100, container: "m4a", artwork: nil)
        }
    }

    func testAdvanceStopsAtEndWhenRepeatOff() {
        var q = PlayQueue(tracks: tracks(3), startAt: 2)
        XCTAssertNil(q.advance(automatic: true))
        XCTAssertEqual(q.index, 2)
    }

    func testRepeatAllWrapsAround() {
        var q = PlayQueue(tracks: tracks(3), startAt: 2)
        q.repeatMode = .all
        XCTAssertEqual(q.advance(automatic: true)?.id, "t0")
    }

    func testRepeatOneReplaysOnAutomaticButSkipsOnManualNext() {
        var q = PlayQueue(tracks: tracks(3), startAt: 1)
        q.repeatMode = .one
        XCTAssertEqual(q.nextIndex(automatic: true), 1)
        XCTAssertEqual(q.advance(automatic: false)?.id, "t2")
    }

    func testShuffleKeepsCurrentTrackFirstAndRestoresOrder() {
        var q = PlayQueue(tracks: tracks(20), startAt: 5)
        q.setShuffle(true)
        XCTAssertEqual(q.current?.id, "t5")
        XCTAssertEqual(q.index, 0)
        XCTAssertEqual(Set(q.tracks.map(\.id)), Set(tracks(20).map(\.id)))
        q.advance(automatic: false)
        let playing = q.current
        q.setShuffle(false)
        XCTAssertEqual(q.current, playing)
        XCTAssertEqual(q.tracks.map(\.id), tracks(20).map(\.id))
    }

    func testInsertNextPlaysImmediatelyAfterCurrent() {
        var q = PlayQueue(tracks: tracks(3), startAt: 0)
        let extra = Track(id: "x", name: "X", albumID: nil, albumName: "", artistName: "", artistID: nil,
                          trackNumber: nil, discNumber: nil, duration: 1, container: nil, artwork: nil)
        q.insertNext([extra])
        XCTAssertEqual(q.upcoming.first?.id, "x")
        XCTAssertEqual(q.tracks.count, 4)
    }

    func testRemoveAndClearUpcoming() {
        var q = PlayQueue(tracks: tracks(5), startAt: 1)
        q.removeUpcoming(at: 0)
        XCTAssertEqual(q.upcoming.map(\.id), ["t3", "t4"])
        q.clearUpcoming()
        XCTAssertTrue(q.upcoming.isEmpty)
        XCTAssertEqual(q.current?.id, "t1")
    }

    func testGoBackAtStartStaysUnlessRepeatAll() {
        var q = PlayQueue(tracks: tracks(3), startAt: 0)
        XCTAssertEqual(q.goBack()?.id, "t0")
        q.repeatMode = .all
        XCTAssertEqual(q.goBack()?.id, "t2")
    }
}
