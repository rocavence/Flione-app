import Foundation
import Observation

enum LoadState: Equatable {
    case idle, loading, loaded
    /// 載入失敗；若有快取，畫面仍可使用快取資料
    case failed
}

/// 整個音樂庫的專輯與藝人清單。先顯示上次的磁碟快照，再向 server 更新。
/// Album Wall、Library、Album Flow 共用這份資料。
@MainActor @Observable
final class LibraryStore {
    private(set) var albums: [Album] = [] {
        didSet { rebuildArtistArtwork() }
    }
    private(set) var artists: [Artist] = []
    /// 藝人沒有照片時，用他的專輯封面代替
    @ObservationIgnored private var albumArtworkByArtist: [String: ArtworkRef] = [:]

    func artwork(for artist: Artist) -> ArtworkRef? {
        artist.artwork ?? albumArtworkByArtist[artist.id]
    }

    private func rebuildArtistArtwork() {
        var map: [String: ArtworkRef] = [:]
        for album in albums {
            guard let id = album.artistID, let artwork = album.artwork, map[id] == nil else { continue }
            map[id] = artwork
        }
        albumArtworkByArtist = map
    }
    private(set) var state: LoadState = .idle

    @ObservationIgnored private var repository: (any MusicRepository)?
    /// 每次 attach / reset 遞增；refresh 完成時若已換帳號就丟棄結果
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var snapshotURL: URL?

    private struct Snapshot: Codable {
        let albums: [Album]
        let artists: [Artist]
    }

    func attach(repository: any MusicRepository, serverID: String) {
        generation += 1
        state = .idle
        self.repository = repository
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.finify.Finify", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let name = String(serverID.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.prefix(80))
        snapshotURL = support.appendingPathComponent("library-\(name).json")
        if let url = snapshotURL, let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            albums = snapshot.albums
            artists = snapshot.artists
        }
    }

    func reset() {
        generation += 1
        albums = []
        artists = []
        state = .idle
        repository = nil
    }

    func refresh() async {
        guard let repository, state != .loading else { return }
        let started = generation
        let url = snapshotURL
        state = .loading
        do {
            async let albums = repository.allAlbums()
            async let artists = repository.allArtists()
            let (a, r) = try await (albums, artists)
            guard started == generation else { return }
            self.albums = a
            self.artists = r
            state = .loaded
            if let url, let data = try? JSONEncoder().encode(Snapshot(albums: a, artists: r)) {
                try? data.write(to: url, options: .atomic)
            }
        } catch {
            guard started == generation else { return }
            state = .failed
        }
    }

    func refreshIfNeeded() async {
        if state == .idle { await refresh() }
    }
}
