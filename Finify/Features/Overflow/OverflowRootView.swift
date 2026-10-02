import AppKit
import SwiftUI

enum OverflowLayout: String, CaseIterable {
    case wall = "Wall"
    case flow = "Flow"
}

/// Overflow mode：讓音樂庫成為畫面本身。完整的 App mode，可瀏覽、搜尋、播放、排佇列，不需離開。
struct OverflowRootView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("FinifyOverflowLayout") private var layout: OverflowLayout = .wall
    @AppStorage("FinifyWallDensity") private var densityRaw = WallDensity.medium.rawValue
    @State private var openAlbum: Album?
    @State private var immersive = false
    @State private var scrollToPlaying = 0

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
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: immersive)
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: openAlbum)
        .task { await app.library.refreshIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in immersive = false }
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
                            albums: app.library.albums,
                            density: density,
                            playingAlbumID: playingAlbumID,
                            images: app.images,
                            onOpen: { openAlbum = $0 },
                            onPlay: play,
                            onQueue: queue,
                            scrollToPlayingToken: scrollToPlaying
                        )
                    case .flow:
                        AlbumFlowView(albums: app.library.albums, playingAlbumID: playingAlbumID, onOpen: { openAlbum = $0 }, onPlay: play)
                    }
                }
            }
            .blur(radius: openAlbum == nil ? 0 : 24)
            .allowsHitTesting(openAlbum == nil)

            VStack(spacing: 0) {
                topBar
                Spacer()
                if openAlbum == nil { NowPlayingPill(onOpen: openPlayingAlbum, onImmersive: enterImmersive) }
            }

            if let album = openAlbum {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { openAlbum = nil }
                OverflowAlbumPanel(album: album) { openAlbum = nil }
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .onExitCommand { openAlbum = nil }
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
            .background(FinifyColor.Overflow.control, in: RoundedRectangle(cornerRadius: Radius.ui + 2, style: .continuous))

            if layout == .wall {
                HStack(spacing: 2) {
                    FinifyIconButton(icon: .minus, label: "Smaller albums", size: .compact) { stepDensity(-1) }
                        .disabled(density.wrappedValue == .small)
                    Text(density.wrappedValue.label)
                        .finifyFont(.caption)
                        .foregroundStyle(FinifyColor.Overflow.muted)
                        .frame(width: 52)
                    FinifyIconButton(icon: .plus, label: "Larger albums", size: .compact) { stepDensity(1) }
                        .disabled(density.wrappedValue == .large)
                }
                .help("Pinch to resize")
            }
            Spacer()
            SearchTrigger { app.isSearchPresented = true }
                .frame(width: 260)
            if playingAlbumID != nil && layout == .wall {
                FinifyIconButton(icon: .musicNote, label: "Show what's playing") { scrollToPlaying += 1 }
            }
            FinifyIconButton(icon: .fullscreen, label: "Fullscreen (⌃⌘F)", action: enterImmersive)
                .keyboardShortcut("f", modifiers: [.command, .control])
            ModeSwitch()
        }
        .padding(.horizontal, Spacing.s16)
        .frame(height: 52)
        .background(LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
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
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { app.isSearchPresented = false }
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
                VolumeControl()
            }
            .padding(.horizontal, Spacing.s16)
            .padding(.vertical, Spacing.s8)
            .background(Color(white: 0.06).opacity(0.86), in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Radius.large, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1) }
            .finifyShadow(FinifyShadow.Style(color: .black.opacity(0.5), radius: 30, y: 12))
            .padding(.bottom, Spacing.s24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
