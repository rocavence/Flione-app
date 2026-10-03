import SwiftUI

/// 選單列的迷你播放器：不打開主視窗也能控制播放
struct MenuBarPlayer: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            if let track = app.player.currentTrack {
                HStack(spacing: Spacing.s12) {
                    ArtworkView(artwork: track.artwork, elevation: .none)
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name).finifyFont(.bodyEmphasis).foregroundStyle(FinifyColor.ink).lineLimit(1)
                        Text(track.artistName).finifyFont(.caption).foregroundStyle(FinifyColor.muted).lineLimit(1)
                        Text(track.albumName).finifyFont(.caption).foregroundStyle(FinifyColor.faint).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    FavoriteButton(itemID: track.id, name: track.name)
                }
                ProgressBar(value: app.player.progress) { app.player.seek(to: $0 * app.player.duration) }
                HStack {
                    Text(app.player.currentTime.formattedDuration)
                    Spacer()
                    Text(app.player.duration.formattedDuration)
                }
                .finifyFont(.caption)
                .monospacedDigit()
                .foregroundStyle(FinifyColor.muted)
                .padding(.top, -Spacing.s8)
                PlaybackControls()
                    .frame(maxWidth: .infinity)
            } else {
                Text("Nothing playing")
                    .finifyFont(.body)
                    .foregroundStyle(FinifyColor.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.s16)
            }
            FinifyColor.hairline.frame(height: 1)
            // icon 按鈕：文字按鈕在 300pt 寬的面板裡會換行爆版
            HStack(spacing: Spacing.s4) {
                FinifyIconButton(icon: .window, label: "Open Flione") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                FinifyIconButton(icon: .pip, label: "Mini Player") { openWindow(id: "floating") }
                OutputPickerButton()
                CastButton()
                Spacer()
                FinifyIconButton(icon: .power, label: "Quit Flione") { NSApp.terminate(nil) }
            }
        }
        .padding(Spacing.s16)
        .frame(width: 300)
    }
}
