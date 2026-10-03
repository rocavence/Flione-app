import Foundation
import Observation

/// 使用者的 playlist 清單與編輯動作。所有寫入都以完整狀態送出（D13）。
/// 同一個 playlist 的寫入依序執行，避免較早送出的請求比較晚完成而蓋掉新的編輯。
@MainActor @Observable
final class PlaylistStore {
    private(set) var playlists: [Playlist] = []
    /// 每個 playlist 被其他地方（例如右鍵選單）修改時遞增，開著的 playlist 頁據此重新載入
    private(set) var revisions: [String: Int] = [:]
    /// 編輯失敗時給使用者看的訊息
    var failureMessage: String?
    @ObservationIgnored private var repository: (any MusicRepository)?
    /// Jellyfin 建立 playlist 後會在背景再存一次；建立後太快寫入會被蓋掉（實測），所以等一下
    @ObservationIgnored private var createdAt: [String: Date] = [:]
    @ObservationIgnored private var lastWrite: [String: Task<Void, Never>] = [:]
    /// 本機剛改過的名稱。Jellyfin 的清單查詢在改名後會延遲更新，重新整理時以本機為準
    @ObservationIgnored private var localNames: [String: (name: String, at: Date)] = [:]
    private static let settleDelay: TimeInterval = 1.5

    func attach(repository: any MusicRepository) {
        self.repository = repository
        playlists = []
        Task { await refresh() }
    }

    func reset() {
        playlists = []
        repository = nil
    }

    func revision(of playlistID: String) -> Int { revisions[playlistID, default: 0] }

    func refresh() async {
        guard let repository, let list = try? await repository.playlists() else { return }
        playlists = list.map { playlist in
            guard let local = localNames[playlist.id], Date().timeIntervalSince(local.at) < 30 else { return playlist }
            return Playlist(id: playlist.id, name: local.name, trackCount: playlist.trackCount, duration: playlist.duration, artwork: playlist.artwork)
        }
    }

    /// 依序執行同一個 playlist 的寫入
    private func enqueue(_ playlistID: String, _ work: @escaping @MainActor () async -> Void) async {
        let previous = lastWrite[playlistID]
        let task = Task { @MainActor [weak self] in
            await previous?.value
            await self?.waitUntilSettled(playlistID)
            await work()
        }
        lastWrite[playlistID] = task
        await task.value
    }

    private func waitUntilSettled(_ playlistID: String) async {
        guard let created = createdAt[playlistID] else { return }
        let remaining = Self.settleDelay - Date().timeIntervalSince(created)
        if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
    }

    /// 建立 playlist 並回傳
    func create(name: String, tracks: [Track] = []) async -> Playlist? {
        guard let repository else { return nil }
        do {
            let id = try await repository.createPlaylist(name: name, trackIDs: tracks.map(\.id))
            createdAt[id] = Date()
            let playlist = Playlist(id: id, name: name, trackCount: tracks.count, duration: tracks.reduce(0) { $0 + $1.duration }, artwork: nil)
            playlists.append(playlist)
            playlists.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return playlist
        } catch {
            failureMessage = String(localized: "Couldn't create the playlist. Check your connection to the music server.")
            return nil
        }
    }

    /// 加到 playlist 結尾（在佇列中讀取最新內容再寫回，連續加入不會遺失）
    func add(_ tracks: [Track], to playlist: Playlist) async {
        guard let repository else { return }
        await enqueue(playlist.id) { [self] in
            do {
                let current = try await repository.playlistTracks(playlist.id)
                var name = playlist.name
                if let local = localNames[playlist.id]?.name {
                    name = local
                } else if let remote = try? await repository.playlist(id: playlist.id).name {
                    name = remote
                }
                try await repository.updatePlaylist(playlist.id, name: name, trackIDs: current.map(\.id) + tracks.map(\.id))
                revisions[playlist.id, default: 0] += 1
                updateSummary(playlist.id, name: name, tracks: current + tracks)
            } catch {
                failureMessage = String(localized: "Couldn't add to “\(playlist.name)”. Check your connection to the music server.")
            }
        }
    }

    /// 以完整狀態儲存（改名、移除、排序）
    @discardableResult
    func save(_ playlist: Playlist, name: String, tracks: [Track]) async -> Bool {
        guard let repository else { return false }
        localNames[playlist.id] = (name, Date())
        var succeeded = false
        await enqueue(playlist.id) { [self] in
            do {
                try await repository.updatePlaylist(playlist.id, name: name, trackIDs: tracks.map(\.id))
                updateSummary(playlist.id, name: name, tracks: tracks)
                succeeded = true
            } catch {
                failureMessage = String(localized: "Couldn't save “\(name)”. Check your connection to the music server.")
            }
        }
        return succeeded
    }

    func delete(_ playlist: Playlist) async -> Bool {
        guard let repository else { return false }
        var succeeded = false
        await enqueue(playlist.id) { [self] in
            do {
                try await repository.deletePlaylist(playlist.id)
                playlists.removeAll { $0.id == playlist.id }
                succeeded = true
            } catch {
                failureMessage = String(localized: "Couldn't delete “\(playlist.name)”. Check your connection to the music server.")
            }
        }
        return succeeded
    }

    private func updateSummary(_ id: String, name: String, tracks: [Track]) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        let old = playlists[index]
        playlists[index] = Playlist(id: id, name: name, trackCount: tracks.count,
                                    duration: tracks.reduce(0) { $0 + $1.duration }, artwork: old.artwork)
    }
}
