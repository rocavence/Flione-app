import SwiftUI

enum FlioneShadow {
    struct Style {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
    }

    /// 一般 artwork
    static let artwork = Style(color: .black.opacity(0.18), radius: 8, y: 4)
    /// hover 中的 artwork
    static let artworkHover = Style(color: .black.opacity(0.28), radius: 16, y: 8)
    /// 正在播放的 album（Playing elevation）
    static let playing = Style(color: .black.opacity(0.45), radius: 28, y: 14)
    /// 浮起的面板
    static let elevated = Style(color: .black.opacity(0.16), radius: 20, y: 8)
}

extension View {
    func flioneShadow(_ style: FlioneShadow.Style) -> some View {
        shadow(color: style.color, radius: style.radius, y: style.y)
    }
}
