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
    var cornerRadius: CGFloat = Radius.artwork
    var elevation: Elevation = .standard
    /// hover 時微幅上浮
    var interactive = false

    @Environment(AppEnvironment.self) private var app
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loaded: LoadedImage?
    @State private var hovering = false

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
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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

    @ViewBuilder
    private var placeholder: some View {
        if let hash = artwork?.blurHash, let blur = BlurHash.image(hash) {
            Image(decorative: blur, scale: 1)
                .resizable()
                .interpolation(.medium)
        } else {
            ZStack {
                FinifyColor.surface
                FinifyIcon(.musicNote, size: .large)
                    .foregroundStyle(FinifyColor.faint)
            }
        }
    }
}
