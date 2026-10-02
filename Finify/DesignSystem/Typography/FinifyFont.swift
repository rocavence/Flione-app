import SwiftUI

/// Finify 字級 token（SF Pro）。原則：字比 UI 安靜，避免大量 bold。
enum FinifyFont {
    /// 專輯 / 藝人頁標題
    case display
    /// 頁面標題（Home 問候語）
    case title
    /// 區塊標題（Recently Added）
    case heading
    /// 卡片標題、曲名強調
    case subheading
    /// 一般內文、曲名
    case body
    /// 內文強調
    case bodyEmphasis
    /// metadata、時間
    case caption
    /// 小型標籤
    case micro

    var font: Font {
        switch self {
        case .display: .system(size: 44, weight: .semibold)
        case .title: .system(size: 28, weight: .semibold)
        case .heading: .system(size: 19, weight: .semibold)
        case .subheading: .system(size: 14, weight: .medium)
        case .body: .system(size: 13, weight: .regular)
        case .bodyEmphasis: .system(size: 13, weight: .medium)
        case .caption: .system(size: 11, weight: .regular)
        case .micro: .system(size: 10, weight: .medium)
        }
    }

    /// 大字收緊字距，小字維持預設
    var tracking: CGFloat {
        switch self {
        case .display: -1.2
        case .title: -0.6
        case .heading: -0.3
        case .micro: 0.6
        default: 0
        }
    }
}

extension View {
    func finifyFont(_ style: FinifyFont) -> some View {
        font(style.font).tracking(style.tracking)
    }
}
