import AppKit
import SwiftUI

/// Finify 色彩 token（Flione Color System：deep-ocean／bioluminescent）。Feature 只能使用這裡定義的顏色。
/// 原則：深色為主、藍色建立環境、紫色增加深度、橘色帶來生命、白色提供清晰；
/// 畫面約 60% Abyss／深藍、20% Deep Ocean、12% 藍、5% 紫、3% 橘。
/// 淺色模式文件沒有定義，沿用原本的淺色值，只換品牌色。
/// Brand color 與 artwork ambient color 分離：ambient 由封面取色，不在這裡。
enum FinifyColor {
    /// 深海表面層級（深色環境固定值；Infinity／Cover Flow、玻璃色調、Hero 用）
    enum Ocean {
        /// Surface 0：App 背景（Abyss）
        static let abyss = Color(hex: 0x061426)
        /// Surface 1：側欄
        static let surface1 = Color(hex: 0x0A1D3C)
        /// Surface 2：卡片
        static let surface2 = Color(hex: 0x10264B)
        /// Surface 3：浮起的卡片
        static let surface3 = Color(hex: 0x14305A)
        /// 選取中的表面（Surface Active）
        static let active = Color(hex: 0x183D78)
        /// Deep Ocean：導覽、較亮的底
        static let deepOcean = Color(hex: 0x0A2A67)
    }

    /// 主要文字（White／淺色模式為深藍黑）
    static let ink = dynamic(light: 0x0B1B33, dark: 0xFFFFFF)
    /// 視窗底色（Surface 0 Abyss）
    static let paper = dynamic(light: 0xF4F6FC, dark: 0x061426)
    /// 側欄、面板（Surface 1）
    static let panel = dynamic(light: 0xEAEEF8, dark: 0x0A1D3C)
    /// 卡片、控制項（Surface 2）
    static let surface = dynamic(light: 0xE3E8F5, dark: 0x10264B)
    /// 浮起的元件（Surface 3）
    static let elevated = dynamic(light: 0xFFFFFF, dark: 0x14305A)
    /// 選取中的表面（Surface Active）
    static let active = dynamic(light: 0xDCE6FF, dark: 0x183D78)
    /// 最深的底色
    static let deep = dynamic(light: 0xDDE3F2, dark: 0x061426)
    /// 次要文字（Secondary）
    static let muted = dynamic(light: 0x4A5878, dark: 0xAFC0DF, highContrastLight: 0x2A3654, highContrastDark: 0xD6E0F2)
    /// metadata（Tertiary）
    static let faint = dynamic(light: 0x7185AA, dark: 0x7185AA, highContrastLight: 0x4A5878, highContrastDark: 0xAFC0DF)
    /// 停用（Disabled）
    static let disabled = dynamic(light: 0xA3AEC8, dark: 0x4D6085)
    /// 邊框、分隔線（#FFFFFF12）
    static let hairline = dynamicAlpha(light: (0x0B1B33, 0.10), dark: (0xFFFFFF, 0.07), highContrastLight: (0x0B1B33, 0.3), highContrastDark: (0xFFFFFF, 0.25))
    /// 玻璃表面、hover（#FFFFFF0A）
    static let glass = dynamicAlpha(light: (0x0B1B33, 0.04), dark: (0xFFFFFF, 0.04))
    /// 浮起的玻璃（#FFFFFF12）
    static let glassHighlight = dynamicAlpha(light: (0x0B1B33, 0.07), dark: (0xFFFFFF, 0.07))
    /// 主要行動（Play 按鈕：Light 底深字）
    static let primary = dynamic(light: 0x0B1B33, dark: 0xEAF2FF)
    /// 主要行動上的文字／icon
    static let onPrimary = dynamic(light: 0xFFFFFF, dark: 0x061426)
    /// Flione Blue：按鈕、連結、選取、focus ring、播放控制
    static let accent = Color(hex: 0x2F6BFF)
    /// Ice Blue：次要 accent、hover、封面光暈
    static let sky = Color(hex: 0x6AA8FF)
    /// Aurora Violet：只當氛圍（漸層、環境光），不用在按鈕與導覽
    static let violet = Color(hex: 0xA78BFF)
    /// Light：重點文字
    static let ice = Color(hex: 0xEAF2FF)
    /// Bright Coral Orange：播放進度、正在播放、重要互動。不可成為主要 UI 色
    static let orange = Color(hex: 0xFF8A3D)
    /// Orange Highlight：光暈中心、柔和過渡（少量使用）
    static let orangeHighlight = Color(hex: 0xFFB36B)
    /// Orange Glow
    static let orangeGlow = Color(hex: 0xFF8A3D).opacity(0.24)

    // 系統狀態（只用在真正的狀態）
    static let success = Color(hex: 0x55D6A6)
    static let warning = Color(hex: 0xFFB84D)
    static let danger = dynamic(light: 0xC23A2B, dark: 0xFF5F6D)
    static let info = Color(hex: 0x6AA8FF)

    /// Flione Aurora 漸層：藍 → 冰藍 → 紫 → 橘。橘色只在視覺焦點，不平均分布；只用在 Hero 與大面積氛圍，不用在按鈕
    static let aurora = LinearGradient(stops: [.init(color: Color(hex: 0x2F6BFF), location: 0), .init(color: Color(hex: 0x6AA8FF), location: 0.45),
                                               .init(color: Color(hex: 0xA78BFF), location: 0.8), .init(color: Color(hex: 0xFF8A3D), location: 1)],
                                       startPoint: .bottomLeading, endPoint: .topTrailing)

    /// Infinity／Cover Flow 永遠是深色環境，不隨系統外觀切換
    enum Overflow {
        static let background = Ocean.abyss
        static let ink = Color(hex: 0xFFFFFF)
        // 「增加對比」開啟時提高次要文字的不透明度（下次重繪時生效）
        private static var highContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
        static var muted: Color { Color(hex: 0xAFC0DF).opacity(highContrast ? 1 : 0.9) }
        static var faint: Color { Color(hex: 0x7185AA).opacity(highContrast ? 1 : 0.9) }
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
