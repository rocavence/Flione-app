import Foundation

/// YouTube Music 的資料來源（第三階段，docs/youtube/DESIGN.md）：
/// 把 InnerTube 的回應轉成 Flione 原本的 Album／Track／Artist／Playlist，讓 Modern、Infinity、Cover Flow 直接使用。
/// 格式依 2026-10-03 的實際回應；YouTube 沒有的功能（曲風、編輯播放清單）回傳空結果或丟出 `unsupported`。
final class YouTubeMusicRepository: MusicRepository, @unchecked Sendable {
    enum Failure: Error { case unsupported, notFound }

    /// 喜歡的歌曲：歌曲列表、最愛、隨機播放共用，載入一次
    private let likedCache = LikedCache()
    private let librarySongsCache = LikedCache()

    // MARK: - 音樂庫

    func allAlbums() async throws -> [Album] {
        try await pages(browseId: "FEmusic_liked_albums", item: "musicTwoRowItemRenderer").compactMap(Parse.album)
    }

    func recentlyAdded(limit: Int) async throws -> [Album] {
        Array(try await allAlbums().prefix(limit))
    }

    /// 播放記錄的歌曲整理成專輯（依最近播放的順序，不重複）
    func recentlyPlayed(limit: Int) async throws -> [Album] {
        let json = try await InnerTube.post("browse", body: ["browseId": "FEmusic_history"])
        var seen = Set<String>()
        var albums: [Album] = []
        for row in Parse.all("musicResponsiveListItemRenderer", in: json) where Parse.isSong(row) {
            guard let track = Parse.track(row), let albumID = track.albumID, seen.insert(albumID).inserted else { continue }
            albums.append(Album(id: albumID, name: track.albumName, artistName: track.artistName, artistID: track.artistID,
                                year: nil, artwork: track.artwork, dateAdded: nil))
            if albums.count >= limit { break }
        }
        return albums
    }

    func quickPicks(limit: Int) async throws -> [Album] {
        Array(try await allAlbums().shuffled().prefix(limit))
    }

    func allArtists() async throws -> [Artist] {
        try await pages(browseId: "FEmusic_library_corpus_artists", item: "musicResponsiveListItemRenderer").compactMap(Parse.artist)
    }

    // MARK: - 藝人

    func artist(id: String) async throws -> Artist {
        let json = try await InnerTube.post("browse", body: ["browseId": id])
        guard let header = Parse.find("musicImmersiveHeaderRenderer", in: json) as? [String: Any]
                ?? Parse.find("musicVisualHeaderRenderer", in: json) as? [String: Any],
              let name = Parse.text(header["title"]) else { throw Failure.notFound }
        return Artist(id: id, name: name, artwork: Parse.artwork(header["thumbnail"]))
    }

    /// 藝人頁「專輯」「單曲與迷你專輯」等區塊中的專輯（不重複）
    func albums(byArtist artistID: String) async throws -> [Album] {
        let json = try await InnerTube.post("browse", body: ["browseId": artistID])
        let header = Parse.find("musicImmersiveHeaderRenderer", in: json) as? [String: Any]
        let artistName = Parse.text(header?["title"]) ?? ""
        var seen = Set<String>()
        return Parse.all("musicTwoRowItemRenderer", in: json).compactMap { item in
            guard var album = Parse.album(item), seen.insert(album.id).inserted else { return nil }
            if album.artistName.isEmpty {
                album = Album(id: album.id, name: album.name, artistName: artistName, artistID: artistID,
                              year: album.year, artwork: album.artwork, dateAdded: nil)
            }
            return album
        }
    }

    func popularTracks(byArtist artistID: String, limit: Int) async throws -> [Track] {
        let json = try await InnerTube.post("browse", body: ["browseId": artistID])
        guard let shelf = Parse.find("musicShelfRenderer", in: json) else { return [] }
        return Array(Parse.all("musicResponsiveListItemRenderer", in: shelf).compactMap { Parse.track($0) }.prefix(limit))
    }

