import Foundation

/// YouTube Music 的專輯與歌曲（第二階段：驗證播放用，docs/youtube/DESIGN.md）
struct YTAlbum: Identifiable, Hashable, Sendable {
    let id: String          // browseId（MPREb_…）
    let title: String
    let artist: String
    let artwork: URL?
    /// 播放整張專輯：第一首的 videoId 與專輯的 playlistId（OLAK5uy_…）
    let videoId: String?
    let playlistId: String?
}

struct YTSong: Identifiable, Hashable, Sendable {
    let id: String          // videoId
    let title: String
    let artist: String
    let album: String?
    let artwork: URL?
    /// 從清單播放時帶上 playlistId，網頁播放器會接著播後面的歌
    let playlistId: String?
}

/// 讀取音樂庫（InnerTube browse）。格式依 2026-10-03 的實際回應：
/// 歌曲在 musicShelfRenderer.contents[].musicResponsiveListItemRenderer，專輯在 gridRenderer.items[].musicTwoRowItemRenderer
enum YouTubeLibrary {
    @MainActor
    static func likedAlbums() async throws -> [YTAlbum] {
        let json = try await InnerTube.post("browse", body: ["browseId": "FEmusic_liked_albums"])
        return all("musicTwoRowItemRenderer", in: json).compactMap(album)
    }

    @MainActor
    static func likedSongs() async throws -> [YTSong] {
        let json = try await InnerTube.post("browse", body: ["browseId": "FEmusic_liked_videos"])
        return all("musicResponsiveListItemRenderer", in: json).compactMap(song)
    }

    private static func album(_ item: [String: Any]) -> YTAlbum? {
        guard let browseId = (item["navigationEndpoint"] as? [String: Any]).flatMap({ value($0, "browseEndpoint", "browseId") }) as? String,
              let title = text(item["title"]) else { return nil }
        let subtitle = runs(item["subtitle"])
        // 副標題：「專輯 • 藝人」或「單曲 • 藝人 • 年份」，取第一個有連結的（藝人）
        let artist = subtitle.first { $0["navigationEndpoint"] != nil }?["text"] as? String ?? subtitle.last?["text"] as? String ?? ""
        let watch = YouTubeAccount.find("watchEndpoint", in: item["thumbnailOverlay"] ?? [:]) as? [String: Any]
        return YTAlbum(id: browseId, title: title, artist: artist,
                       artwork: artworkURL(item["thumbnailRenderer"], size: 544),
                       videoId: watch?["videoId"] as? String, playlistId: watch?["playlistId"] as? String)
    }

    private static func song(_ item: [String: Any]) -> YTSong? {
        let columns = (item["flexColumns"] as? [[String: Any]] ?? []).map { ($0["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"] }
        // 第一筆「隨機播放所有曲目」沒有 videoId，自然被略過
        guard let watch = YouTubeAccount.find("watchEndpoint", in: item) as? [String: Any],
              let videoId = watch["videoId"] as? String,
              let title = columns.first.flatMap({ text($0) }) else { return nil }
        return YTSong(id: videoId, title: title,
                      artist: columns.count > 1 ? text(columns[1]) ?? "" : "",
                      album: columns.count > 2 ? text(columns[2]) : nil,
                      artwork: artworkURL(item["thumbnail"], size: 226),
                      playlistId: watch["playlistId"] as? String)
    }

    // MARK: - 解析工具

    private static func runs(_ value: Any?) -> [[String: Any]] {
        (value as? [String: Any])?["runs"] as? [[String: Any]] ?? []
    }

    private static func text(_ value: Any?) -> String? {
        let joined = runs(value).compactMap { $0["text"] as? String }.joined()
        return joined.isEmpty ? nil : joined
    }

    private static func value(_ dict: [String: Any], _ keys: String...) -> Any? {
        var current: Any? = dict
        for key in keys { current = (current as? [String: Any])?[key] }
        return current
    }

    /// 縮圖網址最後的 =w226-h226-… 換成需要的尺寸
    private static func artworkURL(_ renderer: Any?, size: Int) -> URL? {
        guard let thumbnails = YouTubeAccount.find("thumbnails", in: renderer ?? [:]) as? [[String: Any]],
              let url = thumbnails.last?["url"] as? String else { return nil }
        let resized = url.replacingOccurrences(of: #"=w\d+-h\d+"#, with: "=w\(size)-h\(size)", options: .regularExpression)
        return URL(string: resized)
    }

    private static func all(_ key: String, in value: Any) -> [[String: Any]] {
        var found: [[String: Any]] = []
        func walk(_ v: Any) {
            if let dict = v as? [String: Any] {
                if let hit = dict[key] as? [String: Any] { found.append(hit) }
                for child in dict.values { walk(child) }
            } else if let array = v as? [Any] {
                for child in array { walk(child) }
            }
        }
        walk(value)
        return found
    }
}
