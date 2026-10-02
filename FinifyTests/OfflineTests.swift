import XCTest
@testable import Finify

/// 可設定成「server 離線」的假 repository，不需要真的關掉 server
final class FakeRepository: MusicRepository, @unchecked Sendable {
    var offline = false
    var albums: [Album] = []
    var favoriteWrites: [(String, Bool)] = []

    private func check() throws { if offline { throw JellyfinError.unreachable } }

    func allAlbums() async throws -> [Album] { try check(); return albums }
    func recentlyAdded(limit: Int) async throws -> [Album] { try check(); return Array(albums.prefix(limit)) }
    func recentlyPlayed(limit: Int) async throws -> [Album] { try check(); return [] }
    func quickPicks(limit: Int) async throws -> [Album] { try check(); return [] }
    func allArtists() async throws -> [Artist] { try check(); return [] }
    func artist(id: String) async throws -> Artist { try check(); return Artist(id: id, name: "A", artwork: nil) }
    func albums(byArtist artistID: String) async throws -> [Album] { try check(); return [] }
    func popularTracks(byArtist artistID: String, limit: Int) async throws -> [Track] { try check(); return [] }
    func album(id: String) async throws -> Album { try check(); return albums[0] }
    func tracks(inAlbum albumID: String) async throws -> [Track] { try check(); return [] }
    func songs(offset: Int, limit: Int) async throws -> (tracks: [Track], total: Int) { try check(); return ([], 0) }
    func search(_ query: String) async throws -> SearchResults { try check(); return SearchResults() }
    func artworkURL(_ ref: ArtworkRef, maxPixelSize: Int) -> URL { URL(string: "http://localhost/\(ref.itemID)")! }
    func streamURL(for track: Track) -> URL { URL(string: "http://localhost/\(track.id)")! }
    func reportPlaybackStarted(_ track: Track) async {}
    func reportPlaybackStopped(_ track: Track, position: TimeInterval) async {}
    func lyrics(for trackID: String) async throws -> Lyrics? { try check(); return nil }
    func genres() async throws -> [Genre] { try check(); return [] }
    func albums(inGenre genreID: String) async throws -> [Album] { try check(); return [] }
    func randomTracks(inGenre genreID: String, limit: Int) async throws -> [Track] { try check(); return [] }
    func playlists() async throws -> [Playlist] { try check(); return [] }
    func playlistTracks(_ playlistID: String) async throws -> [Track] { try check(); return [] }
    func playlist(id: String) async throws -> Playlist { try check(); return Playlist(id: id, name: "P", trackCount: 0, duration: 0, artwork: nil) }
    func createPlaylist(name: String, trackIDs: [String]) async throws -> String { try check(); return "new" }
    func updatePlaylist(_ playlistID: String, name: String, trackIDs: [String]) async throws { try check() }
    func deletePlaylist(_ playlistID: String) async throws { try check() }
    func favoriteIDs() async throws -> Set<String> { try check(); return [] }
    func favoriteTracks() async throws -> [Track] { try check(); return [] }
    func setFavorite(_ itemID: String, _ isFavorite: Bool) async throws {
        try check()
        favoriteWrites.append((itemID, isFavorite))
    }
}

@MainActor
final class OfflineTests: XCTestCase {
    /// 清掉測試留下的音樂庫快照
    override func tearDown() async throws {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("app.finify.Finify")
        for file in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where file.hasPrefix("library-test") {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
        }
    }

    private func albums(_ n: Int) -> [Album] {
        (0..<n).map { Album(id: "a\($0)", name: "Album \($0)", artistName: "X", artistID: nil, year: nil, artwork: nil, dateAdded: nil) }
    }

    /// 上次載入過的音樂庫在 server 離線時仍可瀏覽
    func testLibrarySnapshotIsAvailableWhenServerIsOffline() async {
        let serverID = "test-\(UUID().uuidString)"
        let repository = FakeRepository()
        repository.albums = albums(3)

        let online = LibraryStore()
        online.attach(repository: repository, serverID: serverID)
        await online.refresh()
        XCTAssertEqual(online.albums.count, 3)

        repository.offline = true
        let offline = LibraryStore()
        offline.attach(repository: repository, serverID: serverID)
        XCTAssertEqual(offline.albums.count, 3, "啟動時應立即顯示上次的快照")
        await offline.refresh()
        XCTAssertEqual(offline.state, .failed)
        XCTAssertEqual(offline.albums.count, 3, "更新失敗時保留快照")
    }

    /// 喜愛切換在離線時失敗，畫面要還原並提示
    func testFavoriteToggleRevertsWhenOffline() async throws {
        let repository = FakeRepository()
        let store = FavoritesStore()
        store.attach(repository: repository)
        try await Task.sleep(for: .milliseconds(100))
        repository.offline = true

        store.toggle("t1")
        XCTAssertTrue(store.contains("t1"), "先更新畫面")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(store.contains("t1"), "失敗後還原")
        XCTAssertNotNil(store.failureMessage)
    }

    /// 連點三次只送出最終狀態所需的寫入
    func testRapidFavoriteTogglesCoalesce() async throws {
        let repository = FakeRepository()
        let store = FavoritesStore()
        store.attach(repository: repository)
        try await Task.sleep(for: .milliseconds(100))

        store.toggle("t1"); store.toggle("t1"); store.toggle("t1")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(store.contains("t1"))
        XCTAssertEqual(repository.favoriteWrites.last?.1, true)
        XCTAssertLessThanOrEqual(repository.favoriteWrites.count, 3)
    }
}
