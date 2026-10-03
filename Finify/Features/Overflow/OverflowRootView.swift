import AppKit
import SwiftUI

enum OverflowLayout: String, CaseIterable {
    case wall = "Wall"
    case flow = "Flow"
    /// 最近播放的專輯牆
    case recent = "Recent"
}

/// Overflow mode：讓音樂庫成為畫面本身。完整的 App mode，可瀏覽、搜尋、播放、排佇列，不需離開。
struct OverflowRootView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("FinifyOverflowLayout") private var layout: OverflowLayout = .wall
    @AppStorage("FinifyWallDensity") private var densityRaw = WallDensity.medium.rawValue
    @AppStorage("FinifyWallSort") private var sort: AlbumSort = .artist
    @AppStorage("FinifyFlowSize") private var flowSize = 3
    /// 排序結果只在專輯清單或排序方式改變時重算
    @State private var sortedAlbums: [Album] = []
    @State private var openAlbum: Album?
    @State private var immersive = false
    @State private var scrollToPlaying = 0
    @State private var browseWidth: CGFloat = 1360
    @State private var recentAlbums: Loadable<[Album]> = .loading

    private var density: Binding<WallDensity> {
        Binding { WallDensity(rawValue: densityRaw) ?? .medium } set: { densityRaw = $0.rawValue }
    }

    private var playingAlbumID: String? { app.player.currentTrack?.albumID }

    var body: some View {
        ZStack {
            AmbientBackground(artwork: app.player.currentTrack?.artwork)
            if immersive {
                ImmersiveView(onExit: exitImmersive)
                    .transition(.opacity)
            } else {
                browse
                    .transition(.opacity)
            }
        }
        .environment(\.overflowStyle, true)
        .environment(\.colorScheme, .dark)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { browseWidth = $0 }
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: immersive)
        .onChange(of: immersive, initial: true) { app.isImmersive = immersive }
        .onDisappear { app.isImmersive = false }
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: openAlbum)
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: app.isQueuePresented)
        .task { await app.library.refreshIfNeeded() }
        .onChange(of: app.library.albums, initial: true) { sortedAlbums = sort.apply(to: app.library.albums) }
        .onChange(of: sort) { sortedAlbums = sort.apply(to: app.library.albums) }
        // 最近播放：切到 Recent 或換曲時更新
        .task(id: layout == .recent ? (playingAlbumID ?? "") + "recent" : "") {
            guard layout == .recent, let repository = app.repository else { return }
            do { recentAlbums = .loaded(try await repository.recentlyPlayed(limit: 120)) } catch {
                if case .loading = recentAlbums { recentAlbums = .failed }
            }
        }
        #if DEBUG || BENCHMARK
        .task { await DebugDemo.run(app: app, openAlbum: { openAlbum = $0 }, immersive: enterImmersive) }
        #endif
        .onChange(of: app.requestedAlbumID, initial: true) {
            guard let id = app.requestedAlbumID else { return }
            app.requestedAlbumID = nil
            if let album = app.library.albums.first(where: { $0.id == id }) {
                openAlbum = album
            } else {
                Task { if let album = try? await app.repository?.album(id: id) { openAlbum = album } }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            if immersive { exitImmersive() }
        }
        .onChange(of: app.isFullscreenRequested, initial: true) {
            guard app.isFullscreenRequested else { return }
            app.isFullscreenRequested = false
            enterImmersive()
        }
    }

    private var browse: some View {
        ZStack {
            Group {
                if app.library.albums.isEmpty {
                    emptyOrLoading
                } else {
                    switch layout {
                    case .wall:
                        AlbumWallView(
                            albums: sortedAlbums,
                            density: density,
                            playingAlbumID: playingAlbumID,
                            images: app.images,
                            onOpen: { openAlbum = $0 },
                            onPlay: play,
                            onQueue: queue,
                            extraMenu: app.albumMenuItems,
                            scrollToPlayingToken: scrollToPlaying,
                            acceptsKeyboard: openAlbum == nil && !app.isSearchPresented,
                            typeToSelectByTitle: sort == .title
                        )
                    case .recent:
                        switch recentAlbums {
                        case .loading:
                            Color.clear
                        case .failed:
                            MessageState(title: "Can't load recently played.", message: "Check your connection to the music server.", icon: .wifiOff)
                        case .loaded(let list) where list.isEmpty:
                            MessageState(title: "Nothing played yet.", message: "Albums you play will fill this wall.", icon: .history)
                        case .loaded(let list):
                            // 最近播放通常只有幾十張，固定用大尺寸，畫面才不會空
                            AlbumWallView(
                                albums: list,
                                density: .constant(.large),
                                playingAlbumID: playingAlbumID,
                                images: app.images,
                                onOpen: { openAlbum = $0 },
                                onPlay: play,
                                onQueue: queue
                            )
                        }
                    case .flow:
                        AlbumFlowView(albums: sortedAlbums, playingAlbumID: playingAlbumID, onPlay: play,
                                      isActive: openAlbum == nil && !app.isSearchPresented && !app.isQueuePresented,
                                      centerOnPlayingToken: scrollToPlaying,
                                      sizeStep: flowSize)
                    }
                }
            }
            .opacity(openAlbum == nil ? 1 : 0.25)
            .allowsHitTesting(openAlbum == nil)

            VStack(spacing: 0) {
                topBar
                Spacer()
                if openAlbum == nil { NowPlayingPill(onOpen: openPlayingAlbum, onImmersive: enterImmersive) }
            }

            // 右下角：Flow 的封面大小滑桿、回到正在播放的專輯（封面牆與 Album Flow）
            if openAlbum == nil, layout != .recent {
                VStack {
                    Spacer()
                    HStack(spacing: Spacing.s12) {
                        Spacer()
                        if layout == .flow { FlowSizeSlider(step: $flowSize) }
                        if playingAlbumID != nil {
                        Button { scrollToPlaying += 1 } label: {
                            FinifyIcon(.gps, weight: .filled, size: .standard)
                                .foregroundStyle(FinifyColor.Overflow.ink)
                                .frame(width: 44, height: 44)
                                .finifyGlass(in: Circle(), tint: Color(hex: 0x111D40).opacity(0.5), interactive: true, fallback: Color(hex: 0x111D40).opacity(0.88))
                                .finifyShadow(FinifyShadow.Style(color: .black.opacity(0.5), radius: 16, y: 6))
                        }
                        .buttonStyle(PressScaleStyle())
                        .help("Show what's playing")
                        .accessibilityLabel("Show what's playing")
                        }
                    }
                    .padding(.trailing, Spacing.s24)
                    // 視窗窄時，右下角控制項會壓到置中的播放列，改放到播放列上方
                    .padding(.bottom, browseWidth < 1300 ? 104 : Spacing.s32)
                }
                .transition(.opacity)
            }

            if let album = openAlbum {
                Color.black.opacity(0.45)
                    .onTapGesture { openAlbum = nil }
                OverflowAlbumPanel(album: album, onClose: { openAlbum = nil }, onOpenAlbum: { openAlbum = $0 })
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .onExitCommand { openAlbum = nil }
            }

            if app.isQueuePresented {
                HStack {
                    Spacer()
                    OverflowQueue(onOpenAlbum: { id in openAlbum = app.library.albums.first { $0.id == id } })
                        .padding(.top, 60)
                        .padding(.bottom, 108)
                        .padding(.trailing, Spacing.s16)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if app.isSearchPresented {
                searchOverlay
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: Spacing.s12) {
            Color.clear.frame(width: 64)
            HStack(spacing: 2) {
                ForEach(OverflowLayout.allCases, id: \.self) { item in
                    Button(item.rawValue) { layout = item }
                        .buttonStyle(.plain)
                        .finifyFont(.bodyEmphasis)
                        .foregroundStyle(layout == item ? FinifyColor.Overflow.background : FinifyColor.Overflow.muted)
                        .padding(.horizontal, Spacing.s12)
                        .frame(height: 26)
                        .background(layout == item ? FinifyColor.Overflow.ink : .clear, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
                        .accessibilityAddTraits(layout == item ? .isSelected : [])
                }
            }
            .padding(2)
            .finifyGlass(in: RoundedRectangle(cornerRadius: Radius.ui + 2, style: .continuous), tint: Color(hex: 0x111D40).opacity(0.4), fallback: FinifyColor.Overflow.control)

            if layout == .wall {
                HStack(spacing: 2) {
                    FinifyIconButton(icon: .minus, label: "Smaller albums", size: .compact) { stepDensity(-1) }
                        .disabled(density.wrappedValue == WallDensity.allCases.first)
                    Text(density.wrappedValue.label)
                        .finifyFont(.caption)
                        .foregroundStyle(FinifyColor.Overflow.muted)
                        .frame(width: 52)
                    FinifyIconButton(icon: .plus, label: "Larger albums", size: .compact) { stepDensity(1) }
                        .disabled(density.wrappedValue == WallDensity.allCases.last)
                }
                .help("Pinch to resize")
            }
            if layout != .recent {
                Menu {
                    Picker("Sort by", selection: $sort) {
                        ForEach(AlbumSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text("Sort: \(sort.rawValue)")
                        .finifyFont(.caption)
                        .foregroundStyle(FinifyColor.Overflow.muted)
                }
                .menuStyle(.borderlessButton)
                .tint(FinifyColor.Overflow.muted)
                .fixedSize()
                .accessibilityLabel("Sort albums, \(sort.rawValue)")
            }
            Spacer()
            SearchTrigger { app.isSearchPresented = true }
                .frame(width: 260)
            FinifyIconButton(icon: .fullscreen, label: "Fullscreen (⌃⌘F)", action: enterImmersive)
                .keyboardShortcut("f", modifiers: [.command, .control])
            ModeSwitch()
        }
        .padding(.horizontal, Spacing.s16)
        .frame(height: 52)
        .background(LinearGradient(colors: [Color(hex: 0x080D20).opacity(0.75), .clear], startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
    }

    @ViewBuilder
    private var emptyOrLoading: some View {
        if app.library.state == .failed {
            MessageState(title: "Can't reach your music server.", message: "Your library will appear as soon as the connection is back.",
                         icon: .wifiOff, primary: ("Retry", { Task { await app.library.refresh() } }))
        } else if app.library.state == .loaded {
            MessageState(title: "Your library is empty.", message: "Add music to your Jellyfin server and it will appear here.")
        } else {
            let columns = [GridItem(.adaptive(minimum: 148), spacing: 4)]
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<40, id: \.self) { _ in SkeletonBlock(cornerRadius: 2).aspectRatio(1, contentMode: .fit) }
            }
            .padding(.horizontal, 24)
            .padding(.top, 64)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var searchOverlay: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.45).onTapGesture { app.isSearchPresented = false }
            SearchPalette(onOpenAlbum: { openAlbum = $0 }, onOpenArtist: { artist in
                // Overflow 沒有藝人頁：開該藝人最新的專輯
                Task {
                    if let album = try? await app.repository?.albums(byArtist: artist.id).first { openAlbum = album }
                }
            })
            .padding(.top, 96)
        }
        .transition(.opacity)
    }

    private func stepDensity(_ delta: Int) {
        let next = WallDensity(rawValue: density.wrappedValue.rawValue + delta) ?? density.wrappedValue
        density.wrappedValue = next
    }

    private func play(_ album: Album) {
        Task {
            guard let tracks = try? await app.repository?.tracks(inAlbum: album.id) else { return }
            app.player.play(tracks)
        }
    }


    private func queue(_ album: Album, next: Bool) {
        Task {
            guard let tracks = try? await app.repository?.tracks(inAlbum: album.id) else { return }
            if next { app.player.playNext(tracks) } else { app.player.addToQueue(tracks) }
        }
    }

    private func openPlayingAlbum() {
        guard let id = playingAlbumID else { return }
        openAlbum = app.library.albums.first { $0.id == id }
    }

    private func enterImmersive() {
        immersive = true
        if let window = NSApp.keyWindow, !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
    }

    private func exitImmersive() {
        immersive = false
        if let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        // 從 Standard 進來的就回到 Standard
        if let previous = app.fullscreenReturnMode {
            app.fullscreenReturnMode = nil
            app.mode = previous
        }
    }
}

/// Overflow 底部浮動的 now playing：封面、曲名、控制、進度
private struct NowPlayingPill: View {
    let onOpen: () -> Void
    let onImmersive: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        if let track = app.player.currentTrack {
            HStack(spacing: Spacing.s16) {
                ArtworkView(artwork: track.artwork, cornerRadius: Radius.small, elevation: .none)
                    .frame(width: 44, height: 44)
                    .onTapGesture(perform: onOpen)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name).finifyFont(.bodyEmphasis).foregroundStyle(FinifyColor.Overflow.ink).lineLimit(1)
                    Text(track.artistName).finifyFont(.caption).foregroundStyle(FinifyColor.Overflow.muted).lineLimit(1)
                }
                .frame(width: 200, alignment: .leading)
                .onTapGesture(perform: onOpen)
                VStack(spacing: 2) {
                    PlaybackControls()
                    ProgressBar(value: app.player.progress) { app.player.seek(to: $0 * app.player.duration) }
                        .frame(width: 300)
                }
                FinifyIconButton(icon: .playlist, label: "Queue", isActive: app.isQueuePresented) { app.isQueuePresented.toggle() }
                VolumeControl()
            }
            .padding(.horizontal, Spacing.s16)
            .padding(.vertical, Spacing.s8)
            .finifyGlass(in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous), tint: Color(hex: 0x0D1633).opacity(0.55), fallback: Color(hex: 0x0D1633).opacity(0.88))
            .finifyShadow(FinifyShadow.Style(color: .black.opacity(0.5), radius: 30, y: 12))
            .padding(.bottom, Spacing.s24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Overflow 中的播放佇列：與 Standard 相同內容，浮在封面牆上方的深色面板
struct OverflowQueue: View {
    let onOpenAlbum: (String?) -> Void

    var body: some View {
        QueuePanel(onOpenAlbum: onOpenAlbum)
            .frame(width: 360)
            .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Radius.large, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1) }
            .finifyShadow(FinifyShadow.Style(color: .black.opacity(0.5), radius: 40, y: 16))
            // 佇列內的元件使用一般深色配色，不是 Overflow 的半透明樣式
            .environment(\.overflowStyle, false)
    }
}

/// Album Flow 的封面大小：6 段滑桿，拖動時即時縮放
private struct FlowSizeSlider: View {
    @Binding var step: Int

    var body: some View {
        HStack(spacing: Spacing.s8) {
            FinifyIcon(.cd, size: .compact).foregroundStyle(FinifyColor.Overflow.faint).scaleEffect(0.75)
            Slider(value: Binding(get: { Double(step) }, set: {
                       let next = Int($0.rounded())
                       if next != step { Haptics.perform(.step) }
                       step = next
                   }),
                   in: 0...Double(AlbumFlowView.sizeSteps - 1), step: 1)
                .controlSize(.small)
                .frame(width: 110)
                .tint(FinifyColor.Overflow.ink)
                .accessibilityLabel("Cover size")
                .accessibilityValue("\(step + 1) of \(AlbumFlowView.sizeSteps)")
            FinifyIcon(.cd, size: .compact).foregroundStyle(FinifyColor.Overflow.muted)
        }
        .padding(.horizontal, Spacing.s16)
        .frame(height: 44)
        .finifyGlass(in: Capsule(), tint: Color(hex: 0x111D40).opacity(0.5), fallback: Color(hex: 0x111D40).opacity(0.88))
        .finifyShadow(FinifyShadow.Style(color: .black.opacity(0.5), radius: 16, y: 6))
        .help("Cover size")
    }
}
