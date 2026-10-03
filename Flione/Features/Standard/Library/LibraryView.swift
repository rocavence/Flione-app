import SwiftUI

enum LibrarySection: String, CaseIterable, Sendable {
    case albums = "Albums"
    case artists = "Artists"
    case songs = "Songs"
    case genres = "Genres"
    case playlists = "Playlists"
    case favorites = "Favorites"
}


struct LibraryView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(StandardRouter.self) private var router
    /// 由側欄決定
    let section: LibrarySection
    /// 標題（例如「Recently Added」）；nil 時用分頁名稱
    var title: String?
    @State var sort: AlbumSort = .artist

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s24) {
                Text(title ?? section.rawValue).finifyFont(.title).foregroundStyle(FinifyColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if section == .playlists {
                    FinifyButton(title: "New Playlist", icon: .plus) { app.newPlaylistTracks = [] }
                }
                if section == .albums {
                    Picker("Sort", selection: $sort) {
                        ForEach(AlbumSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .finifyFont(.caption)
                }
            }
            .padding(.horizontal, Spacing.s32)
            .padding(.top, Spacing.s32)
            .padding(.bottom, Spacing.s16)

            if app.library.state == .failed && app.library.albums.isEmpty {
                MessageState(title: "Can't reach your music server.", message: "Your library will appear as soon as the connection is back.",
                             icon: .wifiOff, primary: ("Retry", { Task { await app.library.refresh() } }))
                Spacer()
            } else {
                switch section {
                case .albums: albums
                case .artists: artists
                case .songs: SongsList()
                case .playlists: playlistGrid
                case .genres: GenreGrid()
                case .favorites: FavoriteSongs()
                }
            }
        }
    }

    private var sortedAlbums: [Album] { sort.apply(to: app.library.albums) }

    // 上千張專輯：用 NSCollectionView 重用 cell（LazyVGrid 實測捲動掉 frame，見 S3 正式版實測）
    @ViewBuilder
    private var albums: some View {
        if app.library.albums.isEmpty {
            ScrollView { AlbumGrid(albums: nil).padding(.horizontal, Spacing.s32) }
        } else {
            LibraryAlbumGrid(albums: sortedAlbums, app: app, onOpen: { router.openAlbum($0) }, onPlay: play)
        }
    }

    private var artists: some View {
        CollectionGrid(items: app.library.artists, minItemWidth: 140, captionHeight: 28, spacing: Spacing.s24) { artist in
            ArtistCard(artist: artist) { router.openArtist(id: artist.id, name: artist.name) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .environment(app)
        }
    }

    @ViewBuilder
    private var playlistGrid: some View {
        if app.playlists.playlists.isEmpty {
            MessageState(title: "Your playlists are empty.", message: "Create your first playlist and make the library yours.",
                         icon: .playlist2, primary: ("Create Playlist", { app.newPlaylistTracks = [] }))
            Spacer()
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 156, maximum: 220), spacing: Spacing.s20, alignment: .top)], alignment: .leading, spacing: Spacing.s24) {
                    ForEach(app.playlists.playlists) { playlist in
                        PlaylistCard(playlist: playlist) { router.open(.playlist(playlist)) }
                    }
                }
                .padding(.horizontal, Spacing.s32)
                .padding(.bottom, Spacing.s32)
            }
            .task { await app.playlists.refresh() }
        }
    }

    private func play(_ album: Album) {
        app.player.play(album: album)
    }
}

/// 全部歌曲，捲到底時分頁載入
private struct SongsList: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(StandardRouter.self) private var router
    @State private var tracks: [Track] = []
    @State private var total = Int.max
    @State private var isLoading = false
    @State private var failed = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track: track, number: index + 1, showsArtwork: true, showsAlbum: true, onPlay: {
                        let start = max(0, index - 50)
                        app.player.play(Array(tracks[start..<min(tracks.count, index + 200)]), startAt: index - start)
                    }, onOpenArtist: { router.openArtist(id: track.artistID, name: track.artistName) })
                    .onAppear { if index == tracks.count - 30 { Task { await loadMore() } } }
                }
                if failed {
                    MessageState(title: "Can't load songs.", message: "Check your connection to the music server.", icon: .wifiOff,
                                 primary: ("Retry", { Task { failed = false; await loadMore() } }))
                } else if isLoading {
                    ForEach(0..<10, id: \.self) { _ in SkeletonBlock().frame(height: 44) }
                }
            }
            .padding(.horizontal, Spacing.s24)
            .padding(.bottom, Spacing.s32)
        }
        .task { if tracks.isEmpty { await loadMore() } }
    }

    private func loadMore() async {
        guard !isLoading, tracks.count < total, let repository = app.repository else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await repository.songs(offset: tracks.count, limit: 200)
            tracks += page.tracks
            total = page.total
        } catch {
            failed = true
        }
    }
}

/// 喜愛的歌曲。愛心狀態改變時重新載入
private struct FavoriteSongs: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(StandardRouter.self) private var router
    @State private var tracks: Loadable<[Track]> = .loading

    var body: some View {
        Group {
            switch tracks {
            case .loading:
                VStack(spacing: Spacing.s8) { ForEach(0..<8, id: \.self) { _ in SkeletonBlock().frame(height: 44) } }
                    .padding(.horizontal, Spacing.s32)
                Spacer()
            case .failed:
                MessageState(title: "Can't load your favorites.", message: "Check your connection to the music server.", icon: .wifiOff,
                             primary: ("Retry", { Task { await load() } }))
                Spacer()
            case .loaded(let all) where all.allSatisfy({ !app.favorites.contains($0.id) }):
                MessageState(title: "No favorites yet.", message: "Tap the heart next to a song and it will show up here.", icon: .heart)
                Spacer()
            case .loaded(let all):
                // 先依本機狀態過濾，取消喜愛的歌曲立即消失；server 寫入完成後再重新載入
                let list = all.filter { app.favorites.contains($0.id) }
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: track, number: index + 1, showsArtwork: true, showsAlbum: true, onPlay: {
                                app.player.play(list, startAt: index)
                            }, onOpenArtist: { router.openArtist(id: track.artistID, name: track.artistName) })
                        }
                    }
                    .padding(.horizontal, Spacing.s24)
                    .padding(.bottom, Spacing.s32)
                }
            }
        }
        .task(id: app.favorites.revision) { await load() }
    }

    private func load() async {
        guard let repository = app.repository else { return }
        do { tracks = .loaded(try await repository.favoriteTracks()) } catch { tracks = .failed }
    }
}

/// 類型格線
private struct GenreGrid: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(StandardRouter.self) private var router
    @State private var genres: Loadable<[Genre]> = .loading

    var body: some View {
        Group {
            switch genres {
            case .loading:
                ScrollView { AlbumGrid(albums: nil).padding(.horizontal, Spacing.s32) }
            case .failed:
                MessageState(title: "Can't load genres.", message: "Check your connection to the music server.", icon: .wifiOff,
                             primary: ("Retry", { Task { await load() } }))
                Spacer()
            case .loaded(let list):
                CollectionGrid(items: list, captionHeight: 28) { genre in
                    GenreCard(genre: genre) { router.open(.genre(genre)) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .environment(app)
                }
            }
        }
        .task { if case .loading = genres { await load() } }
    }

    private func load() async {
        guard let repository = app.repository else { return }
        do { genres = .loaded(try await repository.genres()) } catch { genres = .failed }
    }
}
