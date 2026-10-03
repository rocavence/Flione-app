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

    var font: Font { font(scale: 1) }

    /// 依「睫狀肌舒適」放大；大標題本來就大，只放大一半的比例，避免撐破固定高度的頁首
    func font(scale: CGFloat) -> Font {
        let factor = isLarge ? 1 + (scale - 1) / 2 : scale
        return .system(size: (size * factor * 2).rounded() / 2, weight: weight)
    }

    private var size: CGFloat {
        switch self {
        case .display: 44
        case .title: 28
        case .heading: 19
        case .subheading: 14
        case .body, .bodyEmphasis: 13
        case .caption: 11
        case .micro: 10
        }
    }

    private var weight: Font.Weight {
        switch self {
        case .display, .title, .heading: .semibold
        case .subheading, .bodyEmphasis, .micro: .medium
        case .body, .caption: .regular
        }
    }

    private var isLarge: Bool { self == .display || self == .title }

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

/// 睫狀肌舒適：三種模式的文字放大程度（設定 → 一般）
enum TextComfort: Int, CaseIterable {
    case standard, relaxed, moreRelaxed

    /// 每一級放大一點點
    var scale: CGFloat {
        switch self {
        case .standard: 1
        case .relaxed: 1.08
        case .moreRelaxed: 1.16
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .standard: "Default"
        case .relaxed: "Relaxed"
        case .moreRelaxed: "More relaxed"
        }
    }
}

extension EnvironmentValues {
    /// finifyFont 的放大倍率；由 StandardRootView／OverflowRootView 依設定提供（D41）
    @Entry var finifyTextScale: CGFloat = 1
}

extension View {
    func finifyFont(_ style: FinifyFont) -> some View {
        modifier(FinifyFontModifier(style: style))
    }
}

private struct FinifyFontModifier: ViewModifier {
    let style: FinifyFont
    @Environment(\.finifyTextScale) private var scale

    func body(content: Content) -> some View {
        content.font(style.font(scale: scale)).tracking(style.tracking)
    }
}
