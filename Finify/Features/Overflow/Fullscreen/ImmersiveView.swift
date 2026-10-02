import AppKit
import SwiftUI

/// Overflow Fullscreen：封面佔滿畫面。滑鼠移動時控制項淡入，靜止 2.5 秒後淡出並隱藏游標。
struct ImmersiveView: View {
    let onExit: () -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controlsVisible = true
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
                            Text(track?.name ?? "Nothing playing")
                                .finifyFont(.title)
                                .foregroundStyle(FinifyColor.Overflow.ink)
                                .lineLimit(1)
                            Text([track?.artistName, track?.albumName].compactMap { $0 }.joined(separator: " — "))
                                .finifyFont(.body)
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
                            PlaybackControls(size: .emphasis)
                        }
                        .opacity(controlsVisible ? 1 : 0)
                    }
                    .frame(maxWidth: side + 200)
                    Spacer()
                }
                .padding(Spacing.s48)

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
        .onContinuousHover { phase in
            if case .active = phase {
                lastMove = .now
                if !controlsVisible { controlsVisible = true }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                if controlsVisible, Date().timeIntervalSince(lastMove) > 2.5, app.player.isPlaying {
                    controlsVisible = false
                    NSCursor.setHiddenUntilMouseMoves(true)
                }
            }
        }
        .onExitCommand(perform: onExit)
    }
}
