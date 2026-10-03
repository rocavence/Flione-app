import AppKit
import SwiftUI

/// Finify 色彩 token（Finity Visual Design System）。Feature 只能使用這裡定義的顏色。
/// 原則：藍色為主、紫色是氛圍、白色是重點；畫面約 70% 深藍、20% Finity Blue、7% 紫、3% 白。
/// Brand color（accent）與 artwork ambient color 分離：ambient 由封面取色，不在這裡。
enum FinifyColor {
    /// 主要文字（White / 淺色模式為深藍黑）
    static let ink = dynamic(light: 0x0D1633, dark: 0xFFFFFF)
    /// 視窗底色（Navy）
    static let paper = dynamic(light: 0xF4F6FC, dark: 0x0D1633)
    /// 側欄、面板（Deep Navy）
    static let panel = dynamic(light: 0xEAEEF8, dark: 0x111D40)
    /// 卡片、控制項（Blue Glass）
    static let surface = dynamic(light: 0xE3E8F5, dark: 0x182956)
    /// 浮起的元件（Elevated Blue）
    static let elevated = dynamic(light: 0xFFFFFF, dark: 0x1B2B56)
    /// 最深的底色（Ink）
    static let deep = dynamic(light: 0xDDE3F2, dark: 0x080D20)
    /// 次要文字（Secondary）
    static let muted = dynamic(light: 0x4A5878, dark: 0xAAB7D6, highContrastLight: 0x2A3654, highContrastDark: 0xD3DCF0)
    /// metadata（Tertiary）
    static let faint = dynamic(light: 0x7180A5, dark: 0x7180A5, highContrastLight: 0x4A5878, highContrastDark: 0xAAB7D6)
    /// 停用（Disabled）
    static let disabled = dynamic(light: 0xA3AEC8, dark: 0x526080)
    /// 分隔線（Divider #FFFFFF14）
    static let hairline = dynamicAlpha(light: (0x0D1633, 0.10), dark: (0xFFFFFF, 0.08), highContrastLight: (0x0D1633, 0.3), highContrastDark: (0xFFFFFF, 0.25))
    /// 玻璃表面（Glass White #FFFFFF0A）
    static let glass = dynamicAlpha(light: (0x0D1633, 0.04), dark: (0xFFFFFF, 0.04))
    /// hover 與浮起的玻璃（Glass Highlight #FFFFFF12）
    static let glassHighlight = dynamicAlpha(light: (0x0D1633, 0.07), dark: (0xFFFFFF, 0.07))
    /// 主要行動（Play 按鈕：白底深字）
    static let primary = dynamic(light: 0x0D1633, dark: 0xEAF0FF)
    /// 主要行動上的文字 / icon
    static let onPrimary = dynamic(light: 0xFFFFFF, dark: 0x0D1633)
    /// 品牌 accent：Finity Blue（Active、選取、播放中、進度）
    static let accent = dynamic(light: 0x2F6BFF, dark: 0x3E7CF6)
    /// Sky Blue：次要 accent
    static let sky = Color(hex: 0x6AA0FF)
    /// Aurora Violet：漸層與氛圍
    static let violet = Color(hex: 0x9B8CFF)
    /// Soft Lavender：光暈
    static let lavender = Color(hex: 0xBDBDFF)
    /// Ice：重點文字
    static let ice = Color(hex: 0xEAF0FF)
    /// 錯誤
    static let danger = dynamic(light: 0xC23A2B, dark: 0xFF6B7A)

    /// Finity Aurora 漸層：只用在 Hero、選取、品牌重點，不當一般填色
    static let aurora = LinearGradient(colors: [Color(hex: 0x1D4ED8), Color(hex: 0x2F6BFF), Color(hex: 0x6A8DFF), Color(hex: 0xA78BFA)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Overflow 永遠是深色環境，不隨系統外觀切換
    enum Overflow {
        static let background = Color(hex: 0x080D20)
        static let ink = Color(hex: 0xFFFFFF)
        // 「增加對比」開啟時提高次要文字的不透明度（下次重繪時生效）
        private static var highContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
        static var muted: Color { Color(hex: 0xAAB7D6).opacity(highContrast ? 1 : 0.9) }
        static var faint: Color { Color(hex: 0x7180A5).opacity(highContrast ? 1 : 0.9) }
        static let control = Color.white.opacity(0.07)
        static let controlHover = Color.white.opacity(0.12)
    }

    private static func dynamicAlpha(light: (UInt32, CGFloat), dark: (UInt32, CGFloat),
                                     highContrastLight: (UInt32, CGFloat)? = nil, highContrastDark: (UInt32, CGFloat)? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let pick: (UInt32, CGFloat)
            switch appearance.bestMatch(from: [.darkAqua, .aqua, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua]) {
            case .accessibilityHighContrastDarkAqua: pick = highContrastDark ?? dark
            case .accessibilityHighContrastAqua: pick = highContrastLight ?? light
            case .darkAqua: pick = dark
            default: pick = light
            }
            return NSColor(hex: pick.0).withAlphaComponent(pick.1)
        })
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
