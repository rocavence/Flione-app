import Foundation

// Jellyfin API 回應格式（只解碼 Finify 用到的欄位）

struct ItemsResponse: Decodable, Sendable {
    let items: [BaseItemDTO]
    let totalRecordCount: Int?

    enum CodingKeys: String, CodingKey { case items = "Items", totalRecordCount = "TotalRecordCount" }
}

struct NameIDPair: Decodable, Sendable {
    let name: String?
    let id: String

    enum CodingKeys: String, CodingKey { case name = "Name", id = "Id" }
}

struct UserDataDTO: Decodable, Sendable {
    let isFavorite: Bool?
    let playCount: Int?
    let lastPlayedDate: Date?

    enum CodingKeys: String, CodingKey { case isFavorite = "IsFavorite", playCount = "PlayCount", lastPlayedDate = "LastPlayedDate" }
}

struct BaseItemDTO: Decodable, Sendable {
    let id: String
    let name: String?
    let type: String?
    let album: String?
    let albumID: String?
    let albumArtist: String?
    let albumArtists: [NameIDPair]?
    let artistItems: [NameIDPair]?
    let albumPrimaryImageTag: String?
    let productionYear: Int?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let runTimeTicks: Int64?
    let container: String?
    let imageTags: [String: String]?
    let imageBlurHashes: [String: [String: String]]?
    let dateCreated: Date?
    let userData: UserDataDTO?
    let playlistItemID: String?
    let childCount: Int?

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", type = "Type", album = "Album", albumID = "AlbumId"
        case albumArtist = "AlbumArtist", albumArtists = "AlbumArtists", artistItems = "ArtistItems"
        case albumPrimaryImageTag = "AlbumPrimaryImageTag", productionYear = "ProductionYear"
        case indexNumber = "IndexNumber", parentIndexNumber = "ParentIndexNumber"
        case runTimeTicks = "RunTimeTicks", container = "Container", imageTags = "ImageTags"
        case imageBlurHashes = "ImageBlurHashes", dateCreated = "DateCreated", userData = "UserData"
        case playlistItemID = "PlaylistItemId", childCount = "ChildCount"
    }

    /// 本身的 Primary 圖
    var primaryArtwork: ArtworkRef? {
        guard let tag = imageTags?["Primary"] else { return nil }
        return ArtworkRef(itemID: id, tag: tag, blurHash: imageBlurHashes?["Primary"]?[tag])
    }

    /// 曲目沒有自己的圖時用專輯的圖
    var albumArtwork: ArtworkRef? {
        if let albumID, let tag = albumPrimaryImageTag {
            return ArtworkRef(itemID: albumID, tag: tag, blurHash: imageBlurHashes?["Primary"]?[tag])
        }
        return primaryArtwork
    }

    func toArtist() -> Artist {
        Artist(id: id, name: name ?? "Unknown Artist", artwork: primaryArtwork)
    }

    func toAlbum() -> Album {
        let artist = albumArtists?.first
        return Album(
            id: id,
            name: name ?? "Untitled",
            artistName: albumArtist ?? artist?.name ?? "Unknown Artist",
            artistID: artist?.id,
            year: productionYear,
            artwork: primaryArtwork,
            dateAdded: dateCreated
        )
    }

    func toTrack() -> Track {
        let artist = artistItems?.first ?? albumArtists?.first
        return Track(
            id: id,
            name: name ?? "Untitled",
            albumID: albumID,
            albumName: album ?? "",
            artistName: artistItems?.compactMap(\.name).joined(separator: ", ").nilIfEmpty ?? albumArtist ?? "Unknown Artist",
            artistID: artist?.id,
            trackNumber: indexNumber,
            discNumber: parentIndexNumber,
            duration: Double(runTimeTicks ?? 0) / 10_000_000,
            container: container?.split(separator: ",").first.map(String.init),
            artwork: albumArtwork,
            playlistItemID: playlistItemID
        )
    }

    func toGenre() -> Genre {
        Genre(id: id, name: name ?? "Unknown", artwork: primaryArtwork)
    }

    func toPlaylist() -> Playlist {
        Playlist(id: id, name: name ?? "Untitled Playlist", trackCount: childCount ?? 0,
                 duration: Double(runTimeTicks ?? 0) / 10_000_000, artwork: primaryArtwork)
    }
}

struct LyricsDTO: Decodable, Sendable {
    struct Line: Decodable, Sendable {
        let text: String?
        let start: Int64?
        enum CodingKeys: String, CodingKey { case text = "Text", start = "Start" }
    }

    let lyrics: [Line]
    enum CodingKeys: String, CodingKey { case lyrics = "Lyrics" }

    func toLyrics() -> Lyrics {
        Lyrics(lines: lyrics.map { Lyrics.Line(text: $0.text ?? "", start: $0.start.map { Double($0) / 10_000_000 }) })
    }
}

struct AuthenticationResponse: Decodable, Sendable {
    struct User: Decodable, Sendable {
        let id: String
        let name: String
        enum CodingKeys: String, CodingKey { case id = "Id", name = "Name" }
    }

    let user: User
    let accessToken: String
    let serverID: String?

    enum CodingKeys: String, CodingKey { case user = "User", accessToken = "AccessToken", serverID = "ServerId" }
}

struct PublicSystemInfo: Decodable, Sendable {
    let serverName: String?
    let version: String?
    let id: String?

    enum CodingKeys: String, CodingKey { case serverName = "ServerName", version = "Version", id = "Id" }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
