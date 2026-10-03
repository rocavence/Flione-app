import SwiftUI

/// YouTube Music 第二階段的驗證畫面（docs/youtube/DESIGN.md）：
/// 音樂庫專輯與喜歡的歌曲，點了用網頁播放器播放。第三階段改接 Modern／Infinity／Cover Flow。
struct YouTubeHomeView: View {
    let accountName: String
    @Environment(AppEnvironment.self) private var app
    @State private var albums: Loadable<[YTAlbum]> = .loading
    @State private var songs: Loadable<[YTSong]> = .loading

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s32) {
                    section("Albums in your library") { albumGrid }
                    section("Liked songs") { songList }
                }
                .padding(Spacing.s32)
            }
            if app.youtubePlayer.hasTrack { YouTubePlayerBar() }
        }
        .background(FinifyColor.paper)
        .task { await load() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("YouTube Music").finifyFont(.title).foregroundStyle(FinifyColor.ink)
                Text(verbatim: accountName).finifyFont(.caption).foregroundStyle(FinifyColor.muted)
            }
            Spacer()
            FinifyButton(title: "Sign Out", kind: .secondary) {
                app.youtubePlayer.stop()
                Task { await app.youtube.signOut() }
            }
        }
        .padding(.horizontal, Spacing.s32)
        .padding(.top, 44)
        .padding(.bottom, Spacing.s16)
    }

    private func section<Content: View>(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text(title).finifyFont(.heading).foregroundStyle(FinifyColor.ink)
            content()
        }
    }

    @ViewBuilder
    private var albumGrid: some View {
        switch albums {
        case .loading: ProgressView().controlSize(.small)
        case .failed: Text("Can't load albums.").foregroundStyle(FinifyColor.muted)
        case .loaded(let list):
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: Spacing.s20, alignment: .top)], alignment: .leading, spacing: Spacing.s24) {
                ForEach(list) { album in
                    Button {
                        if let videoId = album.videoId { app.youtubePlayer.play(videoId: videoId, playlistId: album.playlistId) }
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.s8) {
                            RemoteArtwork(url: album.artwork)
                            Text(verbatim: album.title).finifyFont(.bodyEmphasis).foregroundStyle(FinifyColor.ink).lineLimit(1)
                            Text(verbatim: album.artist).finifyFont(.caption).foregroundStyle(FinifyColor.muted).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var songList: some View {
        switch songs {
        case .loading: ProgressView().controlSize(.small)
        case .failed: Text("Can't load songs.").foregroundStyle(FinifyColor.muted)
        case .loaded(let list):
            VStack(spacing: 2) {
                ForEach(list) { song in
                    Button { app.youtubePlayer.play(videoId: song.id, playlistId: song.playlistId) } label: {
                        HStack(spacing: Spacing.s12) {
                            RemoteArtwork(url: song.artwork).frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: song.title).finifyFont(.body).foregroundStyle(FinifyColor.ink).lineLimit(1)
                                Text(verbatim: [song.artist, song.album].compactMap { $0 }.joined(separator: " · "))
                                    .finifyFont(.caption).foregroundStyle(FinifyColor.muted).lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, Spacing.s8)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func load() async {
        do { albums = .loaded(try await YouTubeLibrary.likedAlbums()) } catch { albums = .failed }
        do { songs = .loaded(try await YouTubeLibrary.likedSongs()) } catch { songs = .failed }
        #if DEBUG
        // -FinifyDemoYTPlay YES：載入後自動播第一首喜歡的歌（驗證網頁播放器）
        if UserDefaults.standard.bool(forKey: "FinifyDemoYTPlay"), case .loaded(let list) = songs, let first = list.first {
            app.youtubePlayer.play(videoId: first.id, playlistId: first.playlistId)
        }
        #endif
    }
}

/// 網址來源的封面（YouTube Music 的縮圖）
private struct RemoteArtwork: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image { image.resizable().scaledToFill() } else { FinifyColor.surface }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
    }
}

/// 底部播放列：封面、歌名、上一首／播放暫停／下一首、進度
private struct YouTubePlayerBar: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let player = app.youtubePlayer
        HStack(spacing: Spacing.s16) {
            RemoteArtwork(url: player.artwork).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: player.title.isEmpty ? "…" : player.title).finifyFont(.bodyEmphasis).foregroundStyle(FinifyColor.ink).lineLimit(1)
                Text(verbatim: player.artist).finifyFont(.caption).foregroundStyle(FinifyColor.muted).lineLimit(1)
            }
            .frame(width: 220, alignment: .leading)
            Spacer()
            VStack(spacing: 4) {
                HStack(spacing: Spacing.s16) {
                    FinifyIconButton(icon: .skipPrev, label: "Previous") { player.previous() }
                    FinifyIconButton(icon: player.isPlaying ? .pause : .play, label: player.isPlaying ? "Pause" : "Play", prominent: true) { player.togglePlayPause() }
                    FinifyIconButton(icon: .skipNext, label: "Next") { player.next() }
                }
                ProgressBar(value: player.duration > 0 ? player.currentTime / player.duration : 0) { player.seek(to: $0 * player.duration) }
                    .frame(width: 360)
            }
            Spacer()
            Color.clear.frame(width: 272, height: 1)
        }
        .padding(.horizontal, Spacing.s24)
        .padding(.vertical, Spacing.s12)
        .background(FinifyColor.panel)
        .overlay(alignment: .top) { FinifyColor.hairline.frame(height: 1) }
    }
}
