import Foundation
import Observation

/// 喜愛的歌曲、專輯、藝人（與 Jellyfin 同步）。切換時先更新畫面，失敗再還原。
@MainActor @Observable
final class FavoritesStore {
    private(set) var ids: Set<String> = []
    /// 切換失敗時給使用者看的訊息
    var failureMessage: String?
    @ObservationIgnored private var repository: (any MusicRepository)?

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

    func toggle(_ id: String) {
        guard let repository else { return }
        let newValue = !ids.contains(id)
        if newValue { ids.insert(id) } else { ids.remove(id) }
        Task {
            do {
                try await repository.setFavorite(id, newValue)
            } catch {
                if newValue { ids.remove(id) } else { ids.insert(id) }
                failureMessage = "Couldn't update your favorites. Check your connection to the music server."
            }
        }
    }
}
