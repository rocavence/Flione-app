import AppKit
import Observation

/// AI 控制（D54）：讓 Claude、Cursor 等支援 MCP 的 app 操作 Flione。
/// 設定 → AI 控制打開後，Flione 開一個本機 socket（MCPSocket）；AI app 啟動 `Flione --mcp`（MCPProxy）轉送 JSON-RPC 到這裡。
/// 工具只用 Flione 已有的動作（播放器、音樂庫、播放清單、最愛）；刪除播放清單一定先跳對話框問使用者
@MainActor @Observable
final class MCPController {
    nonisolated static let enabledKey = "FlioneMCPEnabled"

    private(set) var isEnabled = UserDefaults.standard.bool(forKey: MCPController.enabledKey)
    /// 目前連著的 AI app 數量（設定頁顯示）
    private(set) var connectedClients = 0
    /// 最近一次連線的 AI app 名稱（initialize 的 clientInfo），刪除確認的對話框會寫出來
    private(set) var clientName: String?
    private(set) var startError: String?

    @ObservationIgnored private weak var app: AppEnvironment?
    @ObservationIgnored private var server: MCPSocketServer?
    @ObservationIgnored private let socketPath: String
    /// 回傳過給 AI 的歌曲：`track_ids` 用這裡找回完整資料（音樂來源沒有「用 id 取一首歌」的 API）
    @ObservationIgnored private var knownTracks: [String: Track] = [:]
    /// 刪除播放清單前問使用者；測試時換掉
    @ObservationIgnored var confirmDelete: (Playlist, String) async -> Bool = MCPController.askToDelete

    init(socketPath: String = MCPController.defaultSocketPath) {
        self.socketPath = socketPath
    }

    /// 開發版用另一個 socket，測試時不會搶走正式版的連線
    nonisolated static var defaultSocketPath: String {
        #if DEBUG
        MCPSocket.path.replacingOccurrences(of: "mcp.sock", with: "mcp-debug.sock")
        #else
        MCPSocket.path
        #endif
    }

    func attach(_ app: AppEnvironment) {
        self.app = app
        // 當 test host 時不開，避免占用使用者的 socket
        if isEnabled, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil { start() }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        enabled ? start() : stop()
    }

    private func start() {
        guard server == nil else { return }
        let server = MCPSocketServer(path: socketPath) { [weak self] line, reply in
            Task { @MainActor in reply(await self?.handle(line)) }
        }
        server.onClientCountChange = { [weak self] count in
            Task { @MainActor in self?.connectedClients = count }
        }
        do {
            try server.start()
            self.server = server
            startError = nil
        } catch {
            startError = error.localizedDescription
        }
    }

    private func stop() {
        server?.stop()
        server = nil
        connectedClients = 0
    }

    // MARK: - JSON-RPC

    struct ToolError: Error { let message: String; init(_ message: String) { self.message = message } }

