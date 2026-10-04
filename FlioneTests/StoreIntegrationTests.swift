import XCTest
@testable import Flione

/// 對真實 server 驗證連續操作的順序問題。只用暫存 playlist，喜愛狀態測試後還原。
@MainActor
final class StoreIntegrationTests: XCTestCase {
    private var repository: JellyfinRepository!

    override func setUp() async throws {
        let secrets = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".secrets")
        guard let session = DevelopmentSessionStore(directory: secrets).load() else { throw XCTSkip("沒有 .secrets/") }
        repository = JellyfinRepository(session: session)
    }

    func testRapidPlaylistEditsArriveInOrder() async throws {
        let store = PlaylistStore()
        store.attach(repository: repository)
        for leftover in try await repository.playlists() where leftover.name.hasPrefix("Flione Test") {
            try await repository.deletePlaylist(leftover.id)
        }
        let t = try await IntegrationFixture.album(from: repository).tracks
        let created = try await store.create(name: "Flione Test (order)", tracks: Array(t.prefix(4)))
        let playlist = try XCTUnwrap(created)

        // 連續兩次移除，同時送出：最後的結果必須是第二次的狀態
        async let first = store.save(playlist, name: playlist.name, tracks: [t[0], t[2], t[3]])
        async let second = store.save(playlist, name: playlist.name, tracks: [t[0], t[3]])
        _ = await (first, second)
        await store.add([t[5]], to: playlist)

        let items = try await repository.playlistTracks(playlist.id).map(\.id)
        try await repository.deletePlaylist(playlist.id)
        XCTAssertEqual(items, [t[0].id, t[3].id, t[5].id])
    }

    func testRapidFavoriteTogglesEndInFinalState() async throws {
        let store = FavoritesStore()
        store.attach(repository: repository)
        try await Task.sleep(for: .seconds(1))
        let trackID = try await IntegrationFixture.album(from: repository).tracks[0].id
        let original = store.contains(trackID)

        store.toggle(trackID); store.toggle(trackID); store.toggle(trackID)
        try await Task.sleep(for: .seconds(3))
        let afterThree = try await repository.favoriteIDs().contains(trackID)
        XCTAssertEqual(afterThree, !original)
        XCTAssertEqual(store.contains(trackID), !original)

        // 還原
        store.toggle(trackID)
        try await Task.sleep(for: .seconds(2))
        let restored = try await repository.favoriteIDs().contains(trackID)
        XCTAssertEqual(restored, original)
    }
}
