import Foundation

/// 使用者可選的配色（設定 → 一般 → 配色，D37）。
/// 只換「環境」：深色五層底色、淺色模式底色、帶色調的次要文字、互動色（取代 Flione Blue）。
/// 播放用的橘色、狀態色不隨主題改變：橘色代表「正在播放」，在每個主題都要一眼認得出來。
/// 新增配色：加一個 case 和一組 `Palette`。避開琥珀／橘色系，免得和播放中的橘色混淆。
enum ColorTheme: String, CaseIterable, Sendable {
    case deepOcean, silence, midnight, aurora, emerald, bordeaux, glacier

    struct Palette: Sendable {
        // 深色環境（Modern 深色、Infinity、Cover Flow）
        let abyss: UInt32
        let surface1: UInt32
        let surface2: UInt32
        let surface3: UInt32
        let active: UInt32
        let deepOcean: UInt32
        let mutedDark: UInt32
        let faintDark: UInt32
        let disabledDark: UInt32
        // 淺色環境（Modern 淺色）
        let paperLight: UInt32
        let panelLight: UInt32
        let surfaceLight: UInt32
        let activeLight: UInt32
        let deepLight: UInt32
        let inkLight: UInt32
        let mutedLight: UInt32
        let faintLight: UInt32
        // 互動色與它的淺色版、重點文字
        let accent: UInt32
        let sky: UInt32
        let ice: UInt32
    }

    var title: LocalizedStringResource {
        switch self {
        case .deepOcean: "Deep Ocean"
        case .silence: "Silence"
        case .midnight: "Midnight"
        case .aurora: "Aurora"
        case .emerald: "Emerald"
        case .bordeaux: "Bordeaux"
        case .glacier: "Glacier"
        }
    }

