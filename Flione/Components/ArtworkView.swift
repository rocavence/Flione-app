import SwiftUI

/// 所有 artwork 的唯一元件：快取、placeholder（BlurHash）、載入淡入、圓角、陰影、hover、正在播放狀態。
/// Feature 不得自行載入或繪製封面。
struct ArtworkView: View {
    enum Elevation {
        case none
        case standard
        case playing
    }

    let artwork: ArtworkRef?
    /// nil = 依封面大小自動決定（Radius.artwork(for:)）
    var cornerRadius: CGFloat?
    var elevation: Elevation = .standard
    /// hover 時微幅上浮
    var interactive = false
    /// 沒有封面時顯示的文字（專輯名、藝人）
    var fallbackTitle: String?
    var fallbackSubtitle: String?

    @Environment(AppEnvironment.self) private var app
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loaded: LoadedImage?
    @State private var hovering = false
    @State private var measuredSide: CGFloat = 0

    private var radius: CGFloat { cornerRadius ?? Radius.artwork(for: measuredSide) }

    private struct LoadedImage: Equatable {
        let key: String
        let image: CGImage
        static func == (a: Self, b: Self) -> Bool { a.key == b.key }
    }

    var body: some View {
        GeometryReader { geo in
            let pixels = Int(max(geo.size.width, geo.size.height) * displayScale)
            let key = artwork.map { "\($0.itemID)-\($0.tag)-\(ImagePipeline.bucket(pixels))" } ?? "none"
            // 已在 memory cache 的圖直接顯示，避免捲動時閃 placeholder
            let image = loaded?.key == key ? loaded?.image : artwork.flatMap { app.images?.cached($0, pixelSize: pixels) }
            ZStack {
                placeholder
                if let image {
                    Image(decorative: image, scale: displayScale)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .task(id: key) {
                guard image == nil, let artwork, let images = app.images else { return }
                guard let result = await images.image(artwork, pixelSize: pixels), !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                    loaded = LoadedImage(key: key, image: result)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measuredSide = $0 }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
        .finifyShadow(shadowStyle)
        .scaleEffect(interactive && hovering && !reduceMotion ? 1.015 : 1)
        .animation(Motion.micro, value: hovering)
        .animation(Motion.respecting(reduceMotion, Motion.artwork), value: elevation)
        .onHover { if interactive { hovering = $0 } }
        .accessibilityHidden(true)
    }

    private var shadowStyle: FinifyShadow.Style {
        switch elevation {
        case .none: FinifyShadow.Style(color: .clear, radius: 0, y: 0)
        case .standard: interactive && hovering ? FinifyShadow.artworkHover : FinifyShadow.artwork
        case .playing: FinifyShadow.playing
        }
    }

    /// 沒有封面時的底色：依名稱算出固定的兩個色相（同一個名稱永遠同色，不同名稱各自不同），像一套設計過的封面
    static func fallbackGradient(for title: String) -> LinearGradient {
        // FNV-1a：String.hashValue 每次啟動都不同，不能用
        var hash: UInt32 = 2_166_136_261
        for byte in title.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        let hue = Double(hash % 360) / 360
        return LinearGradient(colors: [Color(hue: hue, saturation: 0.5, brightness: 0.5),
                                       Color(hue: (hue + 0.09).truncatingRemainder(dividingBy: 1), saturation: 0.62, brightness: 0.24)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @ViewBuilder
    private var placeholder: some View {
        if let hash = artwork?.blurHash, let blur = BlurHash.image(hash) {
            Image(decorative: blur, scale: 1)
                .resizable()
                .interpolation(.medium)
        } else if artwork == nil, let fallbackTitle {
            // 沒有封面：以文字排版的封面代替
            GeometryReader { geo in
                let scale = geo.size.width / 200
                // 圓形（藝人）時置中，避免文字被圓角裁掉
                let circular = radius >= geo.size.width / 2
                VStack(alignment: circular ? .center : .leading, spacing: 4 * scale) {
                    if !circular { Spacer(minLength: 0) }
                    Text(fallbackTitle)
                        .font(.system(size: max(9, 17 * scale), weight: .semibold))
                        .tracking(-0.3 * scale)
                        .lineLimit(3)
                        .multilineTextAlignment(circular ? .center : .leading)
                        .foregroundStyle(.white.opacity(0.94))
                    if let fallbackSubtitle, geo.size.width > 64 {
                        Text(fallbackSubtitle)
                            .font(.system(size: max(8, 12 * scale)))
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding((circular ? 28 : 12) * scale)
                .frame(width: geo.size.width, height: geo.size.height, alignment: circular ? .center : .bottomLeading)
                .background(Self.fallbackGradient(for: fallbackTitle))
            }
        } else {
            ZStack {
                FinifyColor.surface
                FinifyIcon(.musicNote, size: .large)
                    .foregroundStyle(FinifyColor.faint)
            }
        }
    }
}
