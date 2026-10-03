import XCTest
@testable import Flione

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

final class PlayQueueDuplicateTests: XCTestCase {
    private func album() -> [Track] {
        (0..<3).map {
            Track(id: "t\($0)", name: "T\($0)", albumID: "a", albumName: "A", artistName: "X", artistID: nil,
                  trackNumber: $0 + 1, discNumber: 1, duration: 100, container: "m4a", artwork: nil)
        }
    }

    func testSameAlbumTwiceKeepsPositionWhenUnshuffling() {
        var q = PlayQueue(tracks: album())
        q.append(album())
        q.jump(to: 4)   // 第二份的 t1
        q.setShuffle(true)
        q.setShuffle(false)
        XCTAssertEqual(q.index, 4, "關閉 shuffle 後應回到第二份，而不是第一份的同一首")
    }

    func testRemovingUpcomingDuplicateKeepsEarlierCopy() {
        var q = PlayQueue(tracks: album())
        q.append(album())
        q.jump(to: 2)
        q.removeUpcoming(at: 1)  // 第二份的 t1
        XCTAssertEqual(q.tracks.map(\.id), ["t0", "t1", "t2", "t0", "t2"])
    }

    func testMoveDownOnLastRowDoesNotCrash() {
        var q = PlayQueue(tracks: album())
        q.moveUpcoming(from: [1], to: 3)  // 超出範圍的目的地
        XCTAssertEqual(q.upcoming.map(\.id), ["t1", "t2"])
    }
}

final class LyricsTests: XCTestCase {
    func testDecodesSyncedLyricsAndFindsCurrentLine() throws {
        let json = #"{"Metadata":{},"Lyrics":[{"Text":"Hello","Start":0},{"Text":"World","Start":50000000},{"Text":"Again","Start":120000000}]}"#
        let lyrics = try JellyfinClient.decoder.decode(LyricsDTO.self, from: Data(json.utf8)).toLyrics()
        XCTAssertTrue(lyrics.isSynced)
        XCTAssertEqual(lyrics.lines[1].start, 5)
        XCTAssertEqual(lyrics.currentLineIndex(at: 0), 0)
        XCTAssertEqual(lyrics.currentLineIndex(at: 6.2), 1)
        XCTAssertEqual(lyrics.currentLineIndex(at: 200), 2)
    }

    func testPlainLyricsHaveNoCurrentLine() throws {
        let json = #"{"Lyrics":[{"Text":"Line one"},{"Text":"Line two"}]}"#
        let lyrics = try JellyfinClient.decoder.decode(LyricsDTO.self, from: Data(json.utf8)).toLyrics()
        XCTAssertFalse(lyrics.isSynced)
        XCTAssertNil(lyrics.currentLineIndex(at: 10))
    }
}

// MARK: - Smart Shuffle

extension PlayQueueTests {
    private func mix(_ ids: [String]) -> [Track] {
        ids.map { Track(id: $0, name: $0, albumID: nil, albumName: "", artistName: "", artistID: nil, trackNumber: nil, discNumber: nil,
                        duration: 1, container: nil, artwork: nil) }
    }

    func testSmartShuffleInsertsSuggestionEveryNAndSkipsDuplicates() {
        var q = PlayQueue(tracks: tracks(7), startAt: 0)
        q.setShuffle(true)
        let existing = q.tracks[3].id
        q.blendSuggestions(mix(["s1", existing, "s2", "s3", "s4", "s5"]), every: 3)
        let pattern = q.upcomingEntries.map(\.suggested)
        // 6 首原本的歌：每 3 首後插一首，最後再接 3 首讓音樂不停
        XCTAssertEqual(pattern, [false, false, false, true, false, false, false, true, true, true, true])
        XCTAssertEqual(q.upcomingEntries.filter(\.suggested).map(\.track.id), ["s1", "s2", "s3", "s4", "s5"])
    }

    func testTurningShuffleOffDropsSuggestionsButKeepsSuggestedCurrentTrack() {
        var q = PlayQueue(tracks: tracks(4), startAt: 0)
        q.setShuffle(true)
        q.blendSuggestions(mix(["s1", "s2"]), every: 1)
        let suggestedPosition = q.entries.firstIndex { $0.suggested }!
        q.jump(to: suggestedPosition)
        q.setShuffle(false)
        XCTAssertEqual(q.current?.id, "s1")
        XCTAssertEqual(q.tracks.filter { $0.id.hasPrefix("s") }.map(\.id), ["s1"])
        XCTAssertEqual(q.tracks.count, 5)
    }

    func testRemoveUpcomingSuggestions() {
        var q = PlayQueue(tracks: tracks(3), startAt: 0)
        q.setShuffle(true)
        q.blendSuggestions(mix(["s1", "s2"]), every: 1)
        q.removeUpcomingSuggestions()
        XCTAssertFalse(q.upcomingEntries.contains { $0.suggested })
        XCTAssertEqual(q.upcoming.count, 2)
    }
}