    var palette: Palette {
        switch self {
        case .deepOcean:
            // Flione 品牌原色（docs/brand/color-system.md）
            Palette(abyss: 0x061426, surface1: 0x0A1D3C, surface2: 0x10264B, surface3: 0x14305A, active: 0x183D78, deepOcean: 0x0A2A67,
                    mutedDark: 0xAFC0DF, faintDark: 0x7185AA, disabledDark: 0x4D6085,
                    paperLight: 0xF4F6FC, panelLight: 0xEAEEF8, surfaceLight: 0xE3E8F5, activeLight: 0xDCE6FF, deepLight: 0xDDE3F2,
                    inkLight: 0x0B1B33, mutedLight: 0x4A5878, faintLight: 0x7185AA,
                    accent: 0x2F6BFF, sky: 0x6AA8FF, ice: 0xEAF2FF)
        case .silence:
            // 寂靜：完全中性的灰黑，不帶色調；互動色也是中性灰，像系統預設的石墨色
            Palette(abyss: 0x0E0E10, surface1: 0x161618, surface2: 0x1D1D20, surface3: 0x252528, active: 0x323236, deepOcean: 0x1A1A1D,
                    mutedDark: 0xB8B8BD, faintDark: 0x7C7C82, disabledDark: 0x505055,
                    paperLight: 0xF5F5F6, panelLight: 0xECECEE, surfaceLight: 0xE4E4E7, activeLight: 0xDEDEE2, deepLight: 0xE2E2E5,
                    inkLight: 0x18181A, mutedLight: 0x56565C, faintLight: 0x7C7C82,
                    accent: 0x8E8E93, sky: 0xC7C7CC, ice: 0xF2F2F7)
        case .midnight:
            // 石墨黑：偏冷，互動色是長春花藍
            Palette(abyss: 0x0B0D12, surface1: 0x13161D, surface2: 0x1A1E27, surface3: 0x222733, active: 0x2C3342, deepOcean: 0x181C25,
                    mutedDark: 0xB4BACA, faintDark: 0x7A8293, disabledDark: 0x4F5666,
                    paperLight: 0xF5F6F8, panelLight: 0xECEEF1, surfaceLight: 0xE4E7EB, activeLight: 0xE0E5F0, deepLight: 0xE1E4E9,
                    inkLight: 0x15181E, mutedLight: 0x51586A, faintLight: 0x7A8293,
                    accent: 0x7C9CFF, sky: 0xAFC2FF, ice: 0xEEF1F8)
        case .aurora:
            // 夜紫
            Palette(abyss: 0x0D0A1E, surface1: 0x15102E, surface2: 0x1D173D, surface3: 0x251E4C, active: 0x33296A, deepOcean: 0x21175A,
                    mutedDark: 0xC4B8E6, faintDark: 0x8679AA, disabledDark: 0x5B4D85,
                    paperLight: 0xF6F4FC, panelLight: 0xEEEAF8, surfaceLight: 0xE7E2F5, activeLight: 0xE6DCFF, deepLight: 0xE3DEF2,
                    inkLight: 0x1A1233, mutedLight: 0x5A4E7A, faintLight: 0x8679AA,
                    accent: 0x8B6CFF, sky: 0xB9A6FF, ice: 0xF1ECFF)
        case .emerald:
            // 墨綠
            Palette(abyss: 0x041410, surface1: 0x081F19, surface2: 0x0D2A22, surface3: 0x12362C, active: 0x18483B, deepOcean: 0x0A3328,
                    mutedDark: 0xAFD3C4, faintDark: 0x6E9184, disabledDark: 0x456B5D,
                    paperLight: 0xF3F8F6, panelLight: 0xE8F1ED, surfaceLight: 0xE0EBE6, activeLight: 0xD6EDE3, deepLight: 0xDCE8E3,
                    inkLight: 0x0B2219, mutedLight: 0x45685B, faintLight: 0x6E9184,
                    accent: 0x22B07D, sky: 0x7FD8B5, ice: 0xEAFBF3)
        case .bordeaux:
            // 酒紅黑：溫暖、絲絨
            Palette(abyss: 0x16080F, surface1: 0x210D17, surface2: 0x2C1320, surface3: 0x381929, active: 0x4C2237, deepOcean: 0x3A1124,
                    mutedDark: 0xE2BFCD, faintDark: 0x9E7A88, disabledDark: 0x6E4A5A,
                    paperLight: 0xFAF4F6, panelLight: 0xF3EAEE, surfaceLight: 0xEDE2E7, activeLight: 0xF8DCE6, deepLight: 0xEEE0E6,
                    inkLight: 0x2A0F1C, mutedLight: 0x74505F, faintLight: 0x9E7A88,
                    accent: 0xE14F7B, sky: 0xF29BB5, ice: 0xFDEFF4)
        case .glacier:
            // 冰藍黑：清冷、俐落
            Palette(abyss: 0x081418, surface1: 0x0D1F25, surface2: 0x132A31, surface3: 0x19363E, active: 0x204A55, deepOcean: 0x0E3440,
                    mutedDark: 0xAFD0D9, faintDark: 0x6F8F98, disabledDark: 0x466A75,
                    paperLight: 0xF3F8F9, panelLight: 0xE8F1F3, surfaceLight: 0xE0EBEE, activeLight: 0xD5EDF3, deepLight: 0xDBE7EA,
                    inkLight: 0x0B2128, mutedLight: 0x466670, faintLight: 0x6F8F98,
                    accent: 0x2BA9D6, sky: 0x86D3EE, ice: 0xEAF8FC)
        }
    }

    private static let key = "FinifyColorTheme"

    /// 目前的配色。色彩 token 在繪製時讀這個值（可能在背景執行緒），所以不綁 MainActor；只在設定變更時寫入
    nonisolated(unsafe) private(set) static var current: ColorTheme =
        UserDefaults.standard.string(forKey: key).flatMap(ColorTheme.init) ?? .deepOcean

    static func apply(_ theme: ColorTheme) {
        current = theme
        UserDefaults.standard.set(theme.rawValue, forKey: key)
    }
}
