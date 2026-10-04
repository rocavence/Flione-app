import Foundation

/// View / ViewModel 取得音樂資料的唯一入口。
protocol MusicRepository: Sendable {
    func allAlbums() async throws -> [Album]
    func recentlyAdded(limit: Int) async throws -> [Album]
    func recentlyPlayed(limit: Int) async throws -> [Album]
    func quickPicks(limit: Int) async throws -> [Album]
    func allArtists() async throws -> [Artist]
    /// 追蹤中的藝人（YouTube Music 的訂閱）；沒有這個概念的來源為 nil
    func followedArtists() async throws -> [Artist]?
    func artist(id: String) async throws -> Artist
    func albums(byArtist artistID: String) async throws -> [Album]
    func popularTracks(byArtist artistID: String, limit: Int) async throws -> [Track]
    func album(id: String) async throws -> Album
    func tracks(inAlbum albumID: String) async throws -> [Track]
    func songs(offset: Int, limit: Int) async throws -> (tracks: [Track], total: Int)
    func search(_ query: String) async throws -> SearchResults

    func artworkURL(_ ref: ArtworkRef, maxPixelSize: Int) -> URL
    func streamURL(for track: Track) -> URL

    func reportPlaybackStarted(_ track: Track) async
    func reportPlaybackStopped(_ track: Track, position: TimeInterval) async

    /// 沒有歌詞時回傳 nil
    func lyrics(for trackID: String) async throws -> Lyrics?

    func genres() async throws -> [Genre]
    func albums(inGenre genreID: String) async throws -> [Album]
    /// 隨機挑選該類型的曲目
    func randomTracks(inGenre genreID: String, limit: Int) async throws -> [Track]
    /// 從整個音樂庫隨機挑選曲目
    func randomTracks(limit: Int) async throws -> [Track]
    /// Jellyfin 的 Instant Mix：與這首歌相似的曲目（Smart Shuffle 用）
    func instantMix(forTrack trackID: String, limit: Int) async throws -> [Track]
    /// 電台：以專輯、藝人、曲風或歌曲為起點產生連續播放（D47）。不支援時為空陣列
    func radio(seedID: String, limit: Int) async throws -> [Track]
    var supportsRadio: Bool { get }
    /// 心情電台的起始歌曲（D50）
    func moodTracks(_ mood: Mood, limit: Int) async throws -> [Track]

    func playlists() async throws -> [Playlist]
    func playlistTracks(_ playlistID: String) async throws -> [Track]
    func playlist(id: String) async throws -> Playlist
    /// 建立並回傳新 playlist 的 id
    func createPlaylist(name: String, trackIDs: [String]) async throws -> String
    /// 以完整狀態更新 playlist（名稱＋全部曲目，依順序）。改名、加入、移除、排序都走這裡，見 D13
    func updatePlaylist(_ playlistID: String, name: String, trackIDs: [String]) async throws
    func deletePlaylist(_ playlistID: String) async throws

    func favoriteIDs() async throws -> Set<String>
    func favoriteTracks() async throws -> [Track]
    func setFavorite(_ itemID: String, _ isFavorite: Bool) async throws
}

extension MusicRepository {
    func followedArtists() async throws -> [Artist]? { nil }

    /// 預設（Jellyfin）：曲風名稱符合心情關鍵字的，隨機抽最多 6 個曲風，各取一些歌後打散
    func moodTracks(_ mood: Mood, limit: Int) async throws -> [Track] {
        let matched = try await genres().filter { genre in
            let name = genre.name.lowercased()
            return mood.genreKeywords.contains { name.contains($0) }
        }
        let picked = Array(matched.shuffled().prefix(6))
        guard !picked.isEmpty else { return [] }
        let each = max(5, limit / picked.count + 1)
        var tracks: [Track] = []
        for genre in picked {
            tracks += (try? await randomTracks(inGenre: genre.id, limit: each)) ?? []
        }
        var seen = Set<String>()
        return Array(tracks.shuffled().filter { seen.insert($0.id).inserted }.prefix(limit))
    }
}

final class JellyfinRepository: MusicRepository {
    private let client: JellyfinClient
    private let session: JellyfinSession

    init(session: JellyfinSession, urlSession: URLSession = .shared) {
        self.session = session
        self.client = JellyfinClient(serverURL: session.serverURL, accessToken: session.accessToken, urlSession: urlSession)
    }

