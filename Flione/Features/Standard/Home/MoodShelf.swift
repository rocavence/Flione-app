import SwiftUI

/// 首頁的心情電台（D50）：一排可橫向捲動的方形卡，像 Apple Music 的分類卡：
/// 心情的色彩、左上角的名稱、右下角斜放一張音樂庫裡的封面。點了就開始播
struct MoodShelf: View {
    @Environment(AppEnvironment.self) private var app
    @State private var loading: Mood?
    // 尺寸、間距、翻頁箭頭與首頁其他區塊（AlbumShelf）相同
    private let cardWidth: CGFloat = 168
    @State private var firstVisible = 0
    @State private var visibleCount = 6

    private var moods: [Mood] { Mood.allCases }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            HStack(alignment: .center) {
                SectionHeader(title: "Mood Radio")
                if moods.count > visibleCount {
                    HStack(spacing: Spacing.s4) {
                        FinifyIconButton(icon: .chevronLeft, label: "Scroll Mood Radio left", size: .compact) { page(-1) }
                            .disabled(firstVisible == 0)
                        FinifyIconButton(icon: .chevronRight, label: "Scroll Mood Radio right", size: .compact) { page(1) }
                            .disabled(firstVisible + visibleCount >= moods.count)
                    }
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Spacing.s20) {
                        ForEach(moods) { mood in
                            MoodCard(mood: mood, cover: cover(for: mood), side: cardWidth, loading: loading == mood,
                                     playing: app.player.radioName == String(localized: mood.title)) {
                                start(mood)
                            }
                            .id(mood)
                        }
                    }
                    .padding(.vertical, Spacing.s8)
                }
                .scrollClipDisabled()
                .onChange(of: firstVisible) {
                    withAnimation(Motion.ui) { proxy.scrollTo(moods[firstVisible], anchor: .leading) }
                }
            }
            .background(GeometryReader { geo in
                Color.clear.onAppear { visibleCount = max(1, Int(geo.size.width / (cardWidth + Spacing.s20))) }
                    .onChange(of: geo.size.width) { visibleCount = max(1, Int(geo.size.width / (cardWidth + Spacing.s20))) }
            })
        }
    }

    private func page(_ direction: Int) {
        firstVisible = min(max(0, firstVisible + direction * visibleCount), max(0, moods.count - visibleCount))
    }

    /// 封面：曲風符合心情的專輯（依心情固定挑一張，每次看到的一樣）。
    /// 沒有曲風資料（YouTube）或沒有符合的就不放封面，改用心情圖示，避免「專注」配上搖滾專輯
    private func cover(for mood: Mood) -> ArtworkRef? {
        let matched = app.library.albums.filter { album in
            album.artwork != nil && (album.genres ?? []).contains { genre in mood.genreKeywords.contains { genre.lowercased().contains($0) } }
        }
        guard !matched.isEmpty else { return nil }
        let index = Mood.allCases.firstIndex(of: mood) ?? 0
        return matched[(index * 7919 + matched.count / 3) % matched.count].artwork
    }

    private func start(_ mood: Mood) {
        guard loading == nil else { return }
        loading = mood
        Task {
            await app.player.startMoodRadio(mood)
            loading = nil
        }
    }
}

private struct MoodCard: View {
    let mood: Mood
    let cover: ArtworkRef?
    let side: CGFloat
    let loading: Bool
    let playing: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                background
                if let cover {
                    ArtworkView(artwork: cover, cornerRadius: 8, elevation: .standard)
                        .frame(width: side * 0.57, height: side * 0.57)
                        .rotationEffect(.degrees(hovering ? 22 : 16), anchor: .center)
                        .offset(x: side * 0.5, y: side * 0.5)
                } else {
                    Image(systemName: mood.symbol)
                        .font(.system(size: side * 0.46, weight: .bold))
                        .foregroundStyle(.white.opacity(hovering ? 0.34 : 0.24))
                        .rotationEffect(.degrees(hovering ? -6 : -14))
                        .frame(width: side, height: side, alignment: .bottomTrailing)
                        .offset(x: side * 0.08, y: side * 0.06)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(mood.title)
                        .font(.system(size: side * 0.125, weight: .heavy))
                        .tracking(-0.4)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 1)
                    Text("Radio")
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(Spacing.s16)
                status
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .padding(Spacing.s12)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .strokeBorder(.white.opacity(playing ? 0.85 : 0.08), lineWidth: playing ? 2 : 1)
            }
            .shadow(color: mood.colors[1].opacity(hovering ? 0.55 : 0.25), radius: hovering ? 18 : 10, y: hovering ? 10 : 5)
            .scaleEffect(hovering && !reduceMotion ? 1.035 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75), value: hovering)
        .accessibilityLabel(Text("\(mood.title) radio"))
    }

    /// 心情色：主色漸層＋兩團柔光（左上亮、右下深），比單純的線性漸層有層次
    private var background: some View {
        ZStack {
            LinearGradient(colors: mood.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.28), .clear], center: UnitPoint(x: 0.15, y: 0.1), startRadius: 0, endRadius: 140)
            RadialGradient(colors: [mood.colors[1].opacity(0.9), .clear], center: UnitPoint(x: 0.95, y: 1), startRadius: 0, endRadius: 150)
        }
    }

    /// 右上角：讀取中轉圈、播放中顯示電台、滑過時顯示播放
    @ViewBuilder
    private var status: some View {
        if loading {
            ProgressView().controlSize(.small).tint(.white)
        } else if playing {
            FinifyIcon(.radio, size: .compact).foregroundStyle(.white)
                .padding(6)
                .background(.black.opacity(0.25), in: Circle())
        } else {
            FinifyIcon(.play, weight: .filled, size: .compact)
                .foregroundStyle(mood.colors[1])
                .padding(8)
                .background(.white, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                .opacity(hovering ? 1 : 0)
                .scaleEffect(hovering ? 1 : 0.8)
        }
    }
}
