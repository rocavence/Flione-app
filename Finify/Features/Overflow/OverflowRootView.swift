import AppKit
import SwiftUI

/// Overflow 畫面的版面（使用者看到的名稱是 Infinity 與 Cover Flow，見 ViewMode）
enum OverflowLayout: String, CaseIterable {
    case wall = "Wall"
    case flow = "Flow"
}

/// Overflow mode：讓音樂庫成為畫面本身。完整的 App mode，可瀏覽、搜尋、播放、排佇列，不需離開。
struct OverflowRootView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("FinifyWallDensity") private var densityRaw = WallDensity.medium.rawValue
    @AppStorage("FinifyWallSort") private var sort: AlbumSort = .artist
    @AppStorage("FinifyFlowSize") private var flowSize = 3
    /// 排序結果只在專輯清單或排序方式改變時重算
    @State private var sortedAlbums: [Album] = []
    @State private var openAlbum: Album?
    @State private var scrollToPlaying = 0

    private var density: Binding<WallDensity> {
        Binding { WallDensity(rawValue: densityRaw) ?? .medium } set: { densityRaw = $0.rawValue }
    }

    private var playingAlbumID: String? { app.player.currentTrack?.albumID }
    private var layout: OverflowLayout { app.overflowLayout }

    var body: some View {
        ZStack {
            AmbientBackground(artwork: app.player.currentTrack?.artwork)
            browse
        }
        .environment(\.overflowStyle, true)
        .environment(\.colorScheme, .dark)
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: openAlbum)
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: app.isQueuePresented)
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: app.isLyricsPresented)
        .task { await app.library.refreshIfNeeded() }
        .onChange(of: app.library.albums, initial: true) { sortedAlbums = sort.apply(to: app.library.albums) }
        .onChange(of: sort) { sortedAlbums = sort.apply(to: app.library.albums) }
        #if DEBUG || BENCHMARK
        .task { await DebugDemo.run(app: app, openAlbum: { openAlbum = $0 }) }
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
                    case .flow:
                        AlbumFlowView(albums: sortedAlbums, playingAlbumID: playingAlbumID, onPlay: play,
                                      isActive: openAlbum == nil && !app.isSearchPresented && !app.isQueuePresented && !app.isLyricsPresented,
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
                if openAlbum == nil { NowPlayingPill(onOpen: openPlayingAlbum) }
            }

            if let album = openAlbum {
                Color.black.opacity(0.45)
                    .onTapGesture { openAlbum = nil }
                OverflowAlbumPanel(album: album, onClose: { openAlbum = nil }, onOpenAlbum: { openAlbum = $0 })
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .onExitCommand { openAlbum = nil }
            }

            if app.isQueuePresented || app.isLyricsPresented {
                HStack {
                    Spacer()
                    PlayerSidePanel(onOpenAlbum: { id in openAlbum = app.library.albums.first { $0.id == id } })
                        .padding(.top, ViewControls.barHeight + Spacing.s8)
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
            // 左上角：排序、大小、回到正在播放（Infinity 與 Cover Flow 共用）
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(AlbumSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Text("Sort by: \(sort.rawValue)")
                    .finifyFont(.caption)
                    .foregroundStyle(FinifyColor.Overflow.muted)
            }
            .menuStyle(.borderlessButton)
            .tint(FinifyColor.Overflow.muted)
            .fixedSize()
            .padding(.horizontal, Spacing.s12)
            .frame(height: 34)
            .modifier(TopBarSurface(overflow: true, shape: Capsule(), fallback: FinifyColor.Overflow.control))
            .accessibilityLabel("Sort albums, \(sort.rawValue)")

            if layout == .wall {
                SizeSlider(step: $densityRaw, count: WallDensity.allCases.count, label: "Album size",
                           valueText: density.wrappedValue.label)
                    .help("Album size (pinch to resize)")
            } else {
                SizeSlider(step: $flowSize, count: AlbumFlowView.sizeSteps, label: "Cover size",
                           valueText: "\(flowSize + 1) of \(AlbumFlowView.sizeSteps)")
                    .help("Cover size")
            }

            Button { scrollToPlaying += 1 } label: {
                HStack(spacing: Spacing.s4) {
                    FinifyIcon(.gps, size: .compact)
                    Text("Now Playing").finifyFont(.caption)
                }
                .foregroundStyle(FinifyColor.Overflow.muted)
                .padding(.horizontal, Spacing.s12)
                .frame(height: 34)
                .modifier(TopBarSurface(overflow: true, shape: Capsule(), fallback: FinifyColor.Overflow.control))
                .contentShape(Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .disabled(playingAlbumID == nil)
            .opacity(playingAlbumID == nil ? 0.4 : 1)
            .help("Focus on the album that's playing")
            .accessibilityLabel("Focus on the album that's playing")

            Spacer()
            SearchTrigger { app.isSearchPresented = true }
                .frame(width: 260)
            ViewControls()
        }
        .padding(.leading, Spacing.s16)
        .frame(height: ViewControls.barHeight)
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
}

/// Overflow 底部浮動的 now playing：封面、曲名、控制、進度
private struct NowPlayingPill: View {
    let onOpen: () -> Void
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
                FinifyIconButton(icon: .microphone, label: "Lyrics", isActive: app.isLyricsPresented) { app.isLyricsPresented.toggle() }
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


/// 頂部的大小滑桿：分段吸附，拖曳時即時縮放。Infinity 是封面牆密度，Cover Flow 是封面大小
private struct SizeSlider: View {
    @Binding var step: Int
    let count: Int
    let label: String
    let valueText: String

    var body: some View {
        let last = Double(count - 1)
        HStack(spacing: Spacing.s8) {
            FinifyIcon(.cd, size: .compact).foregroundStyle(FinifyColor.Overflow.faint).scaleEffect(0.7)
            ProgressBar(value: Double(step) / last, continuous: true, steps: count, alwaysShowsKnob: true) {
                let next = Int(($0 * last).rounded())
                if next != step { Haptics.perform(.step) }
                step = next
            }
                .frame(width: 96)
                .accessibilityLabel(label)
                .accessibilityValue(valueText)
            FinifyIcon(.cd, size: .compact).foregroundStyle(FinifyColor.Overflow.muted)
        }
        .padding(.horizontal, Spacing.s12)
        .frame(height: 34)
        .modifier(TopBarSurface(overflow: true, shape: Capsule(), fallback: FinifyColor.Overflow.control))
    }
}
