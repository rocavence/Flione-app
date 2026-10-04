import SwiftUI

/// 非同步資料的狀態。每個畫面都必須處理 loading / empty / error。
enum Loadable<Value> {
    case loading
    case loaded(Value)
    case failed
}

extension Loadable: Sendable where Value: Sendable {}

@MainActor @Observable
final class HomeViewModel {
    var recentlyPlayed: Loadable<[Album]> = .loading
    var recentlyAdded: Loadable<[Album]> = .loading
    var quickPicks: Loadable<[Album]> = .loading
    /// Hero 介紹的專輯：最近加入的 30 張裡隨機挑一張（每次載入首頁換一張）
    var heroAlbum: Album?

    func load(_ repository: (any MusicRepository)?) async {
        guard let repository else { return }
        async let played = Self.fetch { try await repository.recentlyPlayed(limit: 12) }
        async let added = Self.fetch { try await repository.recentlyAdded(limit: 30) }
        async let picks = Self.fetch { try await repository.quickPicks(limit: 12) }
        (recentlyPlayed, recentlyAdded, quickPicks) = await (played, added, picks)
        if case .loaded(let albums) = recentlyAdded {
            heroAlbum = albums.filter { $0.artwork != nil }.randomElement()
            // 「最近加入」那一排維持 16 張
            recentlyAdded = .loaded(Array(albums.prefix(16)))
        }
    }

    nonisolated private static func fetch(_ work: @Sendable () async throws -> [Album]) async -> Loadable<[Album]> {
        do { return .loaded(try await work()) } catch { return .failed }
    }
}

struct HomeView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(StandardRouter.self) private var router
    @State private var model = HomeViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s40) {
                HomeHero(greeting: greeting, album: heroAlbum)
                    .padding(.top, Spacing.s8)
                MoodShelf()

                if case .failed = model.recentlyAdded, case .failed = model.quickPicks {
                    MessageState(
                        title: "Can't reach your music server.",
                        message: "Your library will appear here as soon as the connection is back.",
                        icon: .wifiOff,
                        primary: ("Retry", { Task { await reload() } })
                    )
                } else {
                    shelf("Recently Played", model.recentlyPlayed, empty: "Albums you play will show up here.")
                    shelf("Recently Added", model.recentlyAdded, empty: "New albums on your server will show up here.")
                    shelf("Quick Picks", model.quickPicks, empty: nil, refresh: { Task { await reloadPicks() } })
                }
            }
            .padding(.horizontal, Spacing.s32)
            .padding(.bottom, Spacing.s48)
        }
        .task {
            await model.load(app.repository)
            #if DEBUG || BENCHMARK
            LaunchMark.record("homeLoaded")
            #endif
        }
        .onChange(of: app.reconnectCount) { Task { await reload() } }
    }

    /// Hero 介紹的專輯（最近加入的 30 張隨機一張，見 HomeViewModel）
    private var heroAlbum: Album? { model.heroAlbum }

    private var greeting: LocalizedStringResource {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        case 18..<23: "Good evening"
        default: "Late night listening"
        }
    }

    private func reload() async {
        model.recentlyPlayed = .loading
        model.recentlyAdded = .loading
        model.quickPicks = .loading
        await model.load(app.repository)
    }

    private func reloadPicks() async {
        guard let repository = app.repository else { return }
        if let picks = try? await repository.quickPicks(limit: 12) {
            withAnimation(Motion.ui) { model.quickPicks = .loaded(picks) }
        }
    }

    @ViewBuilder
    private func shelf(_ title: LocalizedStringResource, _ state: Loadable<[Album]>, empty: LocalizedStringResource?, refresh: (() -> Void)? = nil) -> some View {
        switch state {
        case .loaded(let albums) where albums.isEmpty:
            if let empty {
                VStack(alignment: .leading, spacing: Spacing.s16) {
                    SectionHeader(title: title)
                    Text(empty).flioneFont(.body).foregroundStyle(FlioneColor.muted)
                }
            }
        case .failed:
            EmptyView()
        default:
            AlbumShelf(title: title, state: state, action: refresh.map { ("Shuffle picks", $0) }, actionIcon: .refresh)
        }
    }
}

