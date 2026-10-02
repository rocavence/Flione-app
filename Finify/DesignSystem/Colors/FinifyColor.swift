import AppKit
import SwiftUI

/// Finify 色彩 token。Feature 只能使用這裡定義的顏色。
/// Brand color（accent）與 artwork ambient color 分離：ambient 由 `AmbientPalette` 從封面取色，不在這裡。
enum FinifyColor {
    /// 主要文字
    static let ink = dynamic(light: 0x141312, dark: 0xF4F1EC)
    /// 視窗底色
    static let paper = dynamic(light: 0xF7F5F1, dark: 0x0E0D0C)
    /// 區塊底色（列表 hover、輸入框）
    static let surface = dynamic(light: 0xEFECE6, dark: 0x181716)
    /// 浮起的元件（popover、player bar）
    static let elevated = dynamic(light: 0xFFFFFF, dark: 0x22201E)
    /// 次要文字、metadata
    static let muted = dynamic(light: 0x6E6A64, dark: 0x9A958E, highContrastLight: 0x45423E, highContrastDark: 0xC9C4BD)
    /// 第三層文字、placeholder
    static let faint = dynamic(light: 0xA19C94, dark: 0x5E5A55, highContrastLight: 0x6E6A64, highContrastDark: 0x9A958E)
    /// 分隔線
    static let hairline = dynamic(light: 0xE2DED7, dark: 0x2A2826, highContrastLight: 0x9A958E, highContrastDark: 0x6E6A64)
    /// 主要行動（Play 按鈕底色）
    static let primary = ink
    /// 主要行動上的文字 / icon
    static let onPrimary = paper
    /// 品牌 accent：Ember
    static let accent = dynamic(light: 0xE0502A, dark: 0xFF6A3D)
    /// 錯誤
    static let danger = dynamic(light: 0xC23A2B, dark: 0xFF6B5B)

    /// Overflow 永遠是深色環境，不隨系統外觀切換
    enum Overflow {
        static let background = Color(hex: 0x080807)
        static let ink = Color(hex: 0xF4F1EC)
        // 「增加對比」開啟時提高次要文字的不透明度（下次重繪時生效）
        private static var highContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
        static var muted: Color { Color(hex: 0xF4F1EC).opacity(highContrast ? 0.82 : 0.6) }
        static var faint: Color { Color(hex: 0xF4F1EC).opacity(highContrast ? 0.6 : 0.35) }
        static let control = Color.white.opacity(0.08)
        static let controlHover = Color.white.opacity(0.14)
    }

    /// 依外觀切換顏色。「增加對比」開啟時使用 high contrast 版本（未指定則沿用一般版本）。
    private static func dynamic(light: UInt32, dark: UInt32, highContrastLight: UInt32? = nil, highContrastDark: UInt32? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua]) {
            case .accessibilityHighContrastDarkAqua: NSColor(hex: highContrastDark ?? dark)
            case .accessibilityHighContrastAqua: NSColor(hex: highContrastLight ?? light)
            case .darkAqua: NSColor(hex: dark)
            default: NSColor(hex: light)
            }
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
