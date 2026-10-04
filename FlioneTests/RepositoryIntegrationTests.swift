import XCTest
@testable import Flione

/// 對真實 Jellyfin server 的整合測試。沒有 `.secrets/` 時自動略過。
final class RepositoryIntegrationTests: XCTestCase {
    private var repository: JellyfinRepository!

    override func setUpWithError() throws {
        let secrets = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".secrets")
        guard let session = DevelopmentSessionStore(directory: secrets).load() else {
            throw XCTSkip("沒有 .secrets/，略過整合測試")
        }
        repository = JellyfinRepository(session: session)
    }

    func testLoadsAlbumsAndTracks() async throws {
        let albums = try await repository.allAlbums()
        XCTAssertGreaterThan(albums.count, 0)
        let pick = try await IntegrationFixture.album(from: repository)
        // 曲目都屬於這張專輯、有名稱與長度；有音軌編號時依序排列
        XCTAssertTrue(pick.tracks.allSatisfy { $0.albumID == pick.album.id })
        XCTAssertTrue(pick.tracks.allSatisfy { !$0.name.isEmpty && $0.duration > 0 })
        let numbers = pick.tracks.compactMap { track in track.trackNumber.map { (track.discNumber ?? 1) * 1000 + $0 } }
        XCTAssertEqual(numbers, numbers.sorted())
    }

    func testSearchGroupsResults() async throws {
        let pick = try await IntegrationFixture.album(from: repository)
        let results = try await repository.search(pick.album.name)
        XCTAssertTrue(results.albums.contains { $0.id == pick.album.id })
    }

    func testHomeShelves() async throws {
        let repository = repository!
        let a = try await repository.recentlyAdded(limit: 12)
        let p = try await repository.quickPicks(limit: 12)
        XCTAssertEqual(a.count, 12)
        XCTAssertEqual(p.count, 12)
    }

    func testArtistPage() async throws {
        let pick = try await IntegrationFixture.album(from: repository)
        let artistID = try XCTUnwrap(pick.album.artistID)
        let albums = try await repository.albums(byArtist: artistID)
        XCTAssertTrue(albums.contains { $0.id == pick.album.id })
        let popular = try await repository.popularTracks(byArtist: artistID, limit: 5)
        XCTAssertFalse(popular.isEmpty)
    }

    func testReadsExistingPlaylists() async throws {
        let playlists = try await repository.playlists().filter { !$0.name.hasPrefix("Flione Test") }
        for playlist in playlists {
            let tracks = try await repository.playlistTracks(playlist.id)
            guard !tracks.isEmpty else { continue }
            XCTAssertNotNil(tracks.first?.playlistItemID)
            return
        }
        throw XCTSkip("沒有含歌曲的播放清單")
    }

    /// 只在暫時建立的 playlist 上測試寫入，結束時一定刪除，不動使用者原有的 playlist
    func testPlaylistWriteOperationsOnTemporaryPlaylist() async throws {
        let repository = repository!
        // 先清掉之前測試失敗時可能留下的暫存 playlist
        for leftover in try await repository.playlists() where leftover.name.hasPrefix("Flione Test") {
            try await repository.deletePlaylist(leftover.id)
        }
        let t = try await IntegrationFixture.album(from: repository).tracks.map(\.id)

        let id = try await repository.createPlaylist(name: "Flione Test (temporary)", trackIDs: [t[0], t[1]])
        defer { Task { try? await repository.deletePlaylist(id) } }
        // Jellyfin 建立後會在背景再存一次，太快更新會被蓋掉（PlaylistStore 也會等待）
        try await Task.sleep(for: .seconds(1.5))

        // 改名＋加入＋排序一次完成
        try await repository.updatePlaylist(id, name: "Flione Test (renamed)", trackIDs: [t[2], t[0], t[1]])
        var playlist = try await repository.playlist(id: id)
        var items = try await repository.playlistTracks(id).map(\.id)
        XCTAssertEqual(playlist.name, "Flione Test (renamed)")
        XCTAssertEqual(items, [t[2], t[0], t[1]])

        // 移除後名稱不能被還原
        try await repository.updatePlaylist(id, name: "Flione Test (renamed)", trackIDs: [t[2], t[1]])
        playlist = try await repository.playlist(id: id)
        items = try await repository.playlistTracks(id).map(\.id)
        XCTAssertEqual(playlist.name, "Flione Test (renamed)")
        XCTAssertEqual(items, [t[2], t[1]])

        try await repository.deletePlaylist(id)
        let remaining = try await repository.playlists()
        XCTAssertFalse(remaining.contains { $0.id == id })
    }

    func testTrackWithoutLyricsReturnsNil() async throws {
        // 這個 server 目前沒有歌詞檔，Jellyfin 回 404
        let lyrics = try await repository.lyrics(for: "5e272fb46db8b120c59ecb607517fc6d")
        XCTAssertNil(lyrics)
    }

    func testDiscoverBareHostname() async throws {
        let (url, info) = try await JellyfinClient.discover("mediabox")
        XCTAssertEqual(url.absoluteString, "http://mediabox:8096")
        XCTAssertNotNil(info.serverName)
    }
}
