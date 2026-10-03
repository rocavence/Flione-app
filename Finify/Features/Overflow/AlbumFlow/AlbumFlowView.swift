import AppKit
import SwiftUI

/// Album Flow：Cover Flow 式橫向瀏覽。中間的專輯最大、最亮，兩側以透視角度排開。
/// 操作：trackpad 橫滑、滑鼠滾輪、← → 鍵；Return 播放；點中間的封面翻面看曲目（Album Flip）。
struct AlbumFlowView: View {
    let albums: [Album]
    let playingAlbumID: String?
    let onPlay: (Album) -> Void
    /// 上方有搜尋、佇列、專輯面板時為 false，滾輪交給那些面板
    var isActive = true
    /// 值改變時回到正在播放的專輯
    var centerOnPlayingToken = 0
    /// 封面大小（0–5 共 6 段），5 = 視窗放得下的最大尺寸
    var sizeStep = 3

    static let sizeSteps = 6
    /// 倒影高度占封面的比例
    private static let reflectionRatio: CGFloat = 0.32

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var centerID: String?
    /// 使用者手動移動過後，不再自動跳到正在播放的專輯
    @State private var userMoved = false
    /// 翻到背面的專輯；移到別張時自動翻回
    @State private var flippedID: String?
    /// 這次拖曳已經移動了幾張
    @State private var dragSteps = 0
    @State private var wheelMonitor: Any?
    /// monitor 的 closure 只在安裝時捕捉一次 view，用 reference 讀取最新的 isActive
    @State private var activeState = ActiveState()

    private final class ActiveState {
        var value = true
        var albums: [Album] = []
        weak var window: NSWindow?
    }
    @FocusState private var focused: Bool

    /// 封面邊長，隨視窗大小調整（扣掉頂部列、標題與底部播放列）
    @State private var side: CGFloat = 340
    @State private var resizeAnchor: String?

    /// 視窗放得下的最大封面（扣掉頂部列、倒影、標題、底部播放列）
    private static func maximumSide(for size: CGSize) -> CGFloat {
        // 垂直空間：頂部列 56、封面＋倒影＋上下留白 60、間距 32、標題與按鈕約 110、底部播放列留白 96
        let byHeight = (size.height - 56 - 60 - 32 - 110 - 96 - 20) / (1 + reflectionRatio)
        let byWidth = size.width * 0.36
        return max(180, min(byHeight, byWidth, 960))
    }

    /// 依段數縮小：第 0 段是最大的 50%，最後一段是 100%
    static func side(for size: CGSize, step: Int) -> CGFloat {
        let factor = 0.5 + 0.1 * CGFloat(min(max(step, 0), sizeSteps - 1))
        return max(140, maximumSide(for: size) * factor).rounded()
    }

    /// 使用者沒調過大小時的預設：最大尺寸的 8 成，並限制在 260～560pt——小視窗不會太小、大螢幕不會巨大
    static func autoStep(for size: CGSize) -> Int {
        let target = min(560, max(260, maximumSide(for: size) * 0.8))
        return (0..<sizeSteps).min { abs(side(for: size, step: $0) - target) < abs(side(for: size, step: $1) - target) }!
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: Spacing.s32) {
                Spacer(minLength: 0)
                ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: -side * 0.42) {
                        ForEach(albums) { album in
                            cover(album)
                                .id(album.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, (geo.size.width - side) / 2, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $centerID, anchor: .center)
                // 尺寸改變後 scroll view 不會自動保持置中，等版面更新後重新捲到目前的專輯
                .onChange(of: side) {
                    guard let id = resizeAnchor ?? centerID else { return }
                    // 大幅改變尺寸時，第一次捲動可能發生在版面還沒更新完；稍後再校正一次
                    DispatchQueue.main.async {
                        proxy.scrollTo(id, anchor: .center)
                        centerID = id
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        proxy.scrollTo(id, anchor: .center)
                        centerID = id
                        resizeAnchor = nil
                    }
                }
                // 滑鼠按住左右拖曳：每拖過一張封面的距離就移動一張
                .simultaneousGesture(DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        let target = Int((-value.translation.width / (side * 0.58)).rounded())
                        if target != dragSteps {
                            step(target - dragSteps)
                            dragSteps = target
                        }
                    }
                    .onEnded { _ in dragSteps = 0 })
                .frame(height: side * (1 + Self.reflectionRatio) + 60)
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onKeyPress(.leftArrow) { step(-1); return .handled }
                .onKeyPress(.rightArrow) { step(1); return .handled }
                .onKeyPress(.return) { if let album = centered { onPlay(album) }; return .handled }
                }

