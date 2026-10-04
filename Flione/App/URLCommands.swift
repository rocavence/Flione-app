import Foundation

/// `flione://` 網址（舊的 `finify://` 仍可用）：讓 Raycast、Alfred、捷徑等工具控制 Flione。做法參考 Kaset（MIT）的 URLHandler。
///
///     flione://play | pause | toggle | next | previous
///     flione://album/<id>               打開專輯
///     flione://play?album=<id>          播放專輯
///     flione://play?playlist=<id>       播放 playlist
extension AppEnvironment {
    func handle(_ url: URL) {
        guard url.scheme == "flione" || url.scheme == "finify", session != nil else { return }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }

        switch url.host() {
        case "play":
            if let id = value("album") {
                Task { if let tracks = try? await repository?.tracks(inAlbum: id) { player.play(tracks) } }
            } else if let id = value("playlist") {
                Task { if let tracks = try? await repository?.playlistTracks(id) { player.play(tracks) } }
            } else if !player.isPlaying {
                player.togglePlayPause()
            }
        case "pause": player.pause()
        case "toggle": player.togglePlayPause()
        case "next": player.next()
        case "previous": player.previous()
        case "album":
            let id = url.pathComponents.dropFirst().first
            if let id, !id.isEmpty { requestedAlbumID = id }
        default: break
        }
    }
}
