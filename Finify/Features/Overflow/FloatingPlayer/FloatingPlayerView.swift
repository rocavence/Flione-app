import AppKit
import SwiftUI

/// 獨立的浮動播放器：工作時放在螢幕角落。可設定永遠在最上層。
struct FloatingPlayerView: View {
    @Environment(AppEnvironment.self) private var app
    @AppStorage(SettingsKey.floatingOnTop) private var alwaysOnTop = true
    @State private var hovering = false
    @State private var window: NSWindow?

    var body: some View {
        let track = app.player.currentTrack
        ZStack(alignment: .bottom) {
            AmbientBackground(artwork: track?.artwork, intensity: 0.9)
            ArtworkView(artwork: track?.artwork, cornerRadius: 0, elevation: .none, fallbackTitle: track?.albumName)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // 滑鼠移入時才顯示控制項，平常只看到封面
            VStack(spacing: Spacing.s8) {
                if let track {
                    VStack(spacing: 2) {
                        Text(track.name).finifyFont(.bodyEmphasis).foregroundStyle(FinifyColor.Overflow.ink).lineLimit(1)
                        Text(track.artistName).finifyFont(.caption).foregroundStyle(FinifyColor.Overflow.muted).lineLimit(1)
                    }
                    ProgressBar(value: app.player.progress) { app.player.seek(to: $0 * app.player.duration) }
                }
                HStack(spacing: Spacing.s8) {
                    FinifyIconButton(icon: .skipPrev, label: "Previous") { app.player.previous() }
                    FinifyIconButton(icon: app.player.isPlaying ? .pause : .play, label: app.player.isPlaying ? "Pause" : "Play", prominent: true) {
                        app.player.togglePlayPause()
                    }
                    FinifyIconButton(icon: .skipNext, label: "Next") { app.player.next() }
                }
                .disabled(track == nil)
                HStack {
                    FinifyIconButton(icon: .layers, label: alwaysOnTop ? "Stop keeping on top" : "Keep on top", size: .compact, isActive: alwaysOnTop) {
                        alwaysOnTop.toggle()
                    }
                    Spacer()
                    if let track { FavoriteButton(itemID: track.id, name: track.name) }
                }
            }
            .padding(Spacing.s12)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
            // 0.001 而不是 0：VoiceOver 與鍵盤使用者不會觸發 hover，控制項仍要可用
            .opacity(hovering || track == nil ? 1 : 0.001)
        }
        .environment(\.overflowStyle, true)
        .environment(\.colorScheme, .dark)
        .frame(minWidth: 220, minHeight: 220)
        .onHover { hovering = $0 }
        .animation(Motion.controlsFade, value: hovering)
        .background(WindowAccessor { window = $0 })
        .onChange(of: window) { applyLevel() }
        .onChange(of: alwaysOnTop) { applyLevel() }
    }

    private func applyLevel() {
        window?.level = alwaysOnTop ? .floating : .normal
        window?.collectionBehavior = alwaysOnTop ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
        window?.isMovableByWindowBackground = true
    }
}

/// 取得 SwiftUI view 所在的 NSWindow（在 view 加入視窗時回報）
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReportingView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}
