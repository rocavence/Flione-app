import CoreGraphics

enum Radius {
    static let small: CGFloat = 4
    static let ui: CGFloat = 8
    static let card: CGFloat = 12
    static let large: CGFloat = 16
    static let hero: CGFloat = 24
    static let floating: CGFloat = 32
    /// 小尺寸 artwork 的圓角（縮圖、列表）
    static let artwork: CGFloat = 4

    /// 依封面邊長決定圓角：約 5%，介於 3–16pt。搭配 continuous（macOS 的連續曲線）使用，
    /// 大封面有明顯的 macOS 大圓角，小縮圖不會圓得像按鈕
    static func artwork(for side: CGFloat) -> CGFloat {
        min(16, max(3, (side * 0.05).rounded()))
    }
}
