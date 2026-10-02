import SwiftUI

/// 專輯卡片：封面＋標題＋藝人。hover 時出現播放鈕。
struct AlbumCard: View {
    let album: Album
    var subtitle: String?
    let onOpen: () -> Void
    let onPlay: () -> Void

    @Environment(AppEnvironment.self) private var app
    @State private var hovering = false

    private var isPlaying: Bool { app.player.currentTrack?.albumID == album.id }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            ArtworkView(artwork: album.artwork, elevation: isPlaying ? .playing : .standard, interactive: true, fallbackTitle: album.name, fallbackSubtitle: album.artistName)
                .overlay(alignment: .bottomTrailing) {
                    FinifyIconButton(icon: isPlaying && app.player.isPlaying ? .pause : .play, label: "Play \(album.name)", size: .standard, prominent: true) {
                        if isPlaying { app.player.togglePlayPause() } else { onPlay() }
                    }
                    .finifyShadow(FinifyShadow.elevated)
                    .padding(Spacing.s8)
                    .opacity(hovering || isPlaying ? 1 : 0)
                    .offset(y: hovering || isPlaying ? 0 : 6)
                    .animation(Motion.micro, value: hovering)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .finifyFont(.subheading)
                    .foregroundStyle(isPlaying ? FinifyColor.accent : FinifyColor.ink)
                    .lineLimit(1)
                Text(subtitle ?? album.artistName)
                    .finifyFont(.caption)
                    .foregroundStyle(FinifyColor.muted)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(album.name), \(album.artistName)")
        .accessibilityAddTraits(.isButton)
        // onTapGesture 不會回應 VoiceOver 的預設動作，需要另外提供
        .accessibilityAction(.default, onOpen)
        .accessibilityAction(named: "Play", onPlay)
        .contextMenu {
            Button("Play", action: onPlay)
            Button("Play Next") { queue(next: true) }
            Button("Add to Queue") { queue(next: false) }
            AddToPlaylistMenu { (try? await app.repository?.tracks(inAlbum: album.id)) ?? [] }
            Divider()
            Button("Open Album", action: onOpen)
        }
    }
}

extension AlbumCard {
    fileprivate func queue(next: Bool) {
        Task {
            guard let tracks = try? await app.repository?.tracks(inAlbum: album.id) else { return }
            if next { app.player.playNext(tracks) } else { app.player.addToQueue(tracks) }
        }
    }
}

/// 藝人卡片。藝人照片用圓形，與方形的專輯封面區隔（D06）。
struct ArtistCard: View {
    let artist: Artist
    let onOpen: () -> Void
    @Environment(AppEnvironment.self) private var app
    @State private var hovering = false

    var body: some View {
        VStack(spacing: Spacing.s8) {
            ArtworkView(artwork: app.library.artwork(for: artist), cornerRadius: 999, interactive: true, fallbackTitle: artist.name)
            Text(artist.name)
                .finifyFont(.subheading)
                .foregroundStyle(FinifyColor.ink)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onOpen)
    }
}

/// 曲目列。雙擊播放；hover 時顯示播放鈕；正在播放時以 accent 標示。
struct TrackRow: View {
    let track: Track
    /// 顯示在左側的編號（專輯曲序或清單順序）
    var number: Int?
    var showsArtwork = false
    var showsAlbum = false
    /// 專輯頁中，曲目藝人與專輯藝人相同時不重複顯示
    var showsArtist = true
    let onPlay: () -> Void
    var onOpenAlbum: (() -> Void)?
    var onOpenArtist: (() -> Void)?
    /// 頁面專屬的右鍵選單項目（例如 playlist 頁的「Remove from Playlist」）
    var extraMenu: [(title: String, action: () -> Void)] = []

    @Environment(AppEnvironment.self) private var app
    @State private var hovering = false

    private var isCurrent: Bool { app.player.currentTrack?.id == track.id }

