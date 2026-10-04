import SwiftUI

/// Standard mode：每天使用的完整音樂 App。
/// 版面（Finity 設計）：左側導覽、中間內容（頂部有上一頁／下一頁與搜尋）、右側 Now Playing 面板、底部播放列。
struct StandardRootView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var router = StandardRouter()
    @AppStorage(SettingsKey.textComfort) private var comfort = TextComfort.standard
    /// 使用者是否想看到右側 Now Playing 面板（記住上次的選擇）

    private var panelVisible: Bool { app.isQueuePresented || app.isLyricsPresented }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                StandardSidebar()
                VStack(spacing: 0) {
                    StandardTopBar(router: router)
                    content
                }
                // 中間欄吃掉剩餘寬度，不讓子視圖把側欄和面板擠出視窗
                .frame(minWidth: 0, maxWidth: .infinity)
                .clipped()
            }
            // 光暈鋪在側欄與內容底下：側欄是半透明的，底色跟著內容頁變（與 Kaset 相同）
            .background(ContentGlow(artwork: glowArtwork))
            // 佇列與歌詞：與 Infinity／Cover Flow 相同的浮層，浮在內容右側
            .overlay(alignment: .trailing) {
                if panelVisible {
                    PlayerSidePanel(onOpenAlbum: openAlbum(id:))
                        .padding(.top, ViewControls.barHeight + Spacing.s8)
                        .padding(.bottom, Spacing.s16)
                        .padding(.trailing, Spacing.s16)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(Motion.respecting(reduceMotion, Motion.ui), value: panelVisible)
            PlayerBar(onOpenAlbum: openAlbum(id:), onOpenArtist: { router.openArtist(id: $0, name: $1) })
        }
        // 睫狀肌舒適：側欄、內容、佇列與歌詞、播放列的文字放大；右上角控制與搜尋維持原尺寸
        .environment(\.flioneTextScale, comfort.scale)
        // 模式切換固定在視窗右上角，位置與 Infinity／Cover Flow 完全相同
        .overlay(alignment: .topTrailing) { ViewControls() }
        .overlay {
            if app.isSearchPresented {
                SearchOverlay(onOpenAlbum: { router.openAlbum($0) }, onOpenArtist: { router.openArtist(id: $0.id, name: $0.name) },
                              onOpenPlaylist: { router.open(.playlist($0)) })
            }
        }
        .animation(Motion.respecting(reduceMotion, Motion.micro), value: app.isSearchPresented)
        .background(FlioneColor.paper)
        .environment(router)
        .task { await app.library.refreshIfNeeded() }
        .onChange(of: app.requestedAlbumID, initial: true) {
            guard let id = app.requestedAlbumID else { return }
            app.requestedAlbumID = nil
            openAlbum(id: id)
        }
        #if DEBUG || BENCHMARK
        .task {
            // -FlioneDemoDiscover "<需求>"：打開探索並送出（DiscoverView 讀取）
            if UserDefaults.standard.string(forKey: "FlioneDemoDiscover") != nil { router.tab = .discover }
            if UserDefaults.standard.string(forKey: "FlioneDemoTab") == "library" {
                let raw = UserDefaults.standard.string(forKey: "FlioneDemoSection") ?? "Albums"
                router.tab = .library(LibrarySection(rawValue: raw) ?? .albums)
            }
            await DebugDemo.run(app: app, openAlbum: { router.openAlbum($0) })
            // -FlioneDemoArtist "<藝人名>"：打開該藝人頁（驗證專輯排序）
            if let name = UserDefaults.standard.string(forKey: "FlioneDemoArtist") {
                for _ in 0..<100 where app.library.albums.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
                if let album = app.library.albums.first(where: { $0.artistName.localizedCaseInsensitiveContains(name) && $0.artistID != nil }) {
                    router.openArtist(id: album.artistID, name: album.artistName)
                }
            }
        }
        #endif
    }

    private var content: some View {
        ZStack {
            // 首頁常駐，返回時保留捲動位置
            HomeView()
                .opacity(router.tab == .home && router.path.isEmpty ? 1 : 0)
                .allowsHitTesting(router.tab == .home && router.path.isEmpty)
            Group {
                switch router.tab {
                case .home: EmptyView()
                case .library(let section): LibraryView(section: section).id(section)
                case .recentlyAdded: LibraryView(section: .albums, title: "Recently Added", sort: .recentlyAdded).id("recent")
                case .discover: DiscoverView()
                }
            }
            .opacity(router.path.isEmpty ? 1 : 0)
            .allowsHitTesting(router.path.isEmpty)
            if let route = router.path.last {
                Group {
                    switch route {
                    case .album(let album): AlbumView(album: album)
                    case .artist(let id, let name): ArtistView(artistID: id, name: name)
                    case .playlist(let playlist): PlaylistView(playlist: playlist)
                    case .genre(let genre): GenreView(genre: genre)
                    }
                }
                .id(route)
                .transition(.opacity)
            }
        }
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: router.path)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 背景光暈只在專輯與 playlist 頁，用該頁封面（與 Kaset 相同）。
    /// 首頁等其他頁不上色：正在播放的封面若偏灰，整片底色會變髒，也和首頁 Hero 衝突
    private var glowArtwork: ArtworkRef? {
        switch router.path.last {
        case .album(let album): album.artwork
        case .playlist(let playlist): playlist.artwork
        default: nil
        }
    }

    private func openAlbum(id: String?) {
        guard let id else { return }
        if let album = app.library.albums.first(where: { $0.id == id }) {
            router.openAlbum(album)
            return
        }
        Task {
            if let album = try? await app.repository?.album(id: id) { router.openAlbum(album) }
        }
    }
}

