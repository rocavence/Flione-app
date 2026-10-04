import SwiftUI

@MainActor @Observable
final class ArtistViewModel {
    var artist: Artist?
    var popular: Loadable<[Track]> = .loading
    var albums: Loadable<[Album]> = .loading

    func load(id: String, repository: (any MusicRepository)?) async {
        guard let repository else { return }
        async let artist = try? repository.artist(id: id)
        async let popular: Loadable<[Track]> = { do { return .loaded(try await repository.popularTracks(byArtist: id, limit: 5)) } catch { return .failed } }()
        async let albums: Loadable<[Album]> = { do { return .loaded(try await repository.albums(byArtist: id)) } catch { return .failed } }()
        (self.artist, self.popular, self.albums) = await (artist, popular, albums)
    }
}

/// 藝人頁面的專輯排序；記住上次的選擇
enum ArtistAlbumSort: String, CaseIterable, Sendable {
    case newest, oldest, title, recentlyAdded

    var title: LocalizedStringResource {
        switch self {
        case .newest: "Newest First"
        case .oldest: "Oldest First"
        case .title: "Title"
        case .recentlyAdded: "Recently Added"
        }
    }

    /// 同年份或沒有日期的維持原本順序（Swift 的 sorted 不保證穩定，所以帶上原本的位置）
    func apply(to albums: [Album]) -> [Album] {
        let indexed = Array(albums.enumerated())
        func by(_ before: (Album, Album) -> Bool?) -> [Album] {
            indexed.sorted { a, b in before(a.element, b.element) ?? (a.offset < b.offset) }.map(\.element)
        }
        switch self {
        case .newest: return by { a, b in a.year == b.year ? nil : (a.year ?? 0) > (b.year ?? 0) }
        // 沒有年份的排最後
        case .oldest: return by { a, b in a.year == b.year ? nil : (a.year ?? .max) < (b.year ?? .max) }
        case .title: return by { a, b in
            let order = a.name.localizedStandardCompare(b.name)
            return order == .orderedSame ? nil : order == .orderedAscending
        }
        case .recentlyAdded: return by { a, b in a.dateAdded == b.dateAdded ? nil : (a.dateAdded ?? .distantPast) > (b.dateAdded ?? .distantPast) }
        }
    }
}

struct ArtistView: View {
    let artistID: String
    let name: String
    @Environment(AppEnvironment.self) private var app
    @Environment(StandardRouter.self) private var router
    @State private var model = ArtistViewModel()
    @AppStorage("FinifyArtistAlbumSort") private var sort: ArtistAlbumSort = .newest

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s40) {
                header
                popularSection
                albumsSection
            }
            .padding(Spacing.s32)
        }
        .background(alignment: .top) { AmbientWash(artwork: model.artist?.artwork ?? firstAlbumArtwork) }
        .task { await model.load(id: artistID, repository: app.repository) }
    }

    private var firstAlbumArtwork: ArtworkRef? {
        if case .loaded(let albums) = model.albums { return albums.first { $0.artwork != nil }?.artwork }
        return nil
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: Spacing.s32) {
            ArtworkView(artwork: model.artist?.artwork ?? firstAlbumArtwork, cornerRadius: 999, elevation: .playing)
                .frame(width: 200, height: 200)
            VStack(alignment: .leading, spacing: Spacing.s12) {
                Text("Artist").finifyFont(.micro).textCase(.uppercase).foregroundStyle(FinifyColor.muted)
                Text(name).finifyFont(.display).foregroundStyle(FinifyColor.ink).lineLimit(2).minimumScaleFactor(0.6)
                HStack(spacing: Spacing.s8) {
                    FinifyButton(title: "Play", icon: .play, kind: .primary) { Task { await playAll(shuffled: false) } }
                    FinifyButton(title: "Shuffle", icon: .shuffle) { Task { await playAll(shuffled: true) } }
                    if app.repository?.supportsRadio == true {
                        FinifyButton(title: "Radio", icon: .radio) { app.player.startRadio(seedID: artistID, name: name) }
                    }
                }
                .padding(.top, Spacing.s8)
            }
        }
    }

    @ViewBuilder
    private var popularSection: some View {
        if case .loaded(let tracks) = model.popular, !tracks.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s12) {
                SectionHeader(title: "Popular")
                VStack(spacing: 2) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(track: track, number: index + 1, showsArtwork: true, showsAlbum: true, onPlay: {
                            app.player.play(tracks, startAt: index)
                        }, onOpenAlbum: { openAlbum(id: track.albumID) })
                    }
                }
            }
        } else if case .loading = model.popular {
            VStack(spacing: Spacing.s8) { ForEach(0..<5, id: \.self) { _ in SkeletonBlock().frame(height: 44) } }
        }
    }

    @ViewBuilder
    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            HStack(alignment: .center) {
                SectionHeader(title: "Albums")
                Picker("Sort", selection: $sort) {
                    ForEach(ArtistAlbumSort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .finifyFont(.caption)
            }
            switch model.albums {
            case .loading:
                AlbumGrid(albums: nil)
            case .failed:
                MessageState(title: "Can't load albums.", message: "Check your connection to the music server.", icon: .wifiOff,
                             primary: ("Retry", { Task { await model.load(id: artistID, repository: app.repository) } }))
            case .loaded(let albums):
                AlbumGrid(albums: sort.apply(to: albums), subtitle: { $0.year.map(String.init) ?? "Album" })
            }
        }
    }

    private func openAlbum(id: String?) {
        guard case .loaded(let albums) = model.albums, let album = albums.first(where: { $0.id == id }) else { return }
        router.openAlbum(album)
    }

    /// 依專輯順序（新到舊）串成整個藝人的曲目
    private func playAll(shuffled: Bool) async {
        guard case .loaded(let albums) = model.albums, let repository = app.repository else { return }
        var tracks: [Track] = []
        for album in albums.prefix(20) {
            if let albumTracks = try? await repository.tracks(inAlbum: album.id) { tracks += albumTracks }
        }
        app.player.play(tracks, shuffled: shuffled)
    }
}

/// 自適應欄數的專輯格線（Standard 用；Overflow 的 Album Wall 另以 NSCollectionView 實作）
struct AlbumGrid: View {
    /// nil = 載入中
    let albums: [Album]?
    var subtitle: ((Album) -> String)?
    @Environment(AppEnvironment.self) private var app
    @Environment(StandardRouter.self) private var router

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 156, maximum: 220), spacing: Spacing.s20, alignment: .top)], alignment: .leading, spacing: Spacing.s24) {
            if let albums {
                ForEach(albums) { album in
                    AlbumCard(album: album, subtitle: subtitle?(album), onOpen: { router.openAlbum(album) }, onPlay: { app.player.play(album: album) })
                }
            } else {
                ForEach(0..<12, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Spacing.s8) {
                        SkeletonBlock().aspectRatio(1, contentMode: .fit)
                        SkeletonBlock().frame(width: 110, height: 10)
                    }
                }
            }
        }
    }
}