/// 一列可橫向捲動的專輯。標題右側的箭頭讓沒有觸控板的使用者也能翻頁。
struct AlbumShelf: View {
    let title: LocalizedStringResource
    let state: Loadable<[Album]>
    var action: (title: LocalizedStringResource, run: () -> Void)?
    /// 動作前的圖示：「重新推薦」用重新整理，「顯示全部」不需要
    var actionIcon: Reicon?
    var cardWidth: CGFloat = 168
    @Environment(AppEnvironment.self) private var app
    @Environment(StandardRouter.self) private var router
    @State private var firstVisible = 0
    @State private var visibleCount = 6

    private var albums: [Album] {
        if case .loaded(let albums) = state { return albums }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            // 置中對齊：左右箭頭沒有文字基線，用基線對齊會和「重新推薦」上下錯開
            HStack(alignment: .center) {
                SectionHeader(title: title, action: action, actionIcon: actionIcon)
                if albums.count > visibleCount {
                    HStack(spacing: Spacing.s4) {
                        FlioneIconButton(icon: .chevronLeft, label: "Scroll \(title) left", size: .compact) { page(-1) }
                            .disabled(firstVisible == 0)
                        FlioneIconButton(icon: .chevronRight, label: "Scroll \(title) right", size: .compact) { page(1) }
                            .disabled(firstVisible + visibleCount >= albums.count)
                    }
                }
            }
            ScrollViewReader { proxy in
                shelf
                    .onChange(of: firstVisible) {
                        guard albums.indices.contains(firstVisible) else { return }
                        withAnimation(Motion.ui) { proxy.scrollTo(albums[firstVisible].id, anchor: .leading) }
                    }
            }
            .background(GeometryReader { geo in
                Color.clear.onAppear { visibleCount = max(1, Int(geo.size.width / (cardWidth + Spacing.s20))) }
                    .onChange(of: geo.size.width) { visibleCount = max(1, Int(geo.size.width / (cardWidth + Spacing.s20))) }
            })
        }
    }

    private func page(_ direction: Int) {
        firstVisible = min(max(0, firstVisible + direction * visibleCount), max(0, albums.count - visibleCount))
    }

    private var shelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: Spacing.s20) {
                switch state {
                case .loaded(let albums):
                    ForEach(albums) { album in
                        AlbumCard(album: album, onOpen: { router.openAlbum(album) }, onPlay: { play(album) })
                            .frame(width: cardWidth)
                    }
                default:
                    ForEach(0..<7, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: Spacing.s8) {
                            SkeletonBlock().aspectRatio(1, contentMode: .fit)
                            SkeletonBlock().frame(width: 120, height: 10)
                            SkeletonBlock().frame(width: 80, height: 8)
                        }
                        .frame(width: cardWidth)
                    }
                }
            }
            .padding(.vertical, Spacing.s8)
        }
        .scrollClipDisabled()
    }

    private func play(_ album: Album) {
        app.player.play(album: album)
    }
}

