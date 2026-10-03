import Foundation
import Observation

/// 喜愛的歌曲、專輯、藝人（與 Jellyfin 同步）。切換時先更新畫面，失敗再還原。
@MainActor @Observable
final class FavoritesStore {
    private(set) var ids: Set<String> = []
    /// 切換失敗時給使用者看的訊息
    var failureMessage: String?
    @ObservationIgnored private var repository: (any MusicRepository)?
    /// 每個項目最後送到 server 的狀態，以及進行中的寫入。連點時只送最終狀態
    @ObservationIgnored private var serverState: [String: Bool] = [:]
    @ObservationIgnored private var writing: Set<String> = []
    /// 每次寫入成功後遞增，Favorites 頁據此重新載入
    private(set) var revision = 0

    func attach(repository: any MusicRepository) {
        self.repository = repository
        ids = []
        Task { if let ids = try? await repository.favoriteIDs() { self.ids = ids } }
    }

    func reset() {
        ids = []
        repository = nil
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    /// 把畫面上的狀態寫到 server；寫入期間使用者又切換時，完成後再送一次
    private func sync(_ id: String, repository: any MusicRepository) async {
        defer { writing.remove(id) }
        while serverState[id] != ids.contains(id) {
            let target = ids.contains(id)
            do {
                try await repository.setFavorite(id, target)
                serverState[id] = target
                revision += 1
            } catch {
                // 還原成 server 上的狀態
                if serverState[id] == true { ids.insert(id) } else { ids.remove(id) }
                failureMessage = String(localized: "Couldn't update your favorites. Check your connection to the music server.")
                return
            }
        }
    }

    func toggle(_ id: String) {
        guard let repository else { return }
        if serverState[id] == nil { serverState[id] = ids.contains(id) }
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        guard !writing.contains(id) else { return }
        writing.insert(id)
        Task { await sync(id, repository: repository) }
    }
}
