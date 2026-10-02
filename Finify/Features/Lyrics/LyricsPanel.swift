import SwiftUI

/// 歌詞面板。同步歌詞會亮起目前這一行並自動捲動；點任一行跳到該時間。
struct LyricsPanel: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.overflowStyle) private var overflow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lyrics: Loadable<Lyrics?> = .loading

    var body: some View {
        let track = app.player.currentTrack
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Lyrics").finifyFont(.heading).foregroundStyle(ink)
                Spacer()
                FinifyIconButton(icon: .x, label: "Close lyrics") { app.isLyricsPresented = false }
            }
            .padding(Spacing.s16)

            Group {
                if track == nil {
                    MessageState(title: "Nothing playing", message: "Play a song to see its lyrics.", icon: .microphone)
                } else {
                    content
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(overflow ? Color(white: 0.07) : FinifyColor.elevated)
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
                         message: "Add .lrc or .txt lyric files next to your music on the server, and Jellyfin will pick them up.",
                         icon: .microphone)
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
        do { lyrics = .loaded(try await repository.lyrics(for: track.id)) } catch { lyrics = .failed }
    }
}