/// 首頁 Hero：最新加入專輯的封面模糊成背景，疊上 Finity Aurora 漸層；Play 播放這張，Shuffle 隨機播放整個音樂庫
private struct HomeHero: View {
    let greeting: LocalizedStringResource
    let album: Album?
    @Environment(AppEnvironment.self) private var app
    @Environment(StandardRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            background
            HStack(alignment: .center, spacing: Spacing.s32) {
                VStack(alignment: .leading, spacing: Spacing.s12) {
                    Text(greeting)
                        .textCase(.uppercase)
                        .flioneFont(.micro)
                        .foregroundStyle(FlioneColor.ice.opacity(0.85))
                    Text("Listen well. Collect well.")
                        .font(.system(size: 36, weight: .bold))
                        .tracking(-0.8)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(subtitle)
                        .flioneFont(.body)
                        .foregroundStyle(FlioneColor.ice.opacity(0.85))
                        .lineLimit(2)
                        .frame(maxWidth: 380, alignment: .leading)
                    HStack(spacing: Spacing.s8) {
                        HeroButton(title: "Play", icon: .play, prominent: true) { playAlbum() }
                            .disabled(album == nil)
                        HeroButton(title: "Shuffle", icon: .shuffle, prominent: false) { shuffleLibrary() }
                    }
                    .padding(.top, Spacing.s8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                if let album {
                    ArtworkView(artwork: album.artwork, elevation: .playing)
                        .frame(width: 160, height: 160)
                        .onTapGesture { router.openAlbum(album) }
                        .accessibilityLabel("Open \(album.name)")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .padding(Spacing.s32)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Radius.hero, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1) }
        .flioneShadow(FlioneShadow.elevated)
        .environment(\.colorScheme, .dark)
    }

    private var subtitle: LocalizedStringResource {
        let count = app.library.albums.count
        guard let server = app.session?.serverName else { return "\(count) albums, ready when you are." }
        guard let album else { return "\(count) albums on \(server), ready when you are." }
        return "New on \(server): \(album.name) by \(album.artistName)."
    }

    private var background: some View {
        ZStack {
            FlioneColor.aurora
            if let artwork = album?.artwork {
                HeroBackdrop(artwork: artwork)
                    .id(artwork)
                    .transition(.opacity)
            }
            // 左側壓暗，讓文字清楚
            LinearGradient(colors: [FlioneColor.Ocean.abyss.opacity(0.75), FlioneColor.Ocean.abyss.opacity(0.15)], startPoint: .leading, endPoint: .trailing)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: album?.artwork)
        .drawingGroup()
        .accessibilityHidden(true)
    }

    private func playAlbum() {
        guard let album else { return }
        app.player.play(album: album)
    }

    private func shuffleLibrary() {
        Task {
            guard let tracks = try? await app.repository?.randomTracks(limit: 200), !tracks.isEmpty else { return }
            app.player.play(tracks)
        }
    }
}

/// Hero 背景的模糊封面：直接向封面快取要圖，填滿整條 Hero。
/// 不用 ArtworkView：它維持正方形，載入前的佔位方塊模糊後會在 Hero 中間留下一塊硬邊色塊。載入前不畫，只有極光漸層
private struct HeroBackdrop: View {
    let artwork: ArtworkRef
    @Environment(AppEnvironment.self) private var app
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .blur(radius: 60, opaque: true)
                    // 封面的顏色主導整條 Hero（極光漸層只在封面載入前出現）；稍微提高飽和、壓暗，讓白字清楚
                    .saturation(1.25)
                    .brightness(-0.12)
                    .transition(.opacity)
            }
        }
        .task(id: artwork) {
            // 模糊 60 之後解析度看不出差別，720px 就夠
            image = await app.images?.image(artwork, pixelSize: 720)
        }
    }
}

/// Hero 上的按鈕：Play 為白底膠囊，Shuffle 為半透明玻璃
private struct HeroButton: View {
    let title: LocalizedStringResource
    let icon: Reicon
    let prominent: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s8) {
                FlioneIcon(icon, weight: .filled, size: .compact)
                Text(title).flioneFont(.bodyEmphasis)
            }
            .fixedSize()
            .foregroundStyle(prominent ? FlioneColor.Ocean.surface1 : .white)
            .padding(.horizontal, Spacing.s20)
            .frame(height: 38)
            .modifier(HeroButtonBackground(prominent: prominent, hovering: hovering))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
    }
}

/// Play 是實心冰白膠囊；Shuffle 在 macOS 26 以上是 Liquid Glass，舊系統是半透明白
private struct HeroButtonBackground: ViewModifier {
    let prominent: Bool
    let hovering: Bool

    func body(content: Content) -> some View {
        if prominent {
            content.background(FlioneColor.ice.opacity(hovering ? 0.9 : 1), in: Capsule())
        } else {
            content.flioneGlass(in: Capsule(), interactive: true, fallback: .white.opacity(hovering ? 0.22 : 0.14))
        }
    }
}
