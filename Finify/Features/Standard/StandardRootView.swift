import SwiftUI

/// Standard mode：每天使用的完整音樂 App。
/// 版面（Finity 設計）：左側導覽、中間內容（頂部有上一頁／下一頁與搜尋）、右側 Now Playing 面板、底部播放列。
struct StandardRootView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var router = StandardRouter()
    /// 使用者是否想看到右側 Now Playing 面板（記住上次的選擇）
    @AppStorage("FinifyNowPlayingPanel") private var wantsPanel = true

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
                .background(FinifyColor.paper)
                if panelVisible {
                    NowPlayingPanel(onOpenAlbum: openAlbum(id:), onOpenArtist: { router.openArtist(id: $0, name: $1) })
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(Motion.respecting(reduceMotion, Motion.ui), value: panelVisible)
            PlayerBar(onOpenAlbum: openAlbum(id:), onOpenArtist: { router.openArtist(id: $0, name: $1) })
        }
        .overlay {
            if app.isSearchPresented {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { app.isSearchPresented = false }
                    SearchPalette(onOpenAlbum: { router.openAlbum($0) }, onOpenArtist: { router.openArtist(id: $0.id, name: $0.name) },
                                  onOpenPlaylist: { router.open(.playlist($0)) })
                        .padding(.top, 80)
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.respecting(reduceMotion, Motion.micro), value: app.isSearchPresented)
        .background(FinifyColor.paper)
        .environment(router)
        .task { await app.library.refreshIfNeeded() }
        .onAppear { if wantsPanel && !panelVisible { app.isQueuePresented = true } }
        // 只在 Standard 裡記住面板開關（切到 Overflow 時旗標會被清掉，不算使用者的選擇）
        .onChange(of: panelVisible) { if app.mode == .standard { wantsPanel = panelVisible } }
        .onChange(of: app.requestedAlbumID, initial: true) {
            guard let id = app.requestedAlbumID else { return }
            app.requestedAlbumID = nil
            openAlbum(id: id)
        }
        #if DEBUG || BENCHMARK
        .task {
            if UserDefaults.standard.string(forKey: "FinifyDemoTab") == "library" {
                let raw = UserDefaults.standard.string(forKey: "FinifyDemoSection") ?? "Albums"
                router.tab = .library(LibrarySection(rawValue: raw) ?? .albums)
            }
            await DebugDemo.run(app: app, openAlbum: { router.openAlbum($0) })
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
                .background(FinifyColor.paper)
            }
        }
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: router.path)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            ModeSwitch()
        }
        .padding(.horizontal, Spacing.s20)
        .frame(height: 56)
    }
}

/// 上一頁／下一頁的圓形按鈕
private struct CircleNavButton: View {
    let icon: Reicon
    let label: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            FinifyIcon(icon, size: .compact)
                .foregroundStyle(FinifyColor.ink)
                .frame(width: 30, height: 30)
                .background(hovering ? FinifyColor.glassHighlight : FinifyColor.glass, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
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
                FinifyIcon(.search, size: .compact)
                Text("Search your music")
                    .finifyFont(.body)
                Spacer()
                Text("⌘K")
                    .finifyFont(.caption)
                    .foregroundStyle(overflow ? FinifyColor.Overflow.faint : FinifyColor.faint)
            }
            .foregroundStyle(overflow ? FinifyColor.Overflow.muted : FinifyColor.muted)
            .padding(.horizontal, Spacing.s16)
            .frame(height: 34)
            .background(background, in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .accessibilityLabel("Search")
    }

    private var background: Color {
        if overflow { return hovering ? FinifyColor.Overflow.controlHover : FinifyColor.Overflow.control }
        return hovering ? FinifyColor.glassHighlight : FinifyColor.glass
    }
}

/// Standard ↔ Overflow 切換
struct ModeSwitch: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.overflowStyle) private var overflow

    var body: some View {
        HStack(spacing: 2) {
            segment(.standard, icon: .menu, label: "Standard")
            segment(.overflow, icon: .grid, label: "Overflow")
        }
        .padding(2)
        .background(overflow ? FinifyColor.Overflow.control : FinifyColor.surface, in: RoundedRectangle(cornerRadius: Radius.ui + 2, style: .continuous))
    }

    private func segment(_ mode: AppMode, icon: Reicon, label: String) -> some View {
        let selected = app.mode == mode
        return Button { app.mode = mode } label: {
            FinifyIcon(icon, weight: selected ? .filled : .outline, size: .compact)
                .frame(width: 32, height: 26)
                .foregroundStyle(selected ? (overflow ? FinifyColor.Overflow.background : FinifyColor.onPrimary) : (overflow ? FinifyColor.Overflow.muted : FinifyColor.muted))
                .background(selected ? (overflow ? FinifyColor.Overflow.ink : FinifyColor.primary) : .clear, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(label) (\(mode == .standard ? "⌘1" : "⌘2"))")
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
