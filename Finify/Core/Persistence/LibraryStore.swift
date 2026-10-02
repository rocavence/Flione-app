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
    private(set) var albums: [Album] = []
    private(set) var artists: [Artist] = []
    private(set) var state: LoadState = .idle

    @ObservationIgnored private var repository: (any MusicRepository)?
    @ObservationIgnored private var snapshotURL: URL?

    private struct Snapshot: Codable {
        let albums: [Album]
        let artists: [Artist]
    }

    func attach(repository: any MusicRepository, serverID: String) {
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
        albums = []
        artists = []
        state = .idle
        repository = nil
    }

    func refresh() async {
        guard let repository, state != .loading else { return }
        state = .loading
        do {
            async let albums = repository.allAlbums()
            async let artists = repository.allArtists()
            let (a, r) = try await (albums, artists)
            self.albums = a
            self.artists = r
            state = .loaded
            if let url = snapshotURL, let data = try? JSONEncoder().encode(Snapshot(albums: a, artists: r)) {
                try? data.write(to: url, options: .atomic)
            }
        } catch {
            state = .failed
        }
    }

    func refreshIfNeeded() async {
        if state == .idle { await refresh() }
    }
}
