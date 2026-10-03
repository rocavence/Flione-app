import SwiftUI

/// Finify 唯一的 icon 入口。所有 UI icon 都經過這裡，不直接使用 Image。
struct FinifyIcon: View {
    enum Weight: String, Sendable {
        /// 一般 UI
        case outline
        /// Active / Selected / Primary action
        case filled
    }

    enum Size: CGFloat, Sendable {
        case compact = 16
        case standard = 20
        case primary = 24
        case emphasis = 28
        case large = 32
    }

    let icon: Reicon
    var weight: Weight = .outline
    var size: Size = .standard

    init(_ icon: Reicon, weight: Weight = .outline, size: Size = .standard) {
        self.icon = icon
        self.weight = weight
        self.size = size
    }

    var body: some View {
        Image("Reicon/\(icon.rawValue).\(weight.rawValue)")
            .renderingMode(.template)
            .resizable()
            .frame(width: size.rawValue, height: size.rawValue)
            .scaleEffect(icon.opticalScale)
            .accessibilityHidden(true)
    }
}

extension Reicon {
    /// 圖形幾乎塞滿 24×24 的 icon 縮小一點，與旁邊的 icon 看起來一樣大（例如歌詞與佇列並排）
    var opticalScale: CGFloat {
        switch self {
        case .notes2: 0.85
        default: 1
        }
    }
}
