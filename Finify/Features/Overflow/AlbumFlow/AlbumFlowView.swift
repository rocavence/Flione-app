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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var centerID: String?
    /// 使用者手動移動過後，不再自動跳到正在播放的專輯
    @State private var userMoved = false
    /// 翻到背面的專輯；移到別張時自動翻回
    @State private var flippedID: String?
    @State private var wheelMonitor: Any?
    /// monitor 的 closure 只在安裝時捕捉一次 view，用 reference 讀取最新的 isActive
    @State private var activeState = ActiveState()

    private final class ActiveState { var value = true }
    @FocusState private var focused: Bool

    private let side: CGFloat = 340

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: Spacing.s32) {
                Spacer(minLength: 0)
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
                .frame(height: side + 60)
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onKeyPress(.leftArrow) { step(-1); return .handled }
                .onKeyPress(.rightArrow) { step(1); return .handled }
                .onKeyPress(.return) { if let album = centered { onPlay(album) }; return .handled }

                caption
                Spacer(minLength: Spacing.s96)
            }
        }
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
        .onChange(of: centerID) { flippedID = nil }
        .onChange(of: albums.count) { if !userMoved { centerOnPlaying() } }
    }

    private var centered: Album? { albums.first { $0.id == centerID } }

    private func centerOnPlaying() {
        centerID = playingAlbumID.flatMap { id in albums.first { $0.id == id }?.id } ?? centerID ?? albums.first?.id
    }

    private func cover(_ album: Album) -> some View {
        let reduceMotion = reduceMotion
        return AlbumFlipCard(album: album, isFlipped: flippedID == album.id, side: side,
                             elevation: album.id == playingAlbumID ? .playing : .standard)
            .scrollTransition(axis: .horizontal) { content, phase in
                content
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : phase.value * -58), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                    .scaleEffect(1 - min(abs(phase.value), 1) * 0.28)
                    .opacity(1 - min(abs(phase.value), 2) * 0.22)
                    .brightness(-min(abs(phase.value), 1) * 0.25)
            }
            .zIndex(album.id == centerID ? 1 : 0)
            .onTapGesture {
                // 點中間的封面翻面看曲目；點旁邊的封面移到中間
                if album.id == centerID {
                    flippedID = flippedID == album.id ? nil : album.id
                } else {
                    userMoved = true
                    withAnimation(Motion.artwork) { centerID = album.id }
                }
            }
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
            .animation(Motion.ui, value: centerID)
        }
    }

    /// 一般滑鼠的滾輪是垂直方向，橫向 ScrollView 收不到；每一格滾輪移動一張專輯。
    /// 觸控板（精確捲動）維持原生的橫向滑動。
    private func installWheelMonitor() {
        guard wheelMonitor == nil else { return }
        let active = activeState
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard active.value, !event.hasPreciseScrollingDeltas, abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
                  event.scrollingDeltaY != 0 else { return event }
            step(event.scrollingDeltaY > 0 ? -1 : 1)
            return nil
        }
    }

    private func step(_ delta: Int) {
        guard let index = albums.firstIndex(where: { $0.id == centerID }) else { return }
        let next = min(max(0, index + delta), albums.count - 1)
        userMoved = true
        withAnimation(Motion.respecting(reduceMotion, Motion.artwork)) { centerID = albums[next].id }
    }
}
