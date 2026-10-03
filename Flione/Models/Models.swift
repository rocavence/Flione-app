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
    /// 曲風（Magic sort 的「By Genre」用）；舊的快取沒有這個欄位時為 nil
    var genres: [String]? = nil
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

/// 歌詞。每行有開始時間時為同步歌詞
struct Lyrics: Sendable, Equatable {
    struct Line: Sendable, Equatable {
        let text: String
        let start: TimeInterval?
    }

    let lines: [Line]

    var isSynced: Bool { !lines.isEmpty && lines.allSatisfy { $0.start != nil } }

    /// 播放到 `time` 時應該亮起的那一行
    func currentLineIndex(at time: TimeInterval) -> Int? {
        guard isSynced else { return nil }
        return lines.lastIndex { ($0.start ?? .infinity) <= time }
    }
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

/// 專輯排序。Library、Album Wall、Album Flow 共用
enum AlbumSort: String, CaseIterable, Sendable {
    case artist = "Artist"
    case title = "Title"
    case recentlyAdded = "Recently Added"
    case year = "Year"

    /// 音樂庫本身已依藝人排序（server 端），artist 直接回傳
    func apply(to albums: [Album]) -> [Album] {
        switch self {
        case .artist: albums
        case .title: albums.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recentlyAdded: albums.sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
        case .year: albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        }
    }
}

/// 拖放專輯時傳遞的內容。用 URL 型別，與佇列內排序（純文字）區分
enum DragPayload {
    static func album(_ id: String) -> URL { URL(string: "finify-album://\(id)")! }

    static func albumID(from url: URL) -> String? {
        url.scheme == "finify-album" ? url.host : nil
    }
}
