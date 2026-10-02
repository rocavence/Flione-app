import SwiftUI

@MainActor @Observable
final class AlbumViewModel {
    var tracks: Loadable<[Track]> = .loading

    func load(_ album: Album, repository: (any MusicRepository)?) async {
        guard let repository else { return }
        do { tracks = .loaded(try await repository.tracks(inAlbum: album.id)) } catch { tracks = .failed }
    }
}

struct AlbumView: View {
    let album: Album
    @Environment(AppEnvironment.self) private var app
    @Environment(StandardRouter.self) private var router
    @State private var model = AlbumViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s32) {
                header
                trackList
                moreByArtist
            }
            .padding(.horizontal, Spacing.s32)
            .padding(.vertical, Spacing.s32)
        }
        .background(alignment: .top) { AmbientWash(artwork: album.artwork) }
        .task { await model.load(album, repository: app.repository) }
    }

    private var tracks: [Track] {
        if case .loaded(let tracks) = model.tracks { return tracks }
        return []
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: Spacing.s32) {
            ArtworkView(artwork: album.artwork, elevation: .playing, fallbackTitle: album.name, fallbackSubtitle: album.artistName)
                .frame(width: 232, height: 232)
            VStack(alignment: .leading, spacing: Spacing.s12) {
                Text("Album")
                    .finifyFont(.micro)
                    .textCase(.uppercase)
                    .foregroundStyle(FinifyColor.muted)
                Text(album.name)
                    .finifyFont(.display)
                    .foregroundStyle(FinifyColor.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                HStack(spacing: Spacing.s8) {
                    Button(album.artistName) { router.openArtist(id: album.artistID, name: album.artistName) }
                        .buttonStyle(.plain)
                        .finifyFont(.bodyEmphasis)
                        .foregroundStyle(FinifyColor.ink)
                    Text(metadata)
                        .finifyFont(.body)
                        .foregroundStyle(FinifyColor.muted)
                }
                HStack(spacing: Spacing.s8) {
                    if isPlayingThisAlbum {
                        FinifyButton(title: app.player.isPlaying ? "Pause" : "Resume", icon: app.player.isPlaying ? .pause : .play, kind: .primary) {
                            app.player.togglePlayPause()
                        }
                    } else {
                        FinifyButton(title: "Play", icon: .play, kind: .primary) { app.player.play(tracks) }
                    }
                    FinifyButton(title: "Shuffle", icon: .shuffle) { app.player.play(tracks, shuffled: true) }
                    FinifyIconButton(icon: .playlist, label: "Add to Queue") { app.player.addToQueue(tracks) }
                    FavoriteButton(itemID: album.id, name: album.name, size: .standard)
                }
                .disabled(tracks.isEmpty)
                .padding(.top, Spacing.s8)
            }
        }
    }

    /// 同一藝人的其他專輯（取自已載入的音樂庫）
    @ViewBuilder
    private var moreByArtist: some View {
        let others = album.artistID.map { id in app.library.albums.filter { $0.artistID == id && $0.id != album.id } } ?? []
        if !others.isEmpty {
            AlbumShelf(title: "More by \(album.artistName)", state: .loaded(Array(others.prefix(12))),
                       action: ("Show all", { router.openArtist(id: album.artistID, name: album.artistName) }))
                .padding(.top, Spacing.s16)
        }
    }

    private var isPlayingThisAlbum: Bool { app.player.currentTrack?.albumID == album.id }

    private var metadata: String {
        var parts: [String] = []
        if let year = album.year { parts.append(String(year)) }
        if !tracks.isEmpty {
            parts.append("\(tracks.count) \(tracks.count == 1 ? "song" : "songs")")
            parts.append(tracks.reduce(0) { $0 + $1.duration }.formattedDuration)
        }
        return parts.map { "· \($0)" }.joined(separator: " ")
    }

    @ViewBuilder
    private var trackList: some View {
        switch model.tracks {
        case .loading:
            VStack(spacing: Spacing.s8) {
                ForEach(0..<8, id: \.self) { _ in SkeletonBlock().frame(height: 36) }
            }
        case .failed:
            MessageState(title: "Can't load this album.", message: "Check your connection to the music server.", icon: .wifiOff,
                         primary: ("Retry", { Task { model.tracks = .loading; await model.load(album, repository: app.repository) } }))
        case .loaded(let tracks):
            let discs = Dictionary(grouping: tracks) { $0.discNumber ?? 1 }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(discs.keys.sorted(), id: \.self) { disc in
                    if discs.count > 1 {
                        HStack(spacing: Spacing.s8) {
                            FinifyIcon(.cd, size: .compact)
                            Text("Disc \(disc)").finifyFont(.micro).textCase(.uppercase)
                        }
                        .foregroundStyle(FinifyColor.muted)
                        .padding(.horizontal, Spacing.s12)
                        .padding(.top, disc == discs.keys.min() ? 0 : Spacing.s16)
                        .padding(.bottom, Spacing.s4)
                    }
                    ForEach(discs[disc] ?? []) { track in
                        TrackRow(track: track, number: track.trackNumber, showsArtist: track.artistName != album.artistName, onPlay: {
                            app.player.play(tracks, startAt: tracks.firstIndex(of: track) ?? 0)
                        }, onOpenArtist: { router.openArtist(id: track.artistID, name: track.artistName) })
                    }
                }
            }
        }
    }
}

/// 從封面 BlurHash 取色的頂部淡色背景（ambient color，與品牌色分離）
struct AmbientWash: View {
    let artwork: ArtworkRef?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let hash = artwork?.blurHash, let c = BlurHash.averageColor(hash) {
            LinearGradient(
                colors: [Color(red: c.r, green: c.g, blue: c.b).opacity(colorScheme == .dark ? 0.35 : 0.22), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 420)
            .allowsHitTesting(false)
        }
    }
}
