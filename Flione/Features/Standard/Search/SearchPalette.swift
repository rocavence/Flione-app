import SwiftUI

@MainActor @Observable
final class SearchViewModel {
    var query = ""
    private(set) var results: Loadable<SearchResults>?
    /// 鍵盤選取的列（跨 artists / albums / songs 的扁平索引）
    var selection = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    var flatItems: [SearchItem] {
        guard case .loaded(let r) = results else { return [] }
        return r.artists.map(SearchItem.artist) + r.albums.map(SearchItem.album) + r.playlists.map(SearchItem.playlist) + r.tracks.map(SearchItem.track)
    }

    /// 輸入停頓 250 ms 後才送出搜尋
    func queryChanged(_ repository: (any MusicRepository)?) {
        task?.cancel()
        selection = 0
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, let repository else { results = nil; return }
        task = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            if results == nil { results = .loading }
            do {
                let found = try await repository.search(term)
                guard !Task.isCancelled else { return }
                results = .loaded(found)
            } catch {
                guard !Task.isCancelled else { return }
                results = .failed
            }
        }
    }
}

enum SearchItem: Identifiable {
    case artist(Artist), album(Album), playlist(Playlist), track(Track)

    var id: String {
        switch self {
        case .artist(let a): "artist-\(a.id)"
        case .album(let a): "album-\(a.id)"
        case .playlist(let p): "playlist-\(p.id)"
        case .track(let t): "track-\(t.id)"
        }
    }
}

/// ⌘K 搜尋的全畫面浮層：其他地方暗下來，搜尋框固定在畫面正中央，結果往下展開。Standard 與 Overflow 共用
struct SearchOverlay: View {
    let onOpenAlbum: (Album) -> Void
    let onOpenArtist: (Artist) -> Void
    var onOpenPlaylist: ((Playlist) -> Void)?
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        GeometryReader { geo in
            let top = max(Spacing.s32, geo.size.height / 2 - SearchPalette.fieldHeight / 2)
            ZStack(alignment: .top) {
                Color.black.opacity(0.55)
                    .contentShape(Rectangle())
                    .onTapGesture { app.isSearchPresented = false }
                SearchPalette(onOpenAlbum: onOpenAlbum, onOpenArtist: onOpenArtist, onOpenPlaylist: onOpenPlaylist,
                              maxResultsHeight: max(160, geo.size.height - top - SearchPalette.fieldHeight - Spacing.s32))
                    .padding(.top, top)
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }
}

/// ⌘K 搜尋面板。Standard 與 Overflow 共用（D08）。
struct SearchPalette: View {
    static let fieldHeight: CGFloat = 72

    let onOpenAlbum: (Album) -> Void
    let onOpenArtist: (Artist) -> Void
    var onOpenPlaylist: ((Playlist) -> Void)?
    var maxResultsHeight: CGFloat = 460
    @Environment(AppEnvironment.self) private var app
    @State private var model = SearchViewModel()
    @FocusState private var fieldFocused: Bool
    /// 結果的實際高度：結果少時面板跟著縮，不留一大塊空白
    @State private var resultsHeight: CGFloat = 0

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s12) {
                FlioneIcon(.search, size: .primary).foregroundStyle(FlioneColor.muted)
                TextField("", text: $model.query, prompt: Text("Search artists, albums, and songs"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .medium))
                    .focused($fieldFocused)
                    .onChange(of: model.query) { model.queryChanged(app.repository) }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onSubmit(activateSelection)
                if !model.query.isEmpty {
                    FlioneIconButton(icon: .x, label: "Clear search", size: .compact) { model.query = "" }
                }
            }
            .padding(.horizontal, Spacing.s24)
            .frame(height: Self.fieldHeight)