    // MARK: - 專輯

    func album(id: String) async throws -> Album {
        let json = try await InnerTube.post("browse", body: ["browseId": id])
        guard let album = Parse.albumHeader(json, id: id) else { throw Failure.notFound }
        return album
    }

    func tracks(inAlbum albumID: String) async throws -> [Track] {
        let json = try await InnerTube.post("browse", body: ["browseId": albumID])
        let album = Parse.albumHeader(json, id: albumID)
        guard let shelf = Parse.find("musicShelfRenderer", in: json) else { return [] }
        return Parse.all("musicResponsiveListItemRenderer", in: shelf).compactMap { Parse.track($0, album: album) }
    }

    // MARK: - 歌曲、搜尋

    func songs(offset: Int, limit: Int) async throws -> (tracks: [Track], total: Int) {
        let all = try await librarySongs()
        return (Array(all.dropFirst(offset).prefix(limit)), all.count)
    }

    func search(_ query: String) async throws -> SearchResults {
        let json = try await InnerTube.post("search", body: ["query": query])
        var results = SearchResults()
        var seen = Set<String>()
        // 「最佳結果」卡片（搜「pet shop」時的 Pet Shop Boys）不在一般的列表裡：放到同類的第一個
        if let card = Parse.find("musicCardShelfRenderer", in: json) as? [String: Any],
           let titleRun = Parse.runs(card["title"]).first, let name = titleRun["text"] as? String,
           let target = Parse.browse(titleRun) {
            let artwork = Parse.artwork(card["thumbnail"])
            switch target.pageType {
            case "MUSIC_PAGE_TYPE_ARTIST":
                seen.insert(target.id)
                results.artists.append(Artist(id: target.id, name: name, artwork: artwork))
            case "MUSIC_PAGE_TYPE_ALBUM":
                let artistRun = Parse.runs(card["subtitle"]).first { Parse.browse($0)?.pageType == "MUSIC_PAGE_TYPE_ARTIST" }
                seen.insert(target.id)
                results.albums.append(Album(id: target.id, name: name, artistName: artistRun?["text"] as? String ?? "",
                                            artistID: artistRun.flatMap { Parse.browse($0)?.id }, year: Parse.year(in: Parse.runs(card["subtitle"])),
                                            artwork: artwork, dateAdded: nil))
            default:
                break
            }
        }
        for row in Parse.all("musicResponsiveListItemRenderer", in: json) {
            switch Parse.pageType(row) {
            case "MUSIC_PAGE_TYPE_ARTIST":
                if let artist = Parse.artist(row), seen.insert(artist.id).inserted { results.artists.append(artist) }
            case "MUSIC_PAGE_TYPE_ALBUM":
                if let album = Parse.albumRow(row), seen.insert(album.id).inserted { results.albums.append(album) }
            case "MUSIC_PAGE_TYPE_PLAYLIST":
                if let playlist = Parse.playlistRow(row), seen.insert(playlist.id).inserted { results.playlists.append(playlist) }
            default:
                if let track = Parse.track(row), seen.insert(track.id).inserted { results.tracks.append(track) }
            }
        }
        return results
    }

    // MARK: - 封面、播放

    /// 封面參照：可調尺寸的網址（googleusercontent，tag "yt"）依需要的大小補上 `=w…-h…`；
    /// 影片縮圖（i.ytimg.com）與 YouTube 的固定圖（gstatic，tag "ytfixed"）照原網址
    func artworkURL(_ ref: ArtworkRef, maxPixelSize: Int) -> URL {
        let url = ref.tag == "yt" ? "\(ref.itemID)=w\(maxPixelSize)-h\(maxPixelSize)-l90-rj" : ref.itemID
        return URL(string: url) ?? URL(string: InnerTube.origin)!
    }

    /// YouTube Music 不提供可直接播放的網址；播放由網頁播放器負責（PlayerManager 的 web 引擎）
    func streamURL(for track: Track) -> URL {
        URL(string: "\(InnerTube.origin)/watch?v=\(track.id)")!
    }