                caption
                Spacer(minLength: Spacing.s96)
            }
            .onChange(of: geo.size, initial: true) { resize(to: geo.size) }
            .onChange(of: sizeStep) {
                withAnimation(Motion.respecting(reduceMotion, Motion.artwork)) { resize(to: geo.size) }
            }
        }
        .background { FlowBackdrop(artwork: centered?.artwork, horizon: 0.5) }
        .onAppear {
            centerOnPlaying()
            focused = true
            installWheelMonitor()
        }
        .onDisappear {
            if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) }
            wheelMonitor = nil
        }
        .onChange(of: playingAlbumID) { if !userMoved { centerOnPlaying() } }
        .onChange(of: isActive, initial: true) { activeState.value = isActive }
        .onChange(of: albums.map(\.id), initial: true) { activeState.albums = albums }
        .background(FlowWindowReader { activeState.window = $0 })
        .onChange(of: centerID) { flippedID = nil }
        .onChange(of: centerOnPlayingToken) {
            userMoved = false
            withAnimation(Motion.respecting(reduceMotion, Motion.artwork)) { centerOnPlaying() }
        }
        .onChange(of: albums.count) { if !userMoved { centerOnPlaying() } }
    }

    private func resize(to size: CGSize) {
        // 先記下目前置中的專輯：改尺寸時 scroll view 會回報新的位置，蓋掉原本的專輯
        if resizeAnchor == nil { resizeAnchor = centerID }
        side = Self.side(for: size, step: sizeStep)
    }

    private var centered: Album? { albums.first { $0.id == centerID } }

    /// 點中間的封面翻面看曲目；點旁邊的封面移到中間
    private func tapped(_ album: Album) {
        if album.id == centerID {
            flippedID = flippedID == album.id ? nil : album.id
        } else {
            userMoved = true
            withAnimation(Motion.respecting(reduceMotion, Motion.flow)) { centerID = album.id }
        }
    }

    private func centerOnPlaying() {
        centerID = playingAlbumID.flatMap { id in albums.first { $0.id == id }?.id } ?? centerID ?? albums.first?.id
    }

    private func cover(_ album: Album) -> some View {
        let reduceMotion = reduceMotion
        let flipped = flippedID == album.id
        return VStack(spacing: 2) {
            AlbumFlipCard(album: album, isFlipped: flipped, side: side,
                          elevation: album.id == playingAlbumID ? .playing : .standard)
            FlowReflection(album: album, side: side, ratio: Self.reflectionRatio)
                .opacity(flipped ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: flipped)
        }
            .scrollTransition(axis: .horizontal) { content, phase in
                content
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : phase.value * -58), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                    .scaleEffect(1 - min(abs(phase.value), 1) * 0.28)
                    .opacity(1 - min(abs(phase.value), 2) * 0.22)
                    .brightness(-min(abs(phase.value), 1) * 0.25)
            }
            .zIndex(album.id == centerID ? 1 : 0)
            .onTapGesture { tapped(album) }
            .accessibilityAction(.default) { tapped(album) }
            .accessibilityLabel("\(album.name), \(album.artistName)")
            .accessibilityHint(album.id == centerID ? "Flip to see tracks" : "Move to center")
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var caption: some View {
        if let album = centered {
            VStack(spacing: Spacing.s8) {
                Text(album.name)
                    .finifyFont(.title)
                    .foregroundStyle(FinifyColor.Overflow.ink)
                    .lineLimit(1)
                Text([album.artistName, album.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                    .finifyFont(.body)
                    .foregroundStyle(FinifyColor.Overflow.muted)
                HStack(spacing: Spacing.s8) {
                    FinifyButton(title: "Play", icon: .play, kind: .primary) { onPlay(album) }
                    FinifyButton(title: flippedID == album.id ? "Cover" : "Tracks", icon: .cd) {
                        flippedID = flippedID == album.id ? nil : album.id
                    }
                }
                .padding(.top, Spacing.s8)
            }
            .padding(.horizontal, Spacing.s48)
            .id(album.id)
            .transition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.7), value: centerID)
        }
    }

    /// 一般滑鼠的滾輪是垂直方向，橫向 ScrollView 收不到；每一格滾輪移動一張專輯。
    /// 觸控板（精確捲動）維持原生的橫向滑動。
    private func installWheelMonitor() {
        guard wheelMonitor == nil else { return }
        let active = activeState
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard active.value, event.window === active.window, !event.hasPreciseScrollingDeltas, abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
                  event.scrollingDeltaY != 0 else { return event }
            step(event.scrollingDeltaY > 0 ? -1 : 1, in: active.albums)
            return nil
        }
    }

    /// `list` 讓滾輪 monitor 傳入最新的專輯清單（monitor 只在安裝時捕捉一次 view）
    private func step(_ delta: Int, in list: [Album]? = nil) {
        let albums = list ?? self.albums
        guard let index = albums.firstIndex(where: { $0.id == centerID }) else { return }
        let next = min(max(0, index + delta), albums.count - 1)
        userMoved = true
        withAnimation(Motion.respecting(reduceMotion, Motion.flow)) { centerID = albums[next].id }
    }
}