            if model.results != nil {
                FlioneColor.hairline.frame(height: 1)
                resultsView
                    .frame(maxHeight: min(460, maxResultsHeight))
            }
        }
        .frame(width: 720)
        .flioneGlass(in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous), tint: FlioneColor.elevated.opacity(0.4), backing: FlioneColor.elevated.opacity(0.75),
                     fallback: FlioneColor.elevated)
        .flioneShadow(FlioneShadow.Style(color: .black.opacity(0.3), radius: 40, y: 20))
        .defaultFocus($fieldFocused, true)
        .onAppear {
            fieldFocused = true
            // 浮層出現的同一個 frame 設定焦點有時不生效，下一輪再設一次，確保游標在輸入框
            Task { @MainActor in fieldFocused = true }
            #if DEBUG || BENCHMARK
            if let term = DebugDemo.searchTerm, model.query.isEmpty { model.query = term }
            #endif
        }
        .onExitCommand { app.isSearchPresented = false }
        .environment(\.overflowStyle, false)
    }

    @ViewBuilder
    private var resultsView: some View {
        switch model.results {
        case .loading:
            VStack(spacing: Spacing.s8) {
                ForEach(0..<5, id: \.self) { _ in SkeletonBlock().frame(height: 40) }
            }
            .padding(Spacing.s16)
        case .failed:
            MessageState(title: "Can't search right now.", message: "Your music server isn't responding.", icon: .wifiOff,
                         primary: ("Retry", { model.queryChanged(app.repository) }))
        case .loaded(let r) where r.isEmpty:
            MessageState(title: "No matches for “\(model.query)”", message: "Try a different spelling, or search for an artist or album name.", icon: .search)
        case .loaded(let r):
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        let items = model.flatItems
                        section("Artists", count: r.artists.count)
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index == r.artists.count { section("Albums", count: r.albums.count) }
                            if index == r.artists.count + r.albums.count { section("Playlists", count: r.playlists.count) }
                            if index == r.artists.count + r.albums.count + r.playlists.count { section("Songs", count: r.tracks.count) }
                            row(item, selected: index == model.selection)
                                .id(item.id)
                                .onTapGesture { model.selection = index; activateSelection() }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction(.default) { model.selection = index; activateSelection() }
                                .onHover { if $0 { model.selection = index } }
                        }
                    }
                    .padding(Spacing.s8)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { resultsHeight = $0 }
                }
                .frame(maxHeight: resultsHeight)
                .onChange(of: model.selection) {
                    let items = model.flatItems
                    if items.indices.contains(model.selection) { proxy.scrollTo(items[model.selection].id) }
                }
            }
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringResource, count: Int) -> some View {
        if count > 0 {
            Text(title)
                .flioneFont(.micro)
                .textCase(.uppercase)
                .foregroundStyle(FlioneColor.muted)
                .padding(.horizontal, Spacing.s8)
                .padding(.top, Spacing.s12)
                .padding(.bottom, Spacing.s4)
        }
    }

    private func row(_ item: SearchItem, selected: Bool) -> some View {
        HStack(spacing: Spacing.s12) {
            switch item {
            case .artist(let artist):
                ArtworkView(artwork: app.library.artwork(for: artist), cornerRadius: 999, elevation: .none).frame(width: 36, height: 36)
                text(artist.name, "Artist")
            case .album(let album):
                ArtworkView(artwork: album.artwork, elevation: .none).frame(width: 36, height: 36)
                text(album.name, "Album · \(album.artistName)")
            case .playlist(let playlist):
                ArtworkView(artwork: playlist.artwork, elevation: .none, fallbackTitle: playlist.name).frame(width: 36, height: 36)
                text(playlist.name, "Playlist · \(playlist.trackCount) songs")
            case .track(let track):
                ArtworkView(artwork: track.artwork, elevation: .none).frame(width: 36, height: 36)
                text(track.name, "Song · \(track.artistName)")
                Text(track.duration.formattedDuration).flioneFont(.caption).monospacedDigit().foregroundStyle(FlioneColor.muted)
            }
            if selected {
                Text("↩").flioneFont(.caption).foregroundStyle(FlioneColor.faint)
            }
        }
        .padding(.horizontal, Spacing.s8)
        .frame(height: 48)
        .background(selected ? FlioneColor.surface : .clear, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
        .contentShape(Rectangle())
    }

    private func text(_ title: String, _ subtitle: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).flioneFont(.body).foregroundStyle(FlioneColor.ink).lineLimit(1)
            Text(subtitle).flioneFont(.caption).foregroundStyle(FlioneColor.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func move(_ delta: Int) {
        let count = model.flatItems.count
        guard count > 0 else { return }
        model.selection = (model.selection + delta + count) % count
    }

    private func activateSelection() {
        let items = model.flatItems
        guard items.indices.contains(model.selection) else { return }
        switch items[model.selection] {
        case .artist(let artist): onOpenArtist(artist)
        case .album(let album): onOpenAlbum(album)
        case .playlist(let playlist):
            if let onOpenPlaylist {
                onOpenPlaylist(playlist)
            } else {
                Task { if let tracks = try? await app.repository?.playlistTracks(playlist.id) { app.player.play(tracks) } }
            }
        case .track(let track):
            // 播放該曲所在專輯，從這首開始
            Task {
                if let albumID = track.albumID, let tracks = try? await app.repository?.tracks(inAlbum: albumID),
                   let index = tracks.firstIndex(where: { $0.id == track.id }) {
                    app.player.play(tracks, startAt: index)
                } else {
                    app.player.play([track])
                }
            }
        }
        app.isSearchPresented = false
    }
}