    /// 播放紀錄由網頁播放器自己回報給 YouTube
    func reportPlaybackStarted(_ track: Track) async {}
    func reportPlaybackStopped(_ track: Track, position: TimeInterval) async {}

    func lyrics(for trackID: String) async throws -> Lyrics? { nil }

    // MARK: - YouTube 沒有的功能

    func genres() async throws -> [Genre] { [] }
    func albums(inGenre genreID: String) async throws -> [Album] { [] }
    func randomTracks(inGenre genreID: String, limit: Int) async throws -> [Track] { [] }
    func instantMix(forTrack trackID: String, limit: Int) async throws -> [Track] { [] }
    func radio(seedID: String, limit: Int) async throws -> [Track] { [] }
    var supportsRadio: Bool { false }

    func randomTracks(limit: Int) async throws -> [Track] {
        Array(try await likedSongs().shuffled().prefix(limit))
    }

    // MARK: - 播放清單

    /// 音樂庫的播放清單，最前面加上「最近播放」；拿掉 Podcast 的「稍後觀看的集數」（VLSE）
    func playlists() async throws -> [Playlist] {
        let library = try await pages(browseId: "FEmusic_liked_playlists", item: "musicTwoRowItemRenderer")
            .compactMap(Parse.playlist).filter { $0.id != "VLSE" }
        let recent = try? await recentSongs()
        let recentList = Playlist(id: Self.recentID, name: String(localized: "Recently Played"), trackCount: recent?.count ?? 0,
                                  duration: recent?.reduce(0) { $0 + $1.duration } ?? 0, artwork: recent?.first?.artwork)
        return [recentList] + library
    }

    func playlistTracks(_ playlistID: String) async throws -> [Track] {
        if playlistID == Self.recentID { return try await recentSongs() }
        return try await pages(browseId: playlistID, item: "musicResponsiveListItemRenderer").compactMap { Parse.track($0) }
    }

    /// 「最近播放」清單的 id（播放記錄）
    static let recentID = "FEmusic_history"

    /// 播放記錄中的歌曲：只取 YouTube Music 的歌，排除影片、Podcast；同一首只留最近一次
    private func recentSongs() async throws -> [Track] {
        let json = try await InnerTube.post("browse", body: ["browseId": Self.recentID])
        var seen = Set<String>()
        return Parse.all("musicResponsiveListItemRenderer", in: json)
            .filter(Parse.isSong)
            .compactMap { Parse.track($0) }
            .filter { seen.insert($0.id).inserted }
    }

    func playlist(id: String) async throws -> Playlist {
        guard let match = try await playlists().first(where: { $0.id == id }) else { throw Failure.notFound }
        return match
    }

    func createPlaylist(name: String, trackIDs: [String]) async throws -> String { throw Failure.unsupported }
    func updatePlaylist(_ playlistID: String, name: String, trackIDs: [String]) async throws { throw Failure.unsupported }
    func deletePlaylist(_ playlistID: String) async throws { throw Failure.unsupported }

    // MARK: - 最愛＝喜歡的歌曲

    func favoriteIDs() async throws -> Set<String> {
        Set(try await likedSongs().map(\.id))
    }

    func favoriteTracks() async throws -> [Track] {
        try await likedSongs()
    }

    /// 把專輯加入 YouTube Music 收藏：與 YouTube Music 的「儲存到音樂庫」相同，是對專輯的播放清單（OLAK5uy_…）按讚
    func saveAlbumToLibrary(_ albumID: String) async throws {
        let json = try await InnerTube.post("browse", body: ["browseId": albumID])
        guard let playlistID = Parse.albumPlaylistID(json) else { throw Failure.notFound }
        _ = try await InnerTube.post("like/like", body: ["target": ["playlistId": playlistID]])
    }

    func setFavorite(_ itemID: String, _ isFavorite: Bool) async throws {
        _ = try await InnerTube.post(isFavorite ? "like/like" : "like/removelike", body: ["target": ["videoId": itemID]])
        await likedCache.clear()
    }

