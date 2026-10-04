import SwiftUI

/// Modern 主要內容的背景光暈（參考 Kaset 的 AccentBackground，D27）。
/// 顏色取自封面的 BlurHash，不需下載圖片：深色模式頂端是封面的主色漸層，左上角再疊一層放射光；淺色模式只在頂端淡淡上色。
struct ContentGlow: View {
    let artwork: ArtworkRef?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.ambient) private var enabled = true
    @Environment(AppEnvironment.self) private var app
    /// 沒有 BlurHash（YouTube Music 的封面）時，從封面小圖取色
    @State private var sampled: (artwork: ArtworkRef, primary: Color, secondary: Color)?

    private var currentPalette: (primary: Color, secondary: Color)? {
        guard let artwork else { return nil }
        if let palette = Self.palette(artwork) { return palette }
        return sampled?.artwork == artwork ? (sampled!.primary, sampled!.secondary) : nil
    }

    var body: some View {
        ZStack {
            FinifyColor.paper
            if enabled, let palette = currentPalette {
                glow(palette)
                    .id(artwork)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : Motion.ambient, value: artwork)
        .animation(reduceMotion ? nil : Motion.ambient, value: sampled?.artwork)
        .task(id: artwork) {
            guard enabled, let artwork, artwork.blurHash == nil,
                  let image = await app.images?.image(artwork, pixelSize: 96), let colors = ImagePipeline.palette(image) else { return }
            func color(_ c: (r: Double, g: Double, b: Double)) -> Color { Color(.sRGB, red: c.r, green: c.g, blue: c.b) }
            sampled = (artwork, color(colors.left), color(colors.right))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func glow(_ palette: (primary: Color, secondary: Color)) -> some View {
        if colorScheme == .dark {
            ZStack {
                LinearGradient(stops: [.init(color: palette.primary.opacity(0.5), location: 0),
                                       .init(color: palette.secondary.opacity(0.22), location: 0.35),
                                       .init(color: .clear, location: 0.75)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [palette.primary.opacity(0.35), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
            }
        } else {
            LinearGradient(stops: [.init(color: palette.primary.opacity(0.28), location: 0),
                                   .init(color: palette.secondary.opacity(0.1), location: 0.3),
                                   .init(color: .clear, location: 0.55)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    /// BlurHash 解成 2×1：左半與右半的代表色
    private static func palette(_ artwork: ArtworkRef) -> (primary: Color, secondary: Color)? {
        guard let hash = artwork.blurHash, let image = BlurHash.decode(hash, width: 2, height: 1) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 8)
        guard let context = CGContext(data: &pixels, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 8,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 2, height: 1))
        func color(_ i: Int) -> Color {
            Color(.sRGB, red: Double(pixels[i]) / 255, green: Double(pixels[i + 1]) / 255, blue: Double(pixels[i + 2]) / 255)
        }
        return (color(0), color(4))
    }
}
