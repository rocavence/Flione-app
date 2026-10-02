import SwiftUI

/// Standard mode：每天使用的完整音樂 App。
/// 版面：頂部導覽列（不用通用 sidebar，D07）＋內容＋底部 mini player；queue 從右側滑出。
struct StandardRootView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var router = StandardRouter()

    var body: some View {
        VStack(spacing: 0) {
            StandardTopBar(router: router)
            ZStack(alignment: .trailing) {
                content
                if app.isQueuePresented {
                    QueuePanel(onOpenAlbum: openAlbum(id:))
                        .frame(width: 340)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                if app.isLyricsPresented {
                    LyricsPanel()
                        .frame(width: 380)
                        .overlay(alignment: .leading) { FinifyColor.hairline.frame(width: 1) }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(Motion.respecting(reduceMotion, Motion.ui), value: app.isQueuePresented)
            .animation(Motion.respecting(reduceMotion, Motion.ui), value: app.isLyricsPresented)
            PlayerBar(onOpenAlbum: openAlbum(id:), onOpenArtist: { router.openArtist(id: $0, name: $1) })
        }
        .overlay {
            if app.isSearchPresented {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.25).ignoresSafeArea().onTapGesture { app.isSearchPresented = false }
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
        #if DEBUG || BENCHMARK
        .task {
            if UserDefaults.standard.string(forKey: "FinifyDemoTab") == "library" { router.tab = .library }
            await DebugDemo.run(app: app, openAlbum: { router.openAlbum($0) })
        }
        #endif
    }

    private var content: some View {
        ZStack {
            // tab 根畫面常駐，返回時保留捲動位置
            HomeView()
                .opacity(router.tab == .home && router.path.isEmpty ? 1 : 0)
                .allowsHitTesting(router.tab == .home && router.path.isEmpty)
            LibraryView()
                .opacity(router.tab == .library && router.path.isEmpty ? 1 : 0)
                .allowsHitTesting(router.tab == .library && router.path.isEmpty)
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
        HStack(spacing: Spacing.s16) {
            // 左側留給視窗紅綠燈
            Color.clear.frame(width: 64)
            FinifyIconButton(icon: .chevronLeft, label: "Back") { router.back() }
                .disabled(!router.canGoBack)
                .keyboardShortcut("[", modifiers: .command)
            HStack(spacing: Spacing.s4) {
                ForEach(StandardTab.allCases, id: \.self) { tab in
                    TabButton(title: tab.rawValue, isSelected: router.tab == tab) {
                        if router.tab == tab { while router.canGoBack { router.back() } } else { router.tab = tab }
                    }
                }
            }
            Spacer(minLength: Spacing.s16)
            SearchTrigger { app.isSearchPresented = true }
                .frame(maxWidth: 360)
            Spacer(minLength: Spacing.s16)
            ModeSwitch()
        }
        .padding(.horizontal, Spacing.s16)
        .frame(height: 52)
        .background(FinifyColor.paper)
        .overlay(alignment: .bottom) { FinifyColor.hairline.frame(height: 1) }
    }
}

private struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .finifyFont(.bodyEmphasis)
                .foregroundStyle(isSelected ? FinifyColor.ink : (hovering ? FinifyColor.ink : FinifyColor.muted))
                .padding(.horizontal, Spacing.s12)
                .frame(height: 30)
                .background(isSelected ? FinifyColor.surface : .clear, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            .padding(.horizontal, Spacing.s12)
            .frame(height: 32)
            .background(background, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .accessibilityLabel("Search")
    }

    private var background: Color {
        if overflow { return hovering ? FinifyColor.Overflow.controlHover : FinifyColor.Overflow.control }
        return hovering ? FinifyColor.hairline : FinifyColor.surface
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
