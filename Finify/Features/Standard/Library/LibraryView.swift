import SwiftUI

enum LibrarySection: String, CaseIterable {
    case albums = "Albums"
    case artists = "Artists"
    case songs = "Songs"
}

enum AlbumSort: String, CaseIterable {
    case artist = "Artist"
    case title = "Title"
    case recentlyAdded = "Recently Added"
    case year = "Year"
}

struct LibraryView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(StandardRouter.self) private var router
    @State private var section: LibrarySection = .albums
    @State private var sort: AlbumSort = .artist

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s24) {
                Text("Library").finifyFont(.title).foregroundStyle(FinifyColor.ink)
                HStack(spacing: Spacing.s4) {
                    ForEach(LibrarySection.allCases, id: \.self) { item in
                        Button(item.rawValue) { section = item }
                            .buttonStyle(.plain)
                            .finifyFont(.bodyEmphasis)
                            .foregroundStyle(section == item ? FinifyColor.ink : FinifyColor.muted)
                            .padding(.horizontal, Spacing.s12)
                            .frame(height: 28)
                            .background(section == item ? FinifyColor.surface : .clear, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
                            .accessibilityAddTraits(section == item ? .isSelected : [])
                    }
                }
                Spacer()
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
                }
            }
        }
    }

    private var sortedAlbums: [Album] {
        let albums = app.library.albums
        switch sort {
        case .artist: return albums
        case .title: return albums.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recentlyAdded: return albums.sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
        case .year: return albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        }
    }

    // 上千張專輯：用 NSCollectionView 重用 cell（LazyVGrid 實測捲動掉 frame，見 S3 正式版實測）
    @ViewBuilder
    private var albums: some View {
        if app.library.albums.isEmpty {
            ScrollView { AlbumGrid(albums: nil).padding(.horizontal, Spacing.s32) }
        } else {
            CollectionGrid(items: sortedAlbums) { album in
                AlbumCard(album: album, onOpen: { router.openAlbum(album) }, onPlay: { play(album) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .environment(app)
                    .environment(router)
            }
        }
    }

    private var artists: some View {
        CollectionGrid(items: app.library.artists, minItemWidth: 140, captionHeight: 28, spacing: Spacing.s24) { artist in
            ArtistCard(artist: artist) { router.openArtist(id: artist.id, name: artist.name) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .environment(app)
        }
    }

    private func play(_ album: Album) {
        Task {
            guard let tracks = try? await app.repository?.tracks(inAlbum: album.id) else { return }
            app.player.play(tracks)
        }
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
