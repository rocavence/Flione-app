import Foundation
import Observation

/// 使用者的 playlist 清單與編輯動作。所有寫入都以完整狀態送出（D13）。
@MainActor @Observable
final class PlaylistStore {
    private(set) var playlists: [Playlist] = []
    /// 編輯失敗時給使用者看的訊息
    var failureMessage: String?
    @ObservationIgnored private var repository: (any MusicRepository)?
    /// Jellyfin 建立 playlist 後會在背景再存一次；建立後太快寫入會被蓋掉（實測），所以等一下
    @ObservationIgnored private var createdAt: [String: Date] = [:]
    private static let settleDelay: TimeInterval = 1.5

    private func waitUntilSettled(_ playlistID: String) async {
        guard let created = createdAt[playlistID] else { return }
        let remaining = Self.settleDelay - Date().timeIntervalSince(created)
        if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
    }

    func attach(repository: any MusicRepository) {
        self.repository = repository
        playlists = []
        Task { await refresh() }
    }

    func reset() {
        playlists = []
        repository = nil
    }

    func refresh() async {
        guard let repository, let list = try? await repository.playlists() else { return }
        playlists = list
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
            failureMessage = "Couldn't create the playlist. Check your connection to the music server."
            return nil
        }
    }

    /// 加到 playlist 結尾
    func add(_ tracks: [Track], to playlist: Playlist) async {
        guard let repository else { return }
        await waitUntilSettled(playlist.id)
        do {
            let current = try await repository.playlistTracks(playlist.id)
            let name = (try? await repository.playlist(id: playlist.id).name) ?? playlist.name
            try await repository.updatePlaylist(playlist.id, name: name, trackIDs: current.map(\.id) + tracks.map(\.id))
            await refresh()
        } catch {
            failureMessage = "Couldn't add to “\(playlist.name)”. Check your connection to the music server."
        }
    }

    /// 以完整狀態儲存（改名、移除、排序）
    func save(_ playlist: Playlist, name: String, tracks: [Track]) async -> Bool {
        guard let repository else { return false }
        await waitUntilSettled(playlist.id)
        do {
            try await repository.updatePlaylist(playlist.id, name: name, trackIDs: tracks.map(\.id))
            if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
                playlists[index] = Playlist(id: playlist.id, name: name, trackCount: tracks.count,
                                            duration: tracks.reduce(0) { $0 + $1.duration }, artwork: playlist.artwork)
            }
            return true
        } catch {
            failureMessage = "Couldn't save “\(name)”. Check your connection to the music server."
            return false
        }
    }

    func delete(_ playlist: Playlist) async -> Bool {
        guard let repository else { return false }
        do {
            try await repository.deletePlaylist(playlist.id)
            playlists.removeAll { $0.id == playlist.id }
            return true
        } catch {
            failureMessage = "Couldn't delete “\(playlist.name)”. Check your connection to the music server."
            return false
        }
    }
}