    var body: some View {
        HStack(spacing: Spacing.s12) {
            ZStack {
                if hovering {
                    FinifyIcon(isCurrent && app.player.isPlaying ? .pause : .play, weight: .filled, size: .compact)
                        .foregroundStyle(FinifyColor.ink)
                } else if isCurrent {
                    FinifyIcon(.volumeHigh, weight: .filled, size: .compact)
                        .foregroundStyle(FinifyColor.accent)
                } else if let number {
                    Text("\(number)")
                        .finifyFont(.body)
                        .monospacedDigit()
                        .foregroundStyle(FinifyColor.muted)
                }
            }
            .frame(width: 24)
            .contentShape(Rectangle())
            .onTapGesture { if isCurrent { app.player.togglePlayPause() } else { onPlay() } }

            if showsArtwork {
                ArtworkView(artwork: track.artwork, elevation: .none)
                    .frame(width: 36, height: 36)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(track.name)
                    .finifyFont(.body)
                    .foregroundStyle(isCurrent ? FinifyColor.accent : FinifyColor.ink)
                    .lineLimit(1)
                if showsArtist {
                    Text(track.artistName)
                        .finifyFont(.caption)
                        .foregroundStyle(FinifyColor.muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsAlbum {
                Text(track.albumName)
                    .finifyFont(.caption)
                    .foregroundStyle(FinifyColor.muted)
                    .lineLimit(1)
                    .frame(maxWidth: 240, alignment: .leading)
            }

            // 0.001 而不是 0：完全透明的 view 會被移出點擊與 VoiceOver
            FavoriteButton(itemID: track.id, name: track.name)
                .opacity(hovering || app.favorites.contains(track.id) ? 1 : 0.001)
            Text(track.duration.formattedDuration)
                .finifyFont(.caption)
                .monospacedDigit()
                .foregroundStyle(FinifyColor.muted)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.s12)
        .frame(height: showsArtwork ? 52 : (showsArtist ? 44 : 36))
        .background(hovering ? FinifyColor.surface : .clear, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { if isCurrent { app.player.togglePlayPause() } else { onPlay() } }
        .contextMenu {
            Button("Play", action: onPlay)
            Button("Play Next") { app.player.playNext([track]) }
            Button("Add to Queue") { app.player.addToQueue([track]) }
            Button(app.favorites.contains(track.id) ? "Remove from Favorites" : "Add to Favorites") { app.favorites.toggle(track.id) }
            AddToPlaylistMenu { [track] }
            if !extraMenu.isEmpty {
                Divider()
                ForEach(Array(extraMenu.enumerated()), id: \.offset) { _, item in Button(item.title, action: item.action) }
            }
            if let onOpenAlbum { Divider(); Button("Go to Album", action: onOpenAlbum) }
            if let onOpenArtist { Button("Go to Artist", action: onOpenArtist) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.name), \(track.artistName), \(track.duration.formattedDuration)")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default) { if isCurrent { app.player.togglePlayPause() } else { onPlay() } }
        .accessibilityAction(named: "Play", onPlay)
        .accessibilityAction(named: app.favorites.contains(track.id) ? "Remove from Favorites" : "Add to Favorites") {
            app.favorites.toggle(track.id)
        }
    }
}

/// Playlist 卡片
struct PlaylistCard: View {
    let playlist: Playlist
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            ArtworkView(artwork: playlist.artwork, interactive: true, fallbackTitle: playlist.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name).finifyFont(.subheading).foregroundStyle(FinifyColor.ink).lineLimit(1)
                Text("\(playlist.trackCount) \(playlist.trackCount == 1 ? "song" : "songs")")
                    .finifyFont(.caption).foregroundStyle(FinifyColor.muted)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(playlist.name), playlist, \(playlist.trackCount) songs")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onOpen)
    }
}

/// 類型卡片
struct GenreCard: View {
    let genre: Genre
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            ArtworkView(artwork: genre.artwork, interactive: true, fallbackTitle: genre.name)
            Text(genre.name).finifyFont(.subheading).foregroundStyle(FinifyColor.ink).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(genre.name), genre")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onOpen)
    }
}
