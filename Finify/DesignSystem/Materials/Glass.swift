import SwiftUI

/// Liquid Glass：macOS 26 以上用系統的 `.glassEffect`，舊系統退回半透明底色加細邊。
/// 只用在浮在封面上的元件（Overflow 的浮動控制、Hero 上的按鈕），一般頁面不用。
/// 做法參考 Kaset（MIT）的 LiquidGlassCompat。
extension View {
    /// `backing`：墊在玻璃上的半透明底色。內容是文字為主的面板（搜尋、提示）需要它，否則後面的畫面會透出來影響閱讀
    func finifyGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false, backing: Color? = nil,
                                         fallback: Color) -> some View {
        modifier(FinifyGlass(shape: shape, tint: tint, interactive: interactive, backing: backing, fallback: fallback))
    }
}

private struct FinifyGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    let backing: Color?
    let fallback: Color

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background(backing ?? .clear, in: shape)
                .glassEffect(glass, in: shape)
        } else {
            content
                .background(fallback, in: shape)
                .overlay { shape.strokeBorder(.white.opacity(0.1), lineWidth: 1) }
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}
