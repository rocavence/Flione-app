import SwiftUI

/// 歌詞內容（外框、標題與分頁由 PlayerSidePanel 提供）。同步歌詞會亮起目前這一行並自動捲動；點任一行跳到該時間。
struct LyricsPanel: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.overflowStyle) private var overflow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lyrics: Loadable<Lyrics?> = .loading
    /// 目前歌詞是否來自 LRCLIB（顯示來源）
    @State private var fromLRCLib = false
    @AppStorage(SettingsKey.onlineLyrics) private var onlineLyrics = false

    var body: some View {
        let track = app.player.currentTrack
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if track == nil {
                    MessageState(title: "Nothing playing", message: "Play a song to see its lyrics.", icon: .notes2)
                } else {
                    content
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .task(id: track?.id) { await load(track) }
    }

    private var ink: Color { overflow ? FinifyColor.Overflow.ink : FinifyColor.ink }
    private var muted: Color { overflow ? FinifyColor.Overflow.muted : FinifyColor.muted }

    @ViewBuilder
    private var content: some View {
        switch lyrics {
        case .loading:
            VStack(alignment: .leading, spacing: Spacing.s12) {
                ForEach(0..<8, id: \.self) { i in SkeletonBlock().frame(width: CGFloat(140 + (i * 37) % 120), height: 14) }
            }
            .padding(Spacing.s16)
        case .failed:
            MessageState(title: "Can't load lyrics.", message: "Check your connection to the music server.", icon: .wifiOff,
                         primary: ("Retry", { Task { await load(app.player.currentTrack) } }))
        case .loaded(nil):
            MessageState(title: "No lyrics for this song.",
                         message: onlineLyrics
                            ? "Neither your server nor LRCLIB has lyrics for it."
                            : "Add .lrc or .txt lyric files next to your music on the server, or search LRCLIB, a free online lyrics database.",
                         icon: .notes2,
                         primary: onlineLyrics ? nil : ("Search LRCLIB", {
                             onlineLyrics = true
                             Task { await load(app.player.currentTrack) }
                         }))
        case .loaded(let value?):
            lines(value)
        }
    }

    private func lines(_ lyrics: Lyrics) -> some View {
        let current = lyrics.currentLineIndex(at: app.player.currentTime)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s12) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: lyrics.isSynced ? 19 : 15, weight: lyrics.isSynced ? .semibold : .regular))
                            .foregroundStyle(lyrics.isSynced ? (index == current ? ink : muted.opacity(0.7)) : ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { if let start = line.start { app.player.seek(to: start) } }
                            .id(index)
                            .accessibilityAddTraits(index == current ? .isSelected : [])
                    }
                }
                .padding(.horizontal, Spacing.s16)
                .padding(.vertical, Spacing.s48)
                if fromLRCLib {
                    Text("Lyrics from LRCLIB")
                        .finifyFont(.caption)
                        .foregroundStyle(muted)
                        .padding(.horizontal, Spacing.s16)
                        .padding(.bottom, Spacing.s24)
                }
            }
            .onChange(of: current) {
                guard let current else { return }
                withAnimation(reduceMotion ? nil : Motion.ui) { proxy.scrollTo(current, anchor: .center) }
            }
        }
    }

    private func load(_ track: Track?) async {
        guard let track, let repository = app.repository else { return }
        lyrics = .loading
        guard !track.isPlaceholder else { return }
        fromLRCLib = false
        do {
            var result = try await repository.lyrics(for: track.id)
            // server 沒有歌詞時，使用者同意的話再查 LRCLIB；外部查詢失敗就當作沒有歌詞
            if result == nil, onlineLyrics, let online = try? await LRCLib.lyrics(for: track) {
                result = online
                fromLRCLib = true
            }
            guard !Task.isCancelled else { return }
            lyrics = .loaded(result)
        } catch {
            guard !Task.isCancelled else { return }
            lyrics = .failed
        }
    }
}
