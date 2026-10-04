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
            if let radio = app.player.radioName, !app.isLyricsPresented {
                // 電台：佇列會自動補歌；可以停止，目前的佇列照常播完
                HStack(spacing: Spacing.s8) {
                    FlioneIcon(.radio, size: .compact).foregroundStyle(FlioneColor.accent)
                    Text("\(radio) Radio").flioneFont(.bodyEmphasis).foregroundStyle(FlioneColor.ink).lineLimit(1)
                    Spacer(minLength: 0)
                    FlioneButton(title: "Stop Radio", kind: .ghost) { app.player.stopRadio() }
                }
                .padding(.horizontal, Spacing.s16)
                .padding(.bottom, Spacing.s8)
            }
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
        .flioneGlass(in: shape, tint: overflow ? FlioneColor.Ocean.surface1.opacity(0.5) : FlioneColor.elevated.opacity(0.4),
                     backing: overflow ? FlioneColor.Ocean.surface1.opacity(0.55) : FlioneColor.elevated.opacity(0.7),
                     fallback: FlioneColor.elevated)
        .flioneShadow(FlioneShadow.Style(color: .black.opacity(0.4), radius: 40, y: 16))
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
            .background(FlioneColor.glass, in: Capsule())
            Spacer()
            if !app.isLyricsPresented, !app.player.queue.upcoming.isEmpty {
                FlioneButton(title: "Clear", kind: .ghost) { app.player.clearUpcoming() }
            }
            FlioneIconButton(icon: .x, label: "Close", size: .compact) {
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
                .flioneFont(selected ? .bodyEmphasis : .body)
                .foregroundStyle(selected ? FlioneColor.onPrimary : FlioneColor.muted)
                .padding(.horizontal, Spacing.s12)
                .frame(height: 28)
                .background(selected ? FlioneColor.primary : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
