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
    /// -1 = Auto（依視窗尺寸）；使用者拖過大小滑軌後才記住選擇
    @AppStorage("FinifyWallDensity") private var densityRaw = -1
    @AppStorage("FinifyWallSort") private var sort: AlbumSort = .artist
    @AppStorage("FinifyFlowSize") private var flowSizeRaw = -1
    /// 封面牆／Cover Flow 可用的大小，用來算 Auto 預設
    @State private var browseSize = CGSize(width: 1360, height: 860)
    /// 浮動播放列的實際高度（量測），封面牆下方留白依它計算
    @State private var pillHeight: CGFloat = 0
    /// 封面牆與播放列的距離＝播放列到視窗底的距離；沒在播放時只留這段距離
    private var wallBottomInset: CGFloat {
        let margin = NowPlayingPill.bottomMargin
        return app.player.currentTrack == nil ? margin : margin + pillHeight + margin
    }
    /// 排序結果只在專輯清單或排序方式改變時重算
    @State private var sortedAlbums: [Album] = []
    /// Magic 排序（"" = 關閉）；選了會暫時取代一般排序
    @AppStorage("FinifyMagicSort") private var magicRaw = ""
    @AppStorage(SettingsKey.wallRounded) private var wallRounded = true
    @AppStorage(SettingsKey.wallAmbient) private var wallAmbient = true
    @AppStorage(SettingsKey.wallAutoScroll) private var autoScroll = false
    private var magic: MagicSort? { MagicSort(rawValue: magicRaw) }
    @State private var openAlbum: Album?
    @State private var scrollToPlaying = 0

    private var density: Binding<WallDensity> {
        Binding { WallDensity(rawValue: densityRaw) ?? WallDensity.auto(forHeight: browseSize.height, bottomInset: wallBottomInset) } set: { densityRaw = $0.rawValue }
    }

    private var playingAlbumID: String? { app.player.currentTrack?.albumID }
    private var flowSize: Int { flowSizeRaw >= 0 ? flowSizeRaw : AlbumFlowView.autoStep(for: browseSize) }
    private var flowSizeBinding: Binding<Int> { Binding { flowSize } set: { flowSizeRaw = $0 } }
    private var densityStep: Binding<Int> { Binding { density.wrappedValue.rawValue } set: { densityRaw = $0 } }
    private var layout: OverflowLayout { app.overflowLayout }
    @AppStorage(SettingsKey.textComfort) private var comfort = TextComfort.standard

    var body: some View {
        ZStack {
            AmbientBackground(artwork: app.player.currentTrack?.artwork, enabled: wallAmbient)
            browse
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { browseSize = $0 }
        .environment(\.overflowStyle, true)
        .environment(\.colorScheme, .dark)
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: openAlbum)
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: app.isQueuePresented)
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: app.isLyricsPresented)
        .task { await app.library.refreshIfNeeded() }
        .onChange(of: app.library.albums, initial: true) { resort() }
        #if DEBUG
        // -FinifyDemoFocusPlaying <秒>：幾秒後按「正在播放」（除錯用）
        .task {
            let delay = UserDefaults.standard.double(forKey: "FinifyDemoFocusPlaying")
            guard delay > 0 else { return }
            try? await Task.sleep(for: .seconds(delay))
            scrollToPlaying += 1
        }
        #endif
        .onChange(of: sort) {
            magicRaw = ""
            resort()
        }
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
                            typeToSelectByTitle: sort == .title,
                            bottomInset: wallBottomInset,
                            rounded: wallRounded
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
            // 睫狀肌舒適：封面標題、浮動播放列、專輯面板、佇列與歌詞放大；上方的控制列與搜尋維持原尺寸（D41）
            .environment(\.finifyTextScale, comfort.scale)

            VStack(spacing: 0) {
                topBar
                Spacer()
                if openAlbum == nil {
                    NowPlayingPill(onOpen: openPlayingAlbum, onHeight: { pillHeight = $0 })
                        .environment(\.finifyTextScale, comfort.scale)
                }
            }

            if let album = openAlbum {
                Color.black.opacity(0.45)
                    .onTapGesture { openAlbum = nil }
                OverflowAlbumPanel(album: album, onClose: { openAlbum = nil }, onOpenAlbum: { openAlbum = $0 })
                    .environment(\.finifyTextScale, comfort.scale)
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
                .environment(\.finifyTextScale, comfort.scale)
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
                    ForEach(AlbumSort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Text("Sort by: \(sort.title)")
                    .finifyFont(.caption)
                    .foregroundStyle(FinifyColor.Overflow.muted)
            }
            .menuStyle(.borderlessButton)
            .tint(FinifyColor.Overflow.muted)
            .fixedSize()
            .padding(.horizontal, Spacing.s12)
            .frame(height: ViewControls.controlHeight)
            .modifier(TopBarSurface(overflow: true, shape: Capsule(), fallback: FinifyColor.Overflow.control))
            .accessibilityLabel(Text("Sort albums, \(sort.title)"))

            MagicSortMenu(selection: magic) { choice in
                magicRaw = choice?.rawValue ?? ""
                resort()  // 再選一次 Shuffle 也會重洗
            }

            if layout == .wall {
                SizeSlider(step: densityStep, count: WallDensity.allCases.count, label: "Album size",
                           valueText: density.wrappedValue.label)
                    .help("Album size (pinch to resize)")
            } else {
                SizeSlider(step: flowSizeBinding, count: AlbumFlowView.sizeSteps, label: "Cover size",
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
                .frame(height: ViewControls.controlHeight)
                .modifier(TopBarSurface(overflow: true, shape: Capsule(), fallback: FinifyColor.Overflow.control))
                .contentShape(Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .disabled(playingAlbumID == nil)
            .opacity(playingAlbumID == nil ? 0.4 : 1)
            .help("Focus on the album that's playing")
            .accessibilityLabel("Focus on the album that's playing")

            if layout == .wall { autoScrollToggle }

            Spacer()
            SearchTrigger { app.isSearchPresented = true }
                .frame(width: 260)
            ViewControls()
        }
        .padding(.leading, Spacing.s16)
        .frame(height: ViewControls.barHeight)
        .background(LinearGradient(colors: [FinifyColor.Ocean.abyss.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
    }

    /// Infinity：封面牆一直自動捲動（滑鼠在牆上也不停）
    private var autoScrollToggle: some View {
        Button { autoScroll.toggle() } label: {
            HStack(spacing: Spacing.s4) {
                FinifyIcon(.infinite, weight: autoScroll ? .filled : .outline, size: .compact)
                Text("Auto-scroll").finifyFont(.caption)
            }
            .foregroundStyle(autoScroll ? FinifyColor.accent : FinifyColor.Overflow.muted)
            .padding(.horizontal, Spacing.s12)
            .frame(height: ViewControls.controlHeight)
            .modifier(TopBarSurface(overflow: true, shape: Capsule(), fallback: FinifyColor.Overflow.control))
            .overlay { if autoScroll { Capsule().strokeBorder(FinifyColor.accent.opacity(0.6), lineWidth: 1) } }
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .help(autoScroll ? "Auto-scroll is on. The wall keeps moving, even under the pointer." : "Auto-scroll is off. The wall moves only when the pointer is away.")
        .accessibilityLabel("Auto-scroll")
        .accessibilityValue(autoScroll ? Text("On") : Text("Off"))
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
        SearchOverlay(onOpenAlbum: { openAlbum = $0 }, onOpenArtist: { artist in
            // Overflow 沒有藝人頁：開該藝人最新的專輯
            Task {
                if let album = try? await app.repository?.albums(byArtist: artist.id).first { openAlbum = album }
            }
        })
    }

    private func play(_ album: Album) {
        app.player.play(album: album)
    }


    private func queue(_ album: Album, next: Bool) {
        Task {
            guard let tracks = try? await app.repository?.tracks(inAlbum: album.id) else { return }
            if next { app.player.playNext(tracks) } else { app.player.addToQueue(tracks) }
        }
    }

    private func resort() {
        sortedAlbums = magic?.apply(to: app.library.albums) ?? sort.apply(to: app.library.albums)
    }

    private func openPlayingAlbum() {
        guard let id = playingAlbumID else { return }
        openAlbum = app.library.albums.first { $0.id == id }
    }
}

/// Overflow 底部浮動的 now playing：封面、曲名、控制、進度
private struct NowPlayingPill: View {
    /// 播放列到視窗底的距離；封面牆與播放列之間也用同樣的距離
    static let bottomMargin = Spacing.s24
    let onOpen: () -> Void
    let onHeight: (CGFloat) -> Void
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
                FinifyIconButton(icon: .notes2, label: "Lyrics", isActive: app.isLyricsPresented) { app.isLyricsPresented.toggle() }
                VolumeControl()
            }
            // 左右最邊緣留較寬的內距，控制不貼邊
            .padding(.horizontal, Spacing.s32)
            .padding(.vertical, Spacing.s8)
            // 膠囊形：兩側全圓角
            .finifyGlass(in: Capsule(), tint: FinifyColor.Ocean.surface1.opacity(0.55), fallback: FinifyColor.Ocean.surface1.opacity(0.88))
            .finifyShadow(FinifyShadow.Style(color: .black.opacity(0.5), radius: 30, y: 12))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
            .padding(.bottom, Self.bottomMargin)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}


/// 頂部的大小滑桿：分段吸附，拖曳時即時縮放。Infinity 是封面牆密度，Cover Flow 是封面大小
private struct SizeSlider: View {
    @Binding var step: Int
    let count: Int
    let label: LocalizedStringResource
    let valueText: LocalizedStringResource

    var body: some View {
        let last = Double(count - 1)
        HStack(spacing: Spacing.s4) {
            FinifyIconButton(icon: .minus, label: "Smaller", size: .compact) { change(-1) }
                .disabled(step <= 0)
            ProgressBar(value: Double(step) / last, continuous: true, steps: count, alwaysShowsKnob: true, isPlayback: false) {
                let next = Int(($0 * last).rounded())
                if next != step { Haptics.perform(.step) }
                step = next
            }
                .frame(width: 96)
                .accessibilityLabel(Text(label))
                .accessibilityValue(Text(valueText))
            FinifyIconButton(icon: .plus, label: "Larger", size: .compact) { change(1) }
                .disabled(step >= count - 1)
        }
        .padding(.horizontal, Spacing.s4)
        .frame(height: ViewControls.controlHeight)
        .modifier(TopBarSurface(overflow: true, shape: Capsule(), fallback: FinifyColor.Overflow.control))
    }

    /// 兩端的 − ＋：一次一段
    private func change(_ delta: Int) {
        let next = min(count - 1, max(0, step + delta))
        guard next != step else { return }
        Haptics.perform(.step)
        step = next
    }
}

/// 「Magic」排序選單：好玩的排列條件；啟用時按鈕顯示目前的條件
private struct MagicSortMenu: View {
    let selection: MagicSort?
    let onSelect: (MagicSort?) -> Void

    var body: some View {
        // Menu 直接包住自己畫的膠囊。原本把透明的 Menu 疊在膠囊上，選單位置偏掉，點選項也會穿過去打到封面牆
        Menu {
            ForEach(MagicSort.allCases, id: \.self) { option in
                // Toggle 在選單裡會顯示勾選；再點一次同一項也會重新套用（Shuffle 重洗）
                Toggle(isOn: Binding(get: { selection == option }, set: { _ in onSelect(option) })) {
                    Text(option.title)
                    Text(option.subtitle)
                }
            }
            if selection != nil {
                Divider()
                Button("Turn Off Magic") { onSelect(nil) }
            }
        } label: {
            HStack(spacing: Spacing.s4) {
                FinifyIcon(.wandSparkle, weight: selection == nil ? .outline : .filled, size: .compact)
                (selection.map { Text($0.title) } ?? Text("Magic")).finifyFont(.caption)
            }
            .foregroundStyle(selection == nil ? FinifyColor.Overflow.muted : FinifyColor.Overflow.ink)
            .padding(.horizontal, Spacing.s12)
            .frame(height: ViewControls.controlHeight)
            .modifier(TopBarSurface(overflow: true, shape: Capsule(), fallback: FinifyColor.Overflow.control))
            // 啟用中：膠囊外圈一道細橘光
            .overlay { if selection != nil { Capsule().strokeBorder(FinifyColor.orange.opacity(0.7), lineWidth: 1).finifyGlow(radius: 5) } }
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Magic sort: rearrange your library by color, genre, era, or chance")
        .accessibilityLabel(selection.map { Text("Magic sort, \($0.title)") } ?? Text("Magic sort"))
    }
}