private struct StandardTopBar: View {
    let router: StandardRouter
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(spacing: Spacing.s12) {
            HStack(spacing: Spacing.s4) {
                CircleNavButton(icon: .chevronLeft, label: "Back") { router.back() }
                    .disabled(!router.canGoBack)
                    .keyboardShortcut("[", modifiers: .command)
                CircleNavButton(icon: .chevronRight, label: "Forward") { router.goForward() }
                    .disabled(!router.canGoForward)
                    .keyboardShortcut("]", modifiers: .command)
            }
            Spacer(minLength: Spacing.s16)
            SearchTrigger { app.isSearchPresented = true }
                .frame(maxWidth: 400)
            Spacer(minLength: Spacing.s16)
            // 模式切換浮在這一列的右端（ViewControls），留位置給它
            Color.clear.frame(width: ViewControls.width)
        }
        .padding(.horizontal, Spacing.s16)
        .frame(height: ViewControls.barHeight)
    }
}

/// 上一頁／下一頁的圓形按鈕
private struct CircleNavButton: View {
    let icon: Reicon
    let label: LocalizedStringResource
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            FlioneIcon(icon, size: .compact)
                .foregroundStyle(FlioneColor.ink)
                .frame(width: ViewControls.controlHeight, height: ViewControls.controlHeight)
                .modifier(TopBarSurface(overflow: false, shape: Circle(), fallback: hovering ? FlioneColor.glassHighlight : FlioneColor.glass, interactive: false))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}

/// 頂部的搜尋入口；實際搜尋在 ⌘K 面板
struct SearchTrigger: View {
    let action: () -> Void
    @Environment(\.overflowStyle) private var overflow
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s8) {
                FlioneIcon(.search, size: .compact)
                Text("Search your music")
                    .flioneFont(.body)
                    .lineLimit(1)
                Spacer()
                Text("⌘K")
                    .flioneFont(.caption)
                    .foregroundStyle(overflow ? FlioneColor.Overflow.faint : FlioneColor.faint)
            }
            .foregroundStyle(overflow ? FlioneColor.Overflow.muted : FlioneColor.muted)
            .padding(.horizontal, Spacing.s16)
            .frame(height: ViewControls.controlHeight)
            .modifier(TopBarSurface(overflow: overflow, shape: Capsule(), fallback: background))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .accessibilityLabel("Search")
    }

    private var background: Color {
        if overflow { return hovering ? FlioneColor.Overflow.controlHover : FlioneColor.Overflow.control }
        return hovering ? FlioneColor.glassHighlight : FlioneColor.glass
    }
}

/// Standard ↔ Overflow 切換
struct ModeSwitch: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.overflowStyle) private var overflow

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ViewMode.allCases, id: \.self) { segment($0) }
        }
        .padding(3)
        // 與搜尋框相同的膠囊外形；Infinity／Cover Flow 浮在封面上，用 Liquid Glass
        .modifier(TopBarSurface(overflow: overflow, shape: Capsule(), fallback: overflow ? FlioneColor.Overflow.control : FlioneColor.surface))
    }

    private func segment(_ mode: ViewMode) -> some View {
        let selected = app.viewMode == mode
        return Button { app.viewMode = mode } label: {
            FlioneIcon(mode.icon, weight: selected ? .filled : .outline, size: .standard)
                .frame(width: 42, height: 32)
                .foregroundStyle(selected ? (overflow ? FlioneColor.Overflow.background : FlioneColor.onPrimary) : (overflow ? FlioneColor.Overflow.muted : FlioneColor.muted))
                .background(selected ? (overflow ? FlioneColor.Overflow.ink : FlioneColor.primary) : .clear, in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(mode.title) (⌘\(mode.shortcut))")
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 右上角的模式切換。三種模式共用，位置固定在視窗右上角（全螢幕在「視窗」選單）
struct ViewControls: View {
    /// 頂部列高度，Standard 與 Infinity／Cover Flow 相同
    /// 頂部列所有控制項的高度（模式切換、全螢幕、搜尋、上一頁／下一頁、Infinity 的排序等）
    static let controlHeight: CGFloat = 38
    /// 頂部列高度：控制項上下各留 11pt（原本上一頁按鈕到邊緣的距離）
    static let barHeight: CGFloat = controlHeight + 22
    /// 三段切換（3 × 42 + 6）
    static let width: CGFloat = 132

    var body: some View {
        ModeSwitch()
        .frame(height: Self.barHeight)
        .padding(.trailing, Spacing.s16)
    }
}

/// 頂部控制的底：macOS 26 以上一律用 Liquid Glass（像系統工具列按鈕），舊系統用原本的色塊。
/// Infinity／Cover Flow 浮在封面上，帶深藍色調；Standard 帶目前主題的表面色，淺色模式也自然。
struct TopBarSurface<S: InsettableShape>: ViewModifier {
    let overflow: Bool
    let shape: S
    let fallback: Color
    var strokeFallback = true
    /// 系統玻璃的互動變形（滑鼠靠近或按下時鼓起）。小圓按鈕關掉，否則會被拉成直的橢圓
    var interactive = true

    func body(content: Content) -> some View {
        content.flioneGlass(in: shape, tint: overflow ? FlioneColor.Ocean.surface2.opacity(0.45) : FlioneColor.surface.opacity(0.5),
                            interactive: interactive, fallback: fallback)
    }
}
