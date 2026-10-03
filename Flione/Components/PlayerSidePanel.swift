import SwiftUI

/// 佇列與歌詞的浮層：三種模式共用，浮在內容右側的 Liquid Glass 面板。
/// 顯示哪個分頁由 app.isQueuePresented／isLyricsPresented 決定（與播放列上的按鈕同步）。
struct PlayerSidePanel: View {
    let onOpenAlbum: (String?) -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.overflowStyle) private var overflow

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            header
            Group {
                if app.isLyricsPresented {
                    LyricsPanel()
                } else {
                    QueuePanel(onOpenAlbum: onOpenAlbum)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 360)
        .clipShape(shape)
        // 文字為主的面板：玻璃上墊一層半透明底，後面的封面才不會干擾閱讀
        .finifyGlass(in: shape, tint: overflow ? FinifyColor.Ocean.surface1.opacity(0.5) : FinifyColor.elevated.opacity(0.4),
                     backing: overflow ? FinifyColor.Ocean.surface1.opacity(0.55) : FinifyColor.elevated.opacity(0.7),
                     fallback: FinifyColor.elevated)
        .finifyShadow(FinifyShadow.Style(color: .black.opacity(0.4), radius: 40, y: 16))
        // 面板內一律用一般配色（Overflow 的半透明白字不適合長清單）
        .environment(\.overflowStyle, false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.isLyricsPresented ? "Lyrics" : "Queue")
    }

    private var header: some View {
        HStack(spacing: Spacing.s8) {
            HStack(spacing: 2) {
                tab("Up Next", selected: !app.isLyricsPresented) { app.isQueuePresented = true }
                tab("Lyrics", selected: app.isLyricsPresented) { app.isLyricsPresented = true }
            }
            .padding(3)
            .background(FinifyColor.glass, in: Capsule())
            Spacer()
            if !app.isLyricsPresented, !app.player.queue.upcoming.isEmpty {
                FinifyButton(title: "Clear", kind: .ghost) { app.player.clearUpcoming() }
            }
            FinifyIconButton(icon: .x, label: "Close", size: .compact) {
                app.isQueuePresented = false
                app.isLyricsPresented = false
            }
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s12)
    }

    private func tab(_ title: LocalizedStringResource, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .finifyFont(selected ? .bodyEmphasis : .body)
                .foregroundStyle(selected ? FinifyColor.onPrimary : FinifyColor.muted)
                .padding(.horizontal, Spacing.s12)
                .frame(height: 28)
                .background(selected ? FinifyColor.primary : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
