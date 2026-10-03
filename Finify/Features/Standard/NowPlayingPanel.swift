import SwiftUI

/// Standard mode 右側的 Now Playing 面板：大封面、曲名、愛心、進度、控制，下方分頁為 Up Next／Lyrics。
/// 顯示哪個分頁由 app.isQueuePresented／isLyricsPresented 決定（與播放列上的按鈕同步）。
struct NowPlayingPanel: View {
    let onOpenAlbum: (String?) -> Void
    let onOpenArtist: (String?, String) -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let player = app.player
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                FinifyIconButton(icon: .x, label: "Hide Now Playing", size: .compact) {
                    app.isQueuePresented = false
                    app.isLyricsPresented = false
                }
            }
            .padding(.horizontal, Spacing.s12)
            .padding(.top, Spacing.s12)

            if let track = player.currentTrack {
                VStack(alignment: .leading, spacing: Spacing.s16) {
                    ArtworkView(artwork: track.artwork, elevation: .playing, fallbackTitle: track.albumName)
                        .frame(maxWidth: 220)
                        .frame(maxWidth: .infinity)
                        .onTapGesture { onOpenAlbum(track.albumID) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Open \(track.albumName)")
                    HStack(alignment: .top, spacing: Spacing.s8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.name)
                                .finifyFont(.heading)
                                .foregroundStyle(FinifyColor.ink)
                                .lineLimit(2)
                            Button(track.artistName) { onOpenArtist(track.artistID, track.artistName) }
                                .buttonStyle(.plain)
                                .finifyFont(.body)
                                .foregroundStyle(FinifyColor.muted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        FavoriteButton(itemID: track.id, name: track.name, size: .standard)
                    }
                    VStack(spacing: 2) {
                        ProgressBar(value: player.progress) { player.seek(to: $0 * player.duration) }
                            .accessibilityLabel("Playback position")
                        HStack {
                            Text(player.currentTime.formattedDuration)
                            Spacer()
                            Text(player.duration.formattedDuration)
                        }
                        .finifyFont(.caption)
                        .monospacedDigit()
                        .foregroundStyle(FinifyColor.faint)
                    }
                    PlaybackControls()
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Spacing.s20)
                .padding(.bottom, Spacing.s16)
            } else {
                MessageState(title: "Nothing playing", message: "Pick an album to start listening.", icon: .musicNote)
            }

            tabs
                .padding(.horizontal, Spacing.s16)
                .padding(.bottom, Spacing.s8)

            Group {
                if app.isLyricsPresented {
                    LyricsPanel(embedded: true)
                } else {
                    QueuePanel(onOpenAlbum: onOpenAlbum, embedded: true)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 320)
        .background(FinifyColor.panel)
        .overlay(alignment: .leading) { FinifyColor.hairline.frame(width: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now Playing")
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            tab("Up Next", selected: !app.isLyricsPresented) { app.isQueuePresented = true }
            tab("Lyrics", selected: app.isLyricsPresented) { app.isLyricsPresented = true }
        }
        .padding(2)
        .background(FinifyColor.glass, in: RoundedRectangle(cornerRadius: Radius.ui + 2, style: .continuous))
    }

    private func tab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .finifyFont(selected ? .bodyEmphasis : .body)
                .foregroundStyle(selected ? FinifyColor.ink : FinifyColor.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(selected ? FinifyColor.accent.opacity(0.28) : .clear, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