    private var userPath: String { "/Users/\(session.userID)/Items" }

    private func items(_ query: [String: String]) async throws -> ItemsResponse {
        var base = ["Recursive": "true", "EnableTotalRecordCount": "true"]
        base.merge(query) { $1 }
        return try await client.get(userPath, query: base.map { URLQueryItem(name: $0.key, value: $0.value) })
    }

    private static let albumFields = "DateCreated,ProductionYear,Genres"
    private static let trackFields = "ProductionYear"

    func allAlbums() async throws -> [Album] {
        try await items([
            "IncludeItemTypes": "MusicAlbum",
            "SortBy": "AlbumArtist,SortName",
            "Fields": Self.albumFields,
            "EnableTotalRecordCount": "false",
        ]).items.map { $0.toAlbum() }
    }

    func recentlyAdded(limit: Int) async throws -> [Album] {
        try await items([
            "IncludeItemTypes": "MusicAlbum",
            "SortBy": "DateCreated",
            "SortOrder": "Descending",
            "Limit": "\(limit)",
            "Fields": Self.albumFields,
        ]).items.map { $0.toAlbum() }
    }

    /// Jellyfin 只記錄曲目的播放時間；取最近播放的曲目，再依序收斂成不重複的專輯
    func recentlyPlayed(limit: Int) async throws -> [Album] {
        let played = try await items([
            "IncludeItemTypes": "Audio",
            "SortBy": "DatePlayed",
            "SortOrder": "Descending",
            "Filters": "IsPlayed",
            "Limit": "\(limit * 6)",
        ]).items
        var seen = Set<String>()
        let albumIDs = played.compactMap(\.albumID).filter { seen.insert($0).inserted }.prefix(limit)
        guard !albumIDs.isEmpty else { return [] }
        let albums = try await items([
            "Ids": albumIDs.joined(separator: ","),
            "Fields": Self.albumFields,
        ]).items.map { $0.toAlbum() }
        let byID = Dictionary(albums.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return albumIDs.compactMap { byID[$0] }
    }

    func quickPicks(limit: Int) async throws -> [Album] {
        try await items([
            "IncludeItemTypes": "MusicAlbum",
            "SortBy": "Random",
            "Limit": "\(limit)",
            "Fields": Self.albumFields,
        ]).items.map { $0.toAlbum() }
    }

    func allArtists() async throws -> [Artist] {
        let response: ItemsResponse = try await client.get("/Artists/AlbumArtists", query: [
            URLQueryItem(name: "UserId", value: session.userID),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "EnableTotalRecordCount", value: "false"),
        ])
        return response.items.map { $0.toArtist() }
    }

    func artist(id: String) async throws -> Artist {
        let dto: BaseItemDTO = try await client.get("\(userPath)/\(id)")
        return dto.toArtist()
    }

    func albums(byArtist artistID: String) async throws -> [Album] {
        try await items([
            "IncludeItemTypes": "MusicAlbum",
            "AlbumArtistIds": artistID,
            "SortBy": "ProductionYear,SortName",
            "SortOrder": "Descending",
            "Fields": Self.albumFields,
        ]).items.map { $0.toAlbum() }
    }

    func instantMix(forTrack trackID: String, limit: Int) async throws -> [Track] {
        let response: ItemsResponse = try await client.get("/Items/\(trackID)/InstantMix", query: [
            URLQueryItem(name: "UserId", value: session.userID),
            URLQueryItem(name: "Limit", value: "\(limit)"),
            URLQueryItem(name: "Fields", value: Self.trackFields),
        ])
        return response.items.map { $0.toTrack() }.filter { $0.id != trackID }
    }

    /// Instant Mix 接受任何項目當起點（專輯、藝人、曲風、歌曲）
    func radio(seedID: String, limit: Int) async throws -> [Track] {
        let response: ItemsResponse = try await client.get("/Items/\(seedID)/InstantMix", query: [
            URLQueryItem(name: "UserId", value: session.userID),
            URLQueryItem(name: "Limit", value: "\(limit)"),
            URLQueryItem(name: "Fields", value: Self.trackFields),
        ])
        return response.items.map { $0.toTrack() }
    }

    var supportsRadio: Bool { true }

