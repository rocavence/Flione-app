import Foundation

/// 封面圖的參照。實際 URL 由 repository 依尺寸產生。
struct ArtworkRef: Hashable, Sendable, Codable {
    let itemID: String
    let tag: String
    let blurHash: String?
}

struct Artist: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let artwork: ArtworkRef?
}

struct Album: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let artistName: String
    let artistID: String?
    let year: Int?
    let artwork: ArtworkRef?
    let dateAdded: Date?
}

struct Track: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let albumID: String?
    let albumName: String
    let artistName: String
    let artistID: String?
    let trackNumber: Int?
    let discNumber: Int?
    let duration: TimeInterval
    /// 原始檔容器（mp3、m4a…），串流時用來組 URL
    let container: String?
    let artwork: ArtworkRef?
    /// 在 playlist 中的項目 id（同一首歌可在 playlist 出現多次）；不在 playlist 時為 nil
    var playlistItemID: String? = nil
}

struct Genre: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let artwork: ArtworkRef?
}

struct Playlist: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let trackCount: Int
    let duration: TimeInterval
    let artwork: ArtworkRef?
}

struct SearchResults: Sendable {
    var artists: [Artist] = []
    var albums: [Album] = []
    var tracks: [Track] = []
    var playlists: [Playlist] = []

    var isEmpty: Bool { artists.isEmpty && albums.isEmpty && tracks.isEmpty && playlists.isEmpty }
}

enum RepeatMode: Sendable, CaseIterable {
    case off, all, one
}

extension TimeInterval {
    /// 3:07、1:02:45
    var formattedDuration: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
