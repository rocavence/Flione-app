import AppKit
import SwiftUI

/// Overflow Fullscreen：封面佔滿畫面。滑鼠移動時控制項淡入，靜止 2.5 秒後淡出並隱藏游標。
struct ImmersiveView: View {
    let onExit: () -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controlsVisible = true
    @AppStorage(SettingsKey.autoHideControls) private var autoHide = true
    @State private var lastMove = Date()

    var body: some View {
        let track = app.player.currentTrack
        GeometryReader { geo in
            let side = min(geo.size.height * 0.62, geo.size.width * 0.5)
            ZStack {
                AmbientBackground(artwork: track?.artwork, intensity: 0.75)
                VStack(spacing: Spacing.s32) {
                    Spacer()
                    ArtworkView(artwork: track?.artwork, cornerRadius: Radius.small, elevation: .playing)
                        .frame(width: side, height: side)
                        .scaleEffect(app.player.isPlaying || reduceMotion ? 1 : 0.94)
                        .animation(Motion.respecting(reduceMotion, Motion.artwork), value: app.player.isPlaying)
                    VStack(spacing: Spacing.s16) {
                        VStack(spacing: Spacing.s4) {
                            // 字級隨封面尺寸縮放，大螢幕上才不會顯得過小
                            Text(track?.name ?? "Nothing playing")
                                .font(.system(size: max(28, side * 0.055), weight: .semibold))
                                .tracking(-0.02 * max(28, side * 0.055))
                                .foregroundStyle(FinifyColor.Overflow.ink)
                                .lineLimit(1)
                            Text([track?.artistName, track?.albumName].compactMap { $0 }.joined(separator: " — "))
                                .font(.system(size: max(13, side * 0.026)))
                                .foregroundStyle(FinifyColor.Overflow.muted)
                                .lineLimit(1)
                        }
                        VStack(spacing: Spacing.s12) {
                            HStack(spacing: Spacing.s12) {
                                Text(app.player.currentTime.formattedDuration).frame(width: 48, alignment: .trailing)
                                ProgressBar(value: app.player.progress) { app.player.seek(to: $0 * app.player.duration) }
                                Text(app.player.duration.formattedDuration).frame(width: 48, alignment: .leading)
                            }
                            .finifyFont(.caption)
                            .monospacedDigit()
                            .foregroundStyle(FinifyColor.Overflow.muted)
                            .frame(width: min(560, geo.size.width * 0.6))
                            HStack(spacing: Spacing.s24) {
                                if let track { FavoriteButton(itemID: track.id, name: track.name, size: .primary) }
                                PlaybackControls(size: .emphasis)
                                FinifyIconButton(icon: .microphone, label: "Lyrics", size: .primary, isActive: app.isLyricsPresented) {
                                    app.isLyricsPresented.toggle()
                                }
                                FinifyIconButton(icon: .playlist, label: "Queue", size: .primary, isActive: app.isQueuePresented) {
                                    app.isQueuePresented.toggle()
                                }
                            }
                        }
                        .opacity(controlsVisible ? 1 : 0)
                    }
                    .frame(maxWidth: side + 200)
                    Spacer()
                }
                .padding(Spacing.s48)

                if app.isLyricsPresented {
                    HStack {
                        Spacer()
                        LyricsPanel()
                            .frame(width: 420)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                            .padding(.vertical, Spacing.s80)
                            .padding(.trailing, Spacing.s32)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                if app.isQueuePresented {
                    HStack {
                        Spacer()
                        OverflowQueue(onOpenAlbum: { _ in })
                            .padding(.vertical, Spacing.s80)
                            .padding(.trailing, Spacing.s32)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                VStack {
                    HStack {
                        Spacer()
                        FinifyIconButton(icon: .exitFullscreen, label: "Exit fullscreen (Esc)", size: .primary, action: onExit)
                    }
                    Spacer()
                }
                .padding(Spacing.s24)
                .opacity(controlsVisible ? 1 : 0)
            }
        }
        .environment(\.overflowStyle, true)
        .animation(Motion.respecting(reduceMotion, Motion.controlsFade), value: controlsVisible)
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: app.isQueuePresented)
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: app.isLyricsPresented)
        .onContinuousHover { phase in
            if case .active = phase {
                lastMove = .now
                if !controlsVisible { controlsVisible = true }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                if autoHide, !app.isQueuePresented, !app.isLyricsPresented, controlsVisible, Date().timeIntervalSince(lastMove) > 2.5, app.player.isPlaying {
                    controlsVisible = false
                    NSCursor.setHiddenUntilMouseMoves(true)
                }
            }
        }
        .onExitCommand(perform: onExit)
    }
}