    func popularTracks(byArtist artistID: String, limit: Int) async throws -> [Track] {
        try await items([
            "IncludeItemTypes": "Audio",
            "ArtistIds": artistID,
            "SortBy": "PlayCount,SortName",
            "SortOrder": "Descending",
            "Limit": "\(limit)",
        ]).items.map { $0.toTrack() }
    }

    func album(id: String) async throws -> Album {
        let dto: BaseItemDTO = try await client.get("\(userPath)/\(id)")
        return dto.toAlbum()
    }

    func tracks(inAlbum albumID: String) async throws -> [Track] {
        try await items([
            "ParentId": albumID,
            "IncludeItemTypes": "Audio",
            "SortBy": "ParentIndexNumber,IndexNumber,SortName",
        ]).items.map { $0.toTrack() }
    }

    func songs(offset: Int, limit: Int) async throws -> (tracks: [Track], total: Int) {
        let response = try await items([
            "IncludeItemTypes": "Audio",
            "SortBy": "SortName",
            "StartIndex": "\(offset)",
            "Limit": "\(limit)",
        ])
        return (response.items.map { $0.toTrack() }, response.totalRecordCount ?? 0)
    }

    func search(_ query: String) async throws -> SearchResults {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return SearchResults() }
        async let artists: ItemsResponse = client.get("/Artists/AlbumArtists", query: [
            URLQueryItem(name: "UserId", value: session.userID),
            URLQueryItem(name: "SearchTerm", value: term),
            URLQueryItem(name: "Limit", value: "6"),
        ])
        async let albums = items(["IncludeItemTypes": "MusicAlbum", "SearchTerm": term, "Limit": "8", "Fields": Self.albumFields])
        async let tracks = items(["IncludeItemTypes": "Audio", "SearchTerm": term, "Limit": "12"])
        async let playlists = items(["IncludeItemTypes": "Playlist", "SearchTerm": term, "Limit": "4", "Fields": "ChildCount"])
        var results = try await SearchResults(
            artists: artists.items.map { $0.toArtist() },
            albums: albums.items.map { $0.toAlbum() },
            tracks: tracks.items.map { $0.toTrack() },
            playlists: (try? await playlists.items.map { $0.toPlaylist() }) ?? []
        )
        // Jellyfin 的專輯搜尋只比對專輯名稱。搜尋藝人名時，補上最相符藝人的專輯
        if let topArtist = results.artists.first, results.albums.count < 8 {
            let known = Set(results.albums.map(\.id))
            let byArtist = ((try? await self.albums(byArtist: topArtist.id)) ?? []).filter { !known.contains($0.id) }
            results.albums += byArtist.prefix(8 - results.albums.count)
        }
        if let topArtist = results.artists.first, results.tracks.count < 5 {
            let known = Set(results.tracks.map(\.id))
            let popular = ((try? await self.popularTracks(byArtist: topArtist.id, limit: 8)) ?? []).filter { !known.contains($0.id) }
            results.tracks += popular.prefix(8 - results.tracks.count)
        }
        return results
    }

    func artworkURL(_ ref: ArtworkRef, maxPixelSize: Int) -> URL {
        client.url("/Items/\(ref.itemID)/Images/Primary", query: [
            URLQueryItem(name: "tag", value: ref.tag),
            URLQueryItem(name: "maxWidth", value: "\(maxPixelSize)"),
            URLQueryItem(name: "maxHeight", value: "\(maxPixelSize)"),
            URLQueryItem(name: "quality", value: "90"),
        ])
    }

    /// 原始檔直接串流，不轉檔。AVPlayer 無法帶 header，token 放 query。見 S2。
    func streamURL(for track: Track) -> URL {
        let ext = track.container.map { ".\($0)" } ?? ""
        return client.url("/Audio/\(track.id)/stream\(ext)", query: [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "ApiKey", value: session.accessToken),
        ])
    }

    // MARK: - Lyrics

    func lyrics(for trackID: String) async throws -> Lyrics? {
        do {
            let dto: LyricsDTO = try await client.get("/Audio/\(trackID)/Lyrics")
            let lyrics = dto.toLyrics()
            return lyrics.lines.contains { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty } ? lyrics : nil
        } catch JellyfinError.unexpectedResponse(404) {
            return nil
        }
    }

    // MARK: - Genres

    func genres() async throws -> [Genre] {
        let response: ItemsResponse = try await client.get("/MusicGenres", query: [
            URLQueryItem(name: "UserId", value: session.userID),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "EnableTotalRecordCount", value: "false"),
        ])
        return response.items.map { $0.toGenre() }
    }

    func albums(inGenre genreID: String) async throws -> [Album] {
        try await items([
            "IncludeItemTypes": "MusicAlbum",
            "GenreIds": genreID,
            "SortBy": "AlbumArtist,SortName",
            "Fields": Self.albumFields,
        ]).items.map { $0.toAlbum() }
    }

    func randomTracks(inGenre genreID: String, limit: Int) async throws -> [Track] {
        try await items([
            "IncludeItemTypes": "Audio",
            "GenreIds": genreID,
            "SortBy": "Random",
            "Limit": "\(limit)",
        ]).items.map { $0.toTrack() }
    }

    func randomTracks(limit: Int) async throws -> [Track] {
        try await items(["IncludeItemTypes": "Audio", "SortBy": "Random", "Limit": "\(limit)"]).items.map { $0.toTrack() }
    }

    // MARK: - Playlists

    func playlists() async throws -> [Playlist] {
        try await items([
            "IncludeItemTypes": "Playlist",
            "SortBy": "SortName",
            "Fields": "ChildCount",
            "EnableTotalRecordCount": "false",
        ]).items.map { $0.toPlaylist() }
    }

    /// 單一 playlist（改名後列表查詢會延遲更新，單筆查詢是即時的）
    func playlist(id: String) async throws -> Playlist {
        let dto: BaseItemDTO = try await client.get("\(userPath)/\(id)", query: [URLQueryItem(name: "Fields", value: "ChildCount")])
        return dto.toPlaylist()
    }

    func playlistTracks(_ playlistID: String) async throws -> [Track] {
        let response: ItemsResponse = try await client.get("/Playlists/\(playlistID)/Items", query: [
            URLQueryItem(name: "UserId", value: session.userID),
        ])
        return response.items.map { $0.toTrack() }
    }

    func createPlaylist(name: String, trackIDs: [String]) async throws -> String {
        struct Created: Decodable { let Id: String }
        let created: Created = try await client.sendJSON("POST", "/Playlists", json: [
            "Name": name, "Ids": trackIDs, "UserId": session.userID, "MediaType": "Audio",
        ])
        return created.Id
    }

    /// Jellyfin 12.1 實測：先改名再用 Items API 加歌，名稱會被還原成舊的。
    /// 一律送出完整的名稱與曲目清單，避免各操作互相覆蓋
    func updatePlaylist(_ playlistID: String, name: String, trackIDs: [String]) async throws {
        try await client.post("/Playlists/\(playlistID)", json: ["Name": name, "Ids": trackIDs])
    }

    func deletePlaylist(_ playlistID: String) async throws {
        try await client.send("DELETE", "/Items/\(playlistID)")
    }

    func favoriteIDs() async throws -> Set<String> {
        let response = try await items([
            "Filters": "IsFavorite",
            "IncludeItemTypes": "Audio,MusicAlbum,MusicArtist",
            "EnableImages": "false",
            "EnableTotalRecordCount": "false",
        ])
        return Set(response.items.map(\.id))
    }

    func favoriteTracks() async throws -> [Track] {
        try await items([
            "Filters": "IsFavorite",
            "IncludeItemTypes": "Audio",
            "SortBy": "AlbumArtist,Album,ParentIndexNumber,IndexNumber",
        ]).items.map { $0.toTrack() }
    }

    func setFavorite(_ itemID: String, _ isFavorite: Bool) async throws {
        try await client.send(isFavorite ? "POST" : "DELETE", "/Users/\(session.userID)/FavoriteItems/\(itemID)")
    }

    /// 回報播放狀態，讓 Jellyfin 記錄「最近播放」。失敗不影響播放，所以不拋錯。
    func reportPlaybackStarted(_ track: Track) async {
        try? await client.post("/Sessions/Playing", json: [
            "ItemId": track.id, "PositionTicks": 0, "PlayMethod": "DirectStream", "CanSeek": true,
        ])
    }

    func reportPlaybackStopped(_ track: Track, position: TimeInterval) async {
        try? await client.post("/Sessions/Playing/Stopped", json: [
            "ItemId": track.id, "PositionTicks": Int64(position * 10_000_000),
        ])
    }
}