    static let protocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    /// 處理一則訊息；通知（沒有 id）不回覆
    func handle(_ line: Data) async -> Data? {
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return Self.encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let id = message["id"] else { return nil }
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]
        func reply(_ result: [String: Any]) -> Data? { Self.encode(["jsonrpc": "2.0", "id": id, "result": result]) }
        func failure(_ code: Int, _ text: String) -> Data? { Self.encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": text]]) }

        switch method {
        case "initialize":
            clientName = (params["clientInfo"] as? [String: Any])?["name"] as? String
            let requested = params["protocolVersion"] as? String ?? ""
            return reply([
                "protocolVersion": Self.protocolVersions.contains(requested) ? requested : Self.protocolVersions[1],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "flione", "title": "Flione", "version": UpdateChecker.currentVersion],
                "instructions": """
                    Controls the Flione music player on this Mac (Jellyfin or YouTube Music, whichever the user is signed in to). \
                    Find IDs with search_library, list_albums, list_artists, list_playlists, or get_tracks before playing or editing; never make up IDs. \
                    delete_playlist always asks the user to confirm in Flione.
                    """,
            ])
        case "ping":
            return reply([:])
        case "tools/list":
            return reply(["tools": Self.tools])
        case "tools/call":
            guard let name = params["name"] as? String, Self.tools.contains(where: { $0["name"] as? String == name }) else {
                return failure(-32602, "Unknown tool")
            }
            do {
                let value = try await call(name, params["arguments"] as? [String: Any] ?? [:])
                return reply(["content": [["type": "text", "text": Self.text(value)]]])
            } catch let error as ToolError {
                return reply(["content": [["type": "text", "text": error.message]], "isError": true])
            } catch {
                return reply(["content": [["type": "text", "text": error.localizedDescription]], "isError": true])
            }
        default:
            return failure(-32601, "Method not found: \(method)")
        }
    }

    private static func encode(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
    }

    private static func text(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes, .sortedKeys]) else { return "\(value)" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - 工具

    private static let sourceProperties: [String: Any] = [
        "track_ids": ["type": "array", "items": ["type": "string"], "description": "Song IDs returned by other Flione tools."],
        "album_id": ["type": "string"],
        "playlist_id": ["type": "string"],
        "artist_id": ["type": "string", "description": "Plays or adds the artist's most popular songs."],
    ]

    private static func tool(_ name: String, _ title: String, _ description: String, _ properties: [String: Any] = [:],
                             required: [String] = [], readOnly: Bool = false, destructive: Bool = false) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "title": title, "description": description, "inputSchema": schema,
                "annotations": ["readOnlyHint": readOnly, "destructiveHint": destructive, "openWorldHint": false]]
    }

    static var tools: [[String: Any]] {
        [
            tool("get_now_playing", "Now playing",
                 "The current song, playback state, position, volume, shuffle and repeat, radio, music source, and the next songs in the queue.",
                 readOnly: true),
            tool("control_playback", "Control playback",
                 "Play, pause, skip, seek, or change volume, shuffle, or repeat. Returns the new state.",
                 ["action": ["type": "string", "enum": ["play", "pause", "toggle", "next", "previous", "seek", "set_volume", "set_shuffle", "set_repeat"]],
                  "seconds": ["type": "number", "description": "For seek: position in seconds."],
                  "volume": ["type": "integer", "minimum": 0, "maximum": 100, "description": "For set_volume."],
                  "shuffle": ["type": "string", "enum": ["off", "on", "smart"], "description": "For set_shuffle. smart mixes in similar songs."],
                  "repeat": ["type": "string", "enum": ["off", "all", "one"], "description": "For set_repeat."]],
                 required: ["action"]),
            tool("search_library", "Search",
                 "Search the user's music source for artists, albums, songs, and playlists.",
                 ["query": ["type": "string"], "limit": ["type": "integer", "minimum": 1, "maximum": 50, "description": "Per kind. Default 10."]],
                 required: ["query"], readOnly: true),
            tool("list_albums", "List albums",
                 "Albums in the user's library, optionally filtered by artist or title.",
                 ["artist": ["type": "string", "description": "Artist name contains this."],
                  "artist_id": ["type": "string"],
                  "query": ["type": "string", "description": "Album title contains this."],
                  "sort": ["type": "string", "enum": ["recently_added", "title", "artist", "year"], "description": "Default recently_added."],
                  "limit": ["type": "integer", "minimum": 1, "maximum": 500, "description": "Default 50."]],
                 readOnly: true),
            tool("list_artists", "List artists",
                 "Artists in the user's library.",
                 ["query": ["type": "string", "description": "Name contains this."],
                  "limit": ["type": "integer", "minimum": 1, "maximum": 500, "description": "Default 100."]],
                 readOnly: true),
            tool("list_playlists", "List playlists", "The user's playlists.", readOnly: true),
            tool("get_tracks", "Get songs",
                 "Songs of an album or playlist, or an artist's most popular songs. Includes play counts when available.",
                 sourceProperties.filter { $0.key != "track_ids" }, readOnly: true),
            tool("play", "Play",
                 "Replace the queue and start playing. Give exactly one of track_ids, album_id, playlist_id, or artist_id.",
                 sourceProperties.merging(["shuffle": ["type": "boolean"]]) { $1 }),
            tool("start_radio", "Start radio",
                 "Endless radio from a mood, or from a song, album, or artist ID. Keeps adding similar songs.",
                 ["mood": ["type": "string", "enum": Mood.allCases.map(\.rawValue)],
                  "seed_id": ["type": "string", "description": "A song, album, or artist ID."],
                  "name": ["type": "string", "description": "Shown as the radio's name. Defaults to the seed's name."]]),
            tool("add_to_queue", "Add to queue",
                 "Add songs to the queue: right after the current song (next) or at the end.",
                 sourceProperties.merging(["position": ["type": "string", "enum": ["next", "end"], "description": "Default end."]]) { $1 }),
            tool("create_playlist", "Create playlist",
                 "Create a playlist, optionally with songs.",
                 sourceProperties.merging(["name": ["type": "string"]]) { $1 }, required: ["name"]),
            tool("add_to_playlist", "Add to playlist",
                 "Add songs to the end of a playlist.",
                 sourceProperties.merging(["playlist_id": ["type": "string"]]) { $1 }, required: ["playlist_id"]),
            tool("delete_playlist", "Delete playlist",
                 "Delete a playlist. Flione asks the user to confirm first; if they decline, nothing is deleted.",
                 ["playlist_id": ["type": "string"]], required: ["playlist_id"], destructive: true),
            tool("set_favorite", "Set favorite",
                 "Mark a song, album, or artist as a favorite, or remove it. On YouTube Music, favoriting an album saves it to the library.",
                 ["item_id": ["type": "string"], "favorite": ["type": "boolean"]], required: ["item_id", "favorite"]),
        ]
    }

    private func call(_ name: String, _ args: [String: Any]) async throws -> Any {
        guard let app else { throw ToolError("Flione isn't ready yet.") }
        if name == "get_now_playing" { return nowPlaying(app) }
        guard app.session != nil, let repository = app.repository else {
            throw ToolError("Flione isn't signed in to a music source. Sign in to Jellyfin or YouTube Music in Flione first.")
        }
        let player = app.player

        switch name {
        case "control_playback":
            switch args["action"] as? String {
            case "play": if !player.isPlaying { player.togglePlayPause() }
            case "pause": player.pause()
            case "toggle": player.togglePlayPause()
            case "next": player.next()
            case "previous": player.previous()
            case "seek":
                guard let seconds = (args["seconds"] as? NSNumber)?.doubleValue else { throw ToolError("seek needs seconds.") }
                player.seek(to: max(0, seconds))
            case "set_volume":
                guard let volume = (args["volume"] as? NSNumber)?.doubleValue else { throw ToolError("set_volume needs volume (0–100).") }
                player.volume = Float(min(100, max(0, volume)) / 100)
            case "set_shuffle":
                guard let target = args["shuffle"] as? String, ["off", "on", "smart"].contains(target) else { throw ToolError("set_shuffle needs shuffle: off, on, or smart.") }
                // 播放器的 shuffle 是三段循環（關 → 隨機 → Smart Shuffle）
                for _ in 0..<3 where Self.shuffleState(player) != target { player.toggleShuffle() }
            case "set_repeat":
                guard let target = args["repeat"] as? String, ["off", "all", "one"].contains(target) else { throw ToolError("set_repeat needs repeat: off, all, or one.") }
                for _ in 0..<3 where Self.repeatState(player.repeatMode) != target { player.cycleRepeat() }
            default:
                throw ToolError("Unknown action.")
            }
            return nowPlaying(app)

        case "search_library":
            guard let query = args["query"] as? String, !query.isEmpty else { throw ToolError("search_library needs a query.") }
            let limit = Self.int(args["limit"], default: 10, max: 50)
            let results = try await repository.search(query)
            return ["artists": results.artists.prefix(limit).map(Self.info),
                    "albums": results.albums.prefix(limit).map(Self.info),
                    "songs": results.tracks.prefix(limit).map { info($0) },
                    "playlists": results.playlists.prefix(limit).map(Self.info)]

        case "list_albums":
            if app.library.albums.isEmpty { await app.library.refreshIfNeeded() }
            var albums = app.library.albums
            if let artistID = args["artist_id"] as? String { albums = albums.filter { $0.artistID == artistID } }
            if let artist = args["artist"] as? String, !artist.isEmpty { albums = albums.filter { $0.artistName.localizedCaseInsensitiveContains(artist) } }
            if let query = args["query"] as? String, !query.isEmpty { albums = albums.filter { $0.name.localizedCaseInsensitiveContains(query) } }
            switch args["sort"] as? String {
            case "title": albums.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            case "artist": albums.sort { $0.artistName.localizedStandardCompare($1.artistName) == .orderedAscending }
            case "year": albums.sort { ($0.year ?? 0) > ($1.year ?? 0) }
            default: albums.sort { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
            }
            return ["total": albums.count, "albums": albums.prefix(Self.int(args["limit"], default: 50, max: 500)).map(Self.info)]

        case "list_artists":
            if app.library.artists.isEmpty { await app.library.refreshIfNeeded() }
            var artists = app.library.artists
            if let query = args["query"] as? String, !query.isEmpty { artists = artists.filter { $0.name.localizedCaseInsensitiveContains(query) } }
            return ["total": artists.count, "artists": artists.prefix(Self.int(args["limit"], default: 100, max: 500)).map(Self.info)]

        case "list_playlists":
            if app.playlists.playlists.isEmpty { await app.playlists.refresh() }
            return ["playlists": app.playlists.playlists.map(Self.info)]

        case "get_tracks":
            return ["songs": try await tracks(from: args, repository).map { info($0) }]

        case "play":
            let tracks = try await tracks(from: args, repository)
            player.play(tracks, shuffled: args["shuffle"] as? Bool ?? false)
            return ["playing": tracks.count, "now_playing": player.currentTrack.map { info($0) as Any } ?? NSNull()]

        case "start_radio":
            if let raw = args["mood"] as? String {
                guard let mood = Mood(rawValue: raw) else { throw ToolError("Unknown mood.") }
                await player.startMoodRadio(mood)
            } else if let seed = args["seed_id"] as? String {
                guard repository.supportsRadio else { throw ToolError("This music source doesn't support radio.") }
                let name = args["name"] as? String ?? knownTracks[seed]?.name
                    ?? app.library.albums.first { $0.id == seed }?.name
                    ?? app.library.artists.first { $0.id == seed }?.name ?? "Radio"
                player.startRadio(seedID: seed, name: name)
                // 電台在背景取歌；等一下再回報，AI 才看得到開始播的歌
                for _ in 0..<40 where player.radioName != name { try? await Task.sleep(for: .milliseconds(250)) }
            } else {
                throw ToolError("start_radio needs mood or seed_id.")
            }
            guard player.radioName != nil else { throw ToolError(player.notice?.message ?? "Couldn't start the radio.") }
            return nowPlaying(app)

        case "add_to_queue":
            let tracks = try await tracks(from: args, repository)
            if args["position"] as? String == "next" { player.playNext(tracks) } else { player.addToQueue(tracks) }
            return ["added": tracks.count, "queue_length": player.queue.upcoming.count]

        case "create_playlist":
            guard let name = (args["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { throw ToolError("create_playlist needs a name.") }
            let hasSongs = Self.sourceProperties.keys.contains { args[$0] != nil }
            let tracks = hasSongs ? try await tracks(from: args, repository) : []
            guard let playlist = await app.playlists.create(name: name, tracks: tracks) else {
                throw ToolError(app.playlists.failureMessage ?? "Couldn't create the playlist.")
            }
            return ["playlist": Self.info(playlist)]

        case "add_to_playlist":
            let playlist = try await playlist(args["playlist_id"], app, repository)
            let tracks = try await tracks(from: args, repository)
            let before = app.playlists.failureMessage
            await app.playlists.add(tracks, to: playlist)
            if let message = app.playlists.failureMessage, message != before { throw ToolError(message) }
            return ["added": tracks.count, "playlist": Self.info(app.playlists.playlists.first { $0.id == playlist.id } ?? playlist)]

        case "delete_playlist":
            let playlist = try await playlist(args["playlist_id"], app, repository)
            guard await confirmDelete(playlist, clientName ?? "An AI app") else {
                throw ToolError("The user chose not to delete “\(playlist.name)”. Nothing was deleted.")
            }
            guard await app.playlists.delete(playlist) else { throw ToolError(app.playlists.failureMessage ?? "Couldn't delete the playlist.") }
            return ["deleted": Self.info(playlist)]

        case "set_favorite":
            guard let id = args["item_id"] as? String, let favorite = args["favorite"] as? Bool else { throw ToolError("set_favorite needs item_id and favorite.") }
            if app.favorites.contains(id) != favorite { app.favorites.toggle(id) }
            return ["item_id": id, "favorite": favorite]

        default:
            throw ToolError("Unknown tool.")
        }
    }

    /// track_ids、album_id、playlist_id 或 artist_id 其中一個 → 歌曲
    private func tracks(from args: [String: Any], _ repository: any MusicRepository) async throws -> [Track] {
        let tracks: [Track]
        if let ids = args["track_ids"] as? [String] {
            let queued = Dictionary(app?.player.queue.tracks.map { ($0.id, $0) } ?? [], uniquingKeysWith: { first, _ in first })
            let missing = ids.filter { knownTracks[$0] == nil && queued[$0] == nil }
            guard missing.isEmpty else {
                throw ToolError("Unknown song IDs: \(missing.joined(separator: ", ")). Get songs from search_library or get_tracks first.")
            }
            tracks = ids.compactMap { knownTracks[$0] ?? queued[$0] }
        } else if let id = args["album_id"] as? String {
            tracks = try await repository.tracks(inAlbum: id)
        } else if let id = args["playlist_id"] as? String {
            tracks = try await repository.playlistTracks(id)
        } else if let id = args["artist_id"] as? String {
            tracks = try await repository.popularTracks(byArtist: id, limit: 50)
        } else {
            throw ToolError("Give one of track_ids, album_id, playlist_id, or artist_id.")
        }
        guard !tracks.isEmpty else { throw ToolError("No songs found.") }
        for track in tracks { knownTracks[track.id] = track }
        return tracks
    }

    private func playlist(_ id: Any?, _ app: AppEnvironment, _ repository: any MusicRepository) async throws -> Playlist {
        guard let id = id as? String else { throw ToolError("Missing playlist_id.") }
        if app.playlists.playlists.isEmpty { await app.playlists.refresh() }
        if let playlist = app.playlists.playlists.first(where: { $0.id == id }) { return playlist }
        guard let playlist = try? await repository.playlist(id: id) else { throw ToolError("No playlist with ID \(id). Use list_playlists.") }
        return playlist
    }

    // MARK: - 回傳的資料

    private func nowPlaying(_ app: AppEnvironment) -> [String: Any] {
        let player = app.player
        var state: [String: Any] = [
            "state": player.isPlaying ? "playing" : player.currentTrack == nil ? "stopped" : "paused",
            "position": Int(player.currentTime),
            "duration": Int(player.duration),
            "volume": Int((player.volume * 100).rounded()),
            "shuffle": Self.shuffleState(player),
            "repeat": Self.repeatState(player.repeatMode),
            "source": app.session == nil ? "none" : app.source.rawValue,
            "up_next": player.queue.upcoming.prefix(20).map { info($0) },
        ]
        if let track = player.currentTrack, !track.isPlaceholder { state["song"] = info(track) }
        if let radio = player.radioName { state["radio"] = radio }
        return state
    }

    private func info(_ track: Track) -> [String: Any] {
        knownTracks[track.id] = track
        var info: [String: Any] = ["id": track.id, "title": track.name, "artist": track.artistName, "album": track.albumName,
                                   "duration": Int(track.duration)]
        if let id = track.albumID { info["album_id"] = id }
        if let id = track.artistID { info["artist_id"] = id }
        // YouTube Music 的播放次數是 Flione 自己記的（D51）
        let local = app?.session?.isYouTube == true ? app?.youtubePlays.entry(for: track.id) : nil
        if let count = local?.count ?? track.playCount { info["play_count"] = count }
        if let last = local?.last ?? track.lastPlayed { info["last_played"] = last.ISO8601Format() }
        if app?.favorites.contains(track.id) == true { info["favorite"] = true }
        return info
    }

    private static func info(_ album: Album) -> [String: Any] {
        var info: [String: Any] = ["id": album.id, "title": album.name, "artist": album.artistName]
        if let id = album.artistID { info["artist_id"] = id }
        if let year = album.year { info["year"] = year }
        return info
    }

    private static func info(_ artist: Artist) -> [String: Any] { ["id": artist.id, "name": artist.name] }

    private static func info(_ playlist: Playlist) -> [String: Any] {
        ["id": playlist.id, "name": playlist.name, "song_count": playlist.trackCount, "duration": Int(playlist.duration)]
    }

    private static func shuffleState(_ player: PlayerManager) -> String {
        player.isSmartShuffle ? "smart" : player.isShuffled ? "on" : "off"
    }

    private static func repeatState(_ mode: RepeatMode) -> String {
        switch mode { case .off: "off"; case .all: "all"; case .one: "one" }
    }

    private static func int(_ value: Any?, default fallback: Int, max upper: Int) -> Int {
        guard let number = (value as? NSNumber)?.intValue else { return fallback }
        return min(upper, Swift.max(1, number))
    }

    // MARK: - 刪除前確認

    private static func askToDelete(_ playlist: Playlist, client: String) async -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Delete “\(playlist.name)”?")
        alert.informativeText = String(localized: "\(client) asked Flione to delete this playlist. It's removed from your music server. The songs stay in your library.")
        let delete = alert.addButton(withTitle: String(localized: "Delete Playlist"))
        delete.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "Cancel"))
        if let window = FullscreenTracker.mainWindow, window.isVisible {
            return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
        }
        return alert.runModal() == .alertFirstButtonReturn
    }
}
