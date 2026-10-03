import SwiftUI

/// Overflow 的 ambient 背景：目前專輯封面放大、重度模糊、壓暗，緩慢交叉淡入。
/// 顏色來自封面（ambient color），與品牌 accent 分離。Reduce Motion 時直接切換，不做動畫。
struct AmbientBackground: View {
    let artwork: ArtworkRef?
    /// 0–1，越高越亮（Fullscreen 用較亮的版本）
    var intensity: Double = 0.55

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.ambient) private var enabled = true

    var body: some View {
        ZStack {
            FinifyColor.Overflow.background
            // 放在 overlay 裡，封面的正方形比例才不會撐大整個版面
            Color.clear.overlay {
                if enabled, let artwork {
                    ArtworkView(artwork: artwork, cornerRadius: 0, elevation: .none)
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(1.4)
                        .blur(radius: 90, opaque: true)
                        .saturation(1.2)
                        .opacity(intensity)
                        .id(artwork)
                        .transition(.opacity)
                }
            }
            .clipped()
            // 壓暗並加上縱向漸層，確保前景文字對比。用 Abyss 而不是黑色，底色與 Modern 的深海藍一致，封面光暈照樣透出來
            LinearGradient(colors: [FinifyColor.Ocean.abyss.opacity(0.35), FinifyColor.Ocean.abyss.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        }
        .animation(reduceMotion ? nil : Motion.ambient, value: artwork)
        .drawingGroup()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