    // MARK: - 共用

    /// 「喜歡的音樂」（按讚的歌）：最愛與愛心用這個。
    /// 不能用音樂庫的「歌曲」（FEmusic_liked_videos）：那是收藏的專輯裡所有的歌，會讓整張專輯都變成最愛
    private func likedSongs() async throws -> [Track] {
        if let cached = await likedCache.tracks { return cached }
        // 已下架的影片沒有標題，留在清單裡會是一列空白
        let tracks = try await pages(browseId: "VLLM", item: "musicResponsiveListItemRenderer").compactMap { Parse.track($0) }
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        await likedCache.set(tracks)
        return tracks
    }

    /// 音樂庫的「歌曲」：收藏的專輯與按讚的歌裡所有的歌（「歌曲」頁）
    private func librarySongs() async throws -> [Track] {
        if let cached = await librarySongsCache.tracks { return cached }
        let tracks = try await pages(browseId: "FEmusic_liked_videos", item: "musicResponsiveListItemRenderer").compactMap { Parse.track($0) }
        await librarySongsCache.set(tracks)
        return tracks
    }

    /// 讀取所有分頁（最多 20 頁）
    private func pages(browseId: String, item: String) async throws -> [[String: Any]] {
        var json = try await InnerTube.post("browse", body: ["browseId": browseId])
        var items = Parse.all(item, in: json)
        for _ in 0..<20 {
            if let token = Parse.continuation(json) {
                json = try await InnerTube.post("browse", continuation: token)
                items += Parse.all(item, in: json["continuationContents"] ?? [:])
            } else if let token = Parse.continuationCommand(json) {
                // 較新的分頁格式（播放清單，例如「喜歡的音樂」）：token 放在 body，下一頁在 onResponseReceivedActions
                json = try await InnerTube.post("browse", body: ["continuation": token])
                items += Parse.all(item, in: json["onResponseReceivedActions"] ?? [:])
            } else {
                break
            }
        }
        return items
    }
}

private actor LikedCache {
    private(set) var tracks: [Track]?
    func set(_ value: [Track]) { tracks = value }
    func clear() { tracks = nil }
}

/// InnerTube 回應的解析工具
enum Parse {
    static func runs(_ value: Any?) -> [[String: Any]] {
        (value as? [String: Any])?["runs"] as? [[String: Any]] ?? []
    }

    static func text(_ value: Any?) -> String? {
        if let simple = (value as? [String: Any])?["simpleText"] as? String { return simple }
        let joined = runs(value).compactMap { $0["text"] as? String }.joined()
        return joined.isEmpty ? nil : joined
    }

