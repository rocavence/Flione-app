import XCTest
@testable import Flione

/// 整合測試用的資料：從使用者的音樂庫自動挑一張專輯，不寫死特定專輯（音樂庫內容會變）
enum IntegrationFixture {
    struct Pick {
        let album: Album
        let tracks: [Track]
    }

    nonisolated(unsafe) private static var cached: Pick?

    /// 至少 6 首歌、有藝人 id 的第一張專輯（依名稱排序，每次挑到同一張）
    static func album(from repository: JellyfinRepository) async throws -> Pick {
        if let cached { return cached }
        let albums = try await repository.allAlbums()
            .filter { $0.artistID != nil && !$0.artistName.isEmpty }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for album in albums.prefix(60) {
            let tracks = try await repository.tracks(inAlbum: album.id)
            if tracks.count >= 6 {
                let pick = Pick(album: album, tracks: tracks)
                cached = pick
                return pick
            }
        }
        throw XCTSkip("音樂庫裡找不到至少 6 首歌的專輯")
    }
}
