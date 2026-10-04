import AppKit

/// 介面語言。翻譯在 `Resources/Localizable.xcstrings`（String Catalog）。
/// 新增語言：在 catalog 加入該語言的翻譯，再在這裡加一個 case（rawValue 是語言代碼）。
/// 選擇寫進 app 自己的 `AppleLanguages`，系統在下次啟動時套用，所以切換後要重新啟動。
enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case english = "en"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case portuguese = "pt-BR"

    private static let key = "FlioneLanguage"

    /// 語言名稱一律用該語言本身的寫法，不翻譯（看不懂目前語言的人也找得到自己的語言）
    var title: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .english: LocalizedStringResource(stringLiteral: "English")
        case .traditionalChinese: LocalizedStringResource(stringLiteral: "繁體中文")
        case .japanese: LocalizedStringResource(stringLiteral: "日本語")
        case .korean: LocalizedStringResource(stringLiteral: "한국어")
        case .spanish: LocalizedStringResource(stringLiteral: "Español")
        case .portuguese: LocalizedStringResource(stringLiteral: "Português (Brasil)")
        }
    }

    /// 介面實際使用的語言（選「系統」時是系統挑中的那一個），給 AI 探索指定回答語言
    static var effective: AppLanguage {
        if launched != .system { return launched }
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return allCases.first { $0 != .system && code.hasPrefix($0.rawValue) } ?? .english
    }

    /// 給模型的語言說明（英文）
    var modelInstruction: String {
        switch self {
        case .traditionalChinese: "Traditional Chinese as used in Taiwan"
        case .japanese: "Japanese"
        case .korean: "Korean"
        case .spanish: "Spanish"
        case .portuguese: "Brazilian Portuguese"
        case .system, .english: "English"
        }
    }

    static var saved: AppLanguage {
        UserDefaults.standard.string(forKey: key).flatMap(AppLanguage.init) ?? .system
    }

    /// 這次啟動時套用的語言；與 `saved` 不同代表要重新啟動才會生效
    static let launched = saved

    static func save(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: key)
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    /// 開一個新的 Flione，再結束目前這個
    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