    static func browse(_ run: [String: Any]) -> (id: String, pageType: String?)? {
        guard let endpoint = (run["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any],
              let id = endpoint["browseId"] as? String else { return nil }
        let pageType = ((endpoint["browseEndpointContextSupportedConfigs"] as? [String: Any])?["browseEndpointContextMusicConfig"] as? [String: Any])?["pageType"] as? String
        return (id, pageType)
    }

    /// 封面：取最大的縮圖網址，去掉 `=w…` 尺寸後綴當作 ID
    static func artwork(_ renderer: Any?) -> ArtworkRef? {
        guard let thumbnails = find("thumbnails", in: renderer ?? [:]) as? [[String: Any]],
              let url = thumbnails.last?["url"] as? String else { return nil }
        guard let resize = url.range(of: "=w", options: .backwards) ?? url.range(of: "=s", options: .backwards),
              url.contains("googleusercontent.com") || url.contains("ggpht.com") else {
            return ArtworkRef(itemID: url, tag: "ytfixed", blurHash: nil)
        }
        return ArtworkRef(itemID: String(url[..<resize.lowerBound]), tag: "yt", blurHash: nil)
    }

    /// 列（musicResponsiveListItemRenderer）本身連到的頁面類型（藝人、專輯、播放清單）；歌曲沒有
    static func pageType(_ row: [String: Any]) -> String? {
        browse(row)?.pageType
    }

    static func columns(_ row: [String: Any]) -> [[[String: Any]]] {
        (row["flexColumns"] as? [[String: Any]] ?? []).map {
            runs(($0["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"])
        }
    }

    /// 歌曲列：第一欄是歌名，其他欄的連結分別是藝人、專輯，曲長在 fixedColumns 或「3:22」這種文字
    static func track(_ row: [String: Any], album: Album? = nil) -> Track? {
        guard let watch = find("watchEndpoint", in: row) as? [String: Any],
              let videoId = watch["videoId"] as? String else { return nil }
        let cols = columns(row)
        guard let title = cols.first?.compactMap({ $0["text"] as? String }).joined(), !title.isEmpty else { return nil }
        let rest = cols.dropFirst().flatMap { $0 }
        let artists = rest.filter { browse($0)?.pageType == "MUSIC_PAGE_TYPE_ARTIST" }
        let albumRun = rest.first { browse($0)?.pageType == "MUSIC_PAGE_TYPE_ALBUM" }
        let fixed = (row["fixedColumns"] as? [[String: Any]])?.first.flatMap { text(($0["musicResponsiveListItemFixedColumnRenderer"] as? [String: Any])?["text"]) }
        let durationText = fixed ?? rest.compactMap { $0["text"] as? String }.last { $0.range(of: #"^\d+:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil }
        let artistName = artists.compactMap { $0["text"] as? String }.joined(separator: ", ")
        return Track(id: videoId, name: title,
                     albumID: albumRun.flatMap { browse($0)?.id } ?? album?.id,
                     albumName: albumRun?["text"] as? String ?? album?.name ?? "",
                     artistName: artistName.isEmpty ? (album?.artistName ?? "") : artistName,
                     artistID: artists.first.flatMap { browse($0)?.id } ?? album?.artistID,
                     trackNumber: text(row["index"]).flatMap(Int.init), discNumber: nil,
                     duration: durationText.map(seconds) ?? 0, container: nil,
                     artwork: artwork(row["thumbnail"]) ?? album?.artwork)
    }

    /// 專輯卡片（musicTwoRowItemRenderer）：副標題是「專輯 • 藝人 • 年份」
    static func album(_ item: [String: Any]) -> Album? {
        guard let target = browse(item), target.pageType == "MUSIC_PAGE_TYPE_ALBUM",
              let title = text(item["title"]) else { return nil }
        let subtitle = runs(item["subtitle"])
        let artistRun = subtitle.first { browse($0)?.pageType == "MUSIC_PAGE_TYPE_ARTIST" }
        return Album(id: target.id, name: title, artistName: artistRun?["text"] as? String ?? "",
                     artistID: artistRun.flatMap { browse($0)?.id }, year: year(in: subtitle),
                     artwork: artwork(item["thumbnailRenderer"]), dateAdded: nil)
    }

    /// 搜尋結果中的專輯列
    static func albumRow(_ row: [String: Any]) -> Album? {
        guard let target = browse(row), let title = columns(row).first?.compactMap({ $0["text"] as? String }).joined() else { return nil }
        let rest = columns(row).dropFirst().flatMap { $0 }
        let artistRun = rest.first { browse($0)?.pageType == "MUSIC_PAGE_TYPE_ARTIST" }
        return Album(id: target.id, name: title, artistName: artistRun?["text"] as? String ?? "",
                     artistID: artistRun.flatMap { browse($0)?.id }, year: year(in: rest),
                     artwork: artwork(row["thumbnail"]), dateAdded: nil)
    }

    /// 專輯頁的標題區
    static func albumHeader(_ json: [String: Any], id: String) -> Album? {
        guard let header = find("musicResponsiveHeaderRenderer", in: json) as? [String: Any],
              let title = text(header["title"]) else { return nil }
        let artistRun = runs(header["straplineTextOne"]).first
        return Album(id: id, name: title, artistName: artistRun?["text"] as? String ?? "",
                     artistID: artistRun.flatMap { browse($0)?.id }, year: year(in: runs(header["subtitle"])),
                     artwork: artwork(header["thumbnail"]), dateAdded: nil)
    }

    static func artist(_ row: [String: Any]) -> Artist? {
        guard let target = browse(row), target.pageType == "MUSIC_PAGE_TYPE_ARTIST",
              let name = columns(row).first?.compactMap({ $0["text"] as? String }).joined(), !name.isEmpty else { return nil }
        return Artist(id: target.id, name: name, artwork: artwork(row["thumbnail"]))
    }

    static func playlist(_ item: [String: Any]) -> Playlist? {
        guard let target = browse(item), target.pageType == "MUSIC_PAGE_TYPE_PLAYLIST",
              let title = text(item["title"]) else { return nil }
        return Playlist(id: target.id, name: title, trackCount: 0, duration: 0, artwork: artwork(item["thumbnailRenderer"]))
    }

    static func playlistRow(_ row: [String: Any]) -> Playlist? {
        guard let target = browse(row), let title = columns(row).first?.compactMap({ $0["text"] as? String }).joined() else { return nil }
        return Playlist(id: target.id, name: title, trackCount: 0, duration: 0, artwork: artwork(row["thumbnail"]))
    }

    /// 是 YouTube Music 的歌（ATV），不是影片（官方 MV、一般影片）或 Podcast
    static func isSong(_ row: [String: Any]) -> Bool {
        let watch = find("watchEndpoint", in: row) as? [String: Any]
        let config = (watch?["watchEndpointMusicSupportedConfigs"] as? [String: Any])?["watchEndpointMusicConfig"] as? [String: Any]
        return config?["musicVideoType"] as? String == "MUSIC_VIDEO_TYPE_ATV"
    }

    /// 專輯頁裡專輯本身的播放清單 id（OLAK5uy_ 開頭）
    static func albumPlaylistID(_ value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let id = dict["playlistId"] as? String, id.hasPrefix("OLAK5uy_") { return id }
            for child in dict.values { if let id = albumPlaylistID(child) { return id } }
        } else if let array = value as? [Any] {
            for child in array { if let id = albumPlaylistID(child) { return id } }
        }
        return nil
    }

    static func continuation(_ json: [String: Any]) -> String? {
        (find("nextContinuationData", in: json) as? [String: Any])?["continuation"] as? String
    }

    static func continuationCommand(_ json: [String: Any]) -> String? {
        (find("continuationCommand", in: json) as? [String: Any])?["token"] as? String
    }

    /// 年份單獨一段：英文是「2024」，中文、日文是「2024年」，韓文是「2024년」
    static func year(in runs: [[String: Any]]) -> Int? {
        runs.compactMap { $0["text"] as? String }
            .compactMap { $0.wholeMatch(of: /((?:19|20)\d{2})\s*[年년]?/).flatMap { Int($0.1) } }
            .first
    }

    /// 「14:56」「1:02:03」轉成秒
    static func seconds(_ text: String) -> TimeInterval {
        text.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }

    static func find(_ key: String, in value: Any) -> Any? {
        if let dict = value as? [String: Any] {
            if let hit = dict[key] { return hit }
            for child in dict.values { if let hit = find(key, in: child) { return hit } }
        } else if let array = value as? [Any] {
            for child in array { if let hit = find(key, in: child) { return hit } }
        }
        return nil
    }

    static func all(_ key: String, in value: Any) -> [[String: Any]] {
        var found: [[String: Any]] = []
        func walk(_ v: Any) {
            if let dict = v as? [String: Any] {
                if let hit = dict[key] as? [String: Any] { found.append(hit) }
                for child in dict.values where !(child is String) { walk(child) }
            } else if let array = v as? [Any] {
                for child in array { walk(child) }
            }
        }
        walk(value)
        return found
    }
}
