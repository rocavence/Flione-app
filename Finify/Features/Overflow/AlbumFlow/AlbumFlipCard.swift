import SwiftUI

/// Album Flip：正面是封面，翻面是曲目表。3D 旋轉＋透視＋spring；Reduce Motion 時改為交叉淡入。
struct AlbumFlipCard: View {
    let album: Album
    let isFlipped: Bool
    let side: CGFloat
    let elevation: ArtworkView.Elevation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            ZStack {
                front.opacity(isFlipped ? 0 : 1)
                AlbumBack(album: album, side: side).opacity(isFlipped ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.2), value: isFlipped)
        } else {
            FlipView(angle: isFlipped ? 180 : 0, front: front, back: AlbumBack(album: album, side: side))
                .animation(.spring(response: 0.6, dampingFraction: 0.78), value: isFlipped)
        }
    }

    private var front: some View {
        ArtworkView(artwork: album.artwork, elevation: elevation, fallbackTitle: album.name, fallbackSubtitle: album.artistName)
            .frame(width: side, height: side)
    }
}

/// 依動畫中的角度決定顯示正面或背面（轉過 90° 才換成背面），避免兩面同時半透明
private struct FlipView<Front: View, Back: View>: View, Animatable {
    var angle: Double
    let front: Front
    let back: Back

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        ZStack {
            if angle < 90 {
                front
            } else {
                back.rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
    }
}

/// 專輯背面：標題、藝人、曲目表；點曲目從該首開始播放
private struct AlbumBack: View {
    let album: Album
    let side: CGFloat
    @Environment(AppEnvironment.self) private var app
    @State private var tracks: Loadable<[Track]> = .loading

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .finifyFont(.heading)
                    .foregroundStyle(FinifyColor.Overflow.ink)
                    .lineLimit(2)
                Text([album.artistName, album.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                    .finifyFont(.caption)
                    .foregroundStyle(FinifyColor.Overflow.muted)
                    .lineLimit(1)
            }
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
            switch tracks {
            case .loading:
                VStack(spacing: 6) { ForEach(0..<8, id: \.self) { _ in SkeletonBlock().frame(height: 14) } }
            case .failed:
                Text("Can't load tracks.").finifyFont(.caption).foregroundStyle(FinifyColor.Overflow.muted)
            case .loaded(let list):
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, track in
                            BackTrackRow(track: track, number: track.trackNumber ?? index + 1) { app.player.play(list, startAt: index) }
                        }
                    }
                }
            }
        }
        .padding(Spacing.s20)
        .frame(width: side, height: side, alignment: .topLeading)
        .background(backColor, in: RoundedRectangle(cornerRadius: Radius.artwork, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Radius.artwork, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1) }
        .finifyShadow(FinifyShadow.playing)
        .environment(\.overflowStyle, true)
        .task(id: album.id) {
            do { tracks = .loaded(try await app.repository?.tracks(inAlbum: album.id) ?? []) } catch { tracks = .failed }
        }
    }

    /// 背面底色取自封面平均色並壓暗（ambient color，不是品牌色）
    private var backColor: Color {
        guard let hash = album.artwork?.blurHash, let c = BlurHash.averageColor(hash) else { return Color(white: 0.1) }
        return Color(red: c.r * 0.28, green: c.g * 0.28, blue: c.b * 0.28)
    }
}

private struct BackTrackRow: View {
    let track: Track
    let number: Int
    let onPlay: () -> Void
    @Environment(AppEnvironment.self) private var app
    @State private var hovering = false

    var body: some View {
        let current = app.player.currentTrack?.id == track.id
        HStack(spacing: Spacing.s8) {
            Text("\(number)")
                .monospacedDigit()
                .foregroundStyle(FinifyColor.Overflow.faint)
                .frame(width: 18, alignment: .trailing)
            Text(track.name)
                .foregroundStyle(current ? FinifyColor.accent : FinifyColor.Overflow.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(track.duration.formattedDuration)
                .monospacedDigit()
                .foregroundStyle(FinifyColor.Overflow.faint)
        }
        .finifyFont(.caption)
        .padding(.vertical, 5)
        .padding(.horizontal, Spacing.s4)
        .background(hovering ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: Radius.small))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onPlay)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onPlay)
        .accessibilityAction(named: "Play", onPlay)
    }
}
