import SwiftUI

/// Flione 唯一的 icon 入口。所有 UI icon 都經過這裡，不直接使用 Image。
struct FlioneIcon: View {
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
            .accessibilityHidden(true)
    }
}