/// 取得 Flow 所在的視窗，讓滾輪 monitor 只處理這個視窗的事件
private struct FlowWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = Reporter()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Reporter: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}

/// 封面下方的鏡面倒影：上下翻轉、由淡到透明，略帶模糊，像放在亮面展示台上
private struct FlowReflection: View {
    let album: Album
    let side: CGFloat
    let ratio: CGFloat

    var body: some View {
        ArtworkView(artwork: album.artwork, elevation: .none, fallbackTitle: album.name, fallbackSubtitle: album.artistName)
            .frame(width: side, height: side)
            .scaleEffect(x: 1, y: -1)
            .blur(radius: 1.5)
            .mask {
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.32), location: 0),
                    .init(color: .white.opacity(0.08), location: ratio * 0.55),
                    .init(color: .clear, location: ratio),
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: side, height: side * ratio, alignment: .top)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Album Flow 的背景：目前置中專輯的封面放大、重度模糊，換張時緩慢交叉淡入；
/// 再疊上暗角與「地面」漸層，讓封面像擺在展示台上。Reduce Motion 時直接切換
private struct FlowBackdrop: View {
    let artwork: ArtworkRef?
    /// 地平線位置（0 = 頂端、1 = 底部），倒影落在這條線下方
    let horizon: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            FinifyColor.Overflow.background
            Color.clear.overlay {
                if let artwork {
                    ArtworkView(artwork: artwork, cornerRadius: 0, elevation: .none)
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(1.6)
                        .blur(radius: 110, opaque: true)
                        .saturation(1.4)
                        .opacity(0.9)
                        .id(artwork)
                        .transition(.opacity)
                }
            }
            .clipped()
            // 中央的柔光，讓置中的封面周圍最亮
            RadialGradient(colors: [.white.opacity(0.06), .clear], center: UnitPoint(x: 0.5, y: horizon - 0.08),
                           startRadius: 0, endRadius: 520)
            // 暗角
            RadialGradient(colors: [.clear, .black.opacity(0.6)], center: UnitPoint(x: 0.5, y: horizon - 0.05),
                           startRadius: 280, endRadius: 1200)
            // 地面：地平線以下漸暗，倒影融進去
            LinearGradient(stops: [
                .init(color: .clear, location: horizon),
                .init(color: .black.opacity(0.55), location: min(1, horizon + 0.25)),
                .init(color: .black.opacity(0.8), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: artwork)
        .drawingGroup()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
