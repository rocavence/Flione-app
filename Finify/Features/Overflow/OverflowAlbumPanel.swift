import SwiftUI

/// 在 Overflow 中打開的專輯：大封面＋曲目，深色沉浸式。不離開 Overflow。
struct OverflowAlbumPanel: View {
    let album: Album
    let onClose: () -> Void
    /// 切換到同一藝人的其他專輯（Overflow 中的藝人瀏覽）
    var onOpenAlbum: ((Album) -> Void)?
    @Environment(AppEnvironment.self) private var app
    @State private var tracks: Loadable<[Track]> = .loading

    /// 同一藝人的其他專輯，取自已載入的音樂庫，不需額外請求
    private var moreByArtist: [Album] {
        guard let artistID = album.artistID else { return [] }
        return app.library.albums.filter { $0.artistID == artistID && $0.id != album.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s24) {
        HStack(alignment: .top, spacing: Spacing.s40) {
            ArtworkView(artwork: album.artwork, elevation: .playing, fallbackTitle: album.name, fallbackSubtitle: album.artistName)
                .frame(width: 360, height: 360)
            VStack(alignment: .leading, spacing: Spacing.s16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Spacing.s8) {
                        Text(album.name)
                            .finifyFont(.title)
                            .foregroundStyle(FinifyColor.Overflow.ink)
                            .lineLimit(2)
                        Text([album.artistName, album.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                            .finifyFont(.body)
                            .foregroundStyle(FinifyColor.Overflow.muted)
                    }
                    Spacer()
                    FinifyIconButton(icon: .x, label: "Close", action: onClose)
                }
                HStack(spacing: Spacing.s8) {
                    FinifyButton(title: "Play", icon: .play, kind: .primary) { play(at: 0) }
                    FinifyButton(title: "Shuffle", icon: .shuffle) { if case .loaded(let t) = tracks { app.player.play(t, shuffled: true) } }
                    FinifyIconButton(icon: .playlist, label: "Add to Queue") { if case .loaded(let t) = tracks { app.player.addToQueue(t) } }
                    FavoriteButton(itemID: album.id, name: album.name, size: .standard)
                }
                trackList
            }
            .frame(width: 420)
        }
            if !moreByArtist.isEmpty, let onOpenAlbum {
                VStack(alignment: .leading, spacing: Spacing.s12) {
                    Text("More by \(album.artistName)")
                        .finifyFont(.micro)
                        .textCase(.uppercase)
                        .foregroundStyle(FinifyColor.Overflow.muted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.s12) {
                            ForEach(moreByArtist) { other in
                                VStack(alignment: .leading, spacing: Spacing.s4) {
                                    ArtworkView(artwork: other.artwork, elevation: .none, interactive: true,
                                                fallbackTitle: other.name, fallbackSubtitle: other.artistName)
                                        .frame(width: 88, height: 88)
                                    Text(other.name)
                                        .finifyFont(.caption)
                                        .foregroundStyle(FinifyColor.Overflow.muted)
                                        .lineLimit(1)
                                        .frame(width: 88, alignment: .leading)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { onOpenAlbum(other) }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(other.name)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction(.default) { onOpenAlbum(other) }
                            }
                        }
                    }
                    .frame(width: 820)
                }
            }
        }
        .padding(Spacing.s32)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Radius.large, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1) }
        .finifyShadow(FinifyShadow.Style(color: .black.opacity(0.5), radius: 60, y: 30))
        .environment(\.colorScheme, .dark)
        .task(id: album.id) {
            tracks = .loading
            do { tracks = .loaded(try await app.repository?.tracks(inAlbum: album.id) ?? []) } catch { tracks = .failed }
        }
    }

    @ViewBuilder
    private var trackList: some View {
        switch tracks {
        case .loading:
            VStack(spacing: Spacing.s8) { ForEach(0..<6, id: \.self) { _ in SkeletonBlock().frame(height: 32) } }
        case .failed:
            MessageState(title: "Can't load this album.", message: "Check your connection to the music server.", icon: .wifiOff)
        case .loaded(let list):
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, track in
                        OverflowTrackRow(track: track, number: track.trackNumber ?? index + 1) { play(at: index) }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }

    private func play(at index: Int) {
        guard case .loaded(let list) = tracks, !list.isEmpty else { return }
        app.player.play(list, startAt: index)
    }
}

private struct OverflowTrackRow: View {
    let track: Track
    let number: Int
    let onPlay: () -> Void
    @Environment(AppEnvironment.self) private var app
    @State private var hovering = false

    var body: some View {
        let current = app.player.currentTrack?.id == track.id
        HStack(spacing: Spacing.s12) {
            Group {
                if current { FinifyIcon(.volumeHigh, weight: .filled, size: .compact).foregroundStyle(FinifyColor.accent) }
                else if hovering { FinifyIcon(.play, weight: .filled, size: .compact).foregroundStyle(FinifyColor.Overflow.ink) }
                else { Text("\(number)").monospacedDigit().foregroundStyle(FinifyColor.Overflow.faint) }
            }
            .frame(width: 20)
            Text(track.name)
                .foregroundStyle(current ? FinifyColor.accent : FinifyColor.Overflow.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(track.duration.formattedDuration).monospacedDigit().foregroundStyle(FinifyColor.Overflow.faint)
        }
        .finifyFont(.body)
        .padding(.horizontal, Spacing.s8)
        .frame(height: 34)
        .background(hovering ? FinifyColor.Overflow.control : .clear, in: RoundedRectangle(cornerRadius: Radius.small))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onPlay)
        .onTapGesture { if hovering { onPlay() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onPlay)
        .accessibilityAction(named: "Play", onPlay)
    }
}
