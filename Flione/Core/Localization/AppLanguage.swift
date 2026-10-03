import AppKit

/// 介面語言。翻譯在 `Resources/Localizable.xcstrings`（String Catalog）。
/// 新增語言：在 catalog 加入該語言的翻譯，再在這裡加一個 case（rawValue 是語言代碼）。
/// 選擇寫進 app 自己的 `AppleLanguages`，系統在下次啟動時套用，所以切換後要重新啟動。
enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case english = "en"
    case traditionalChinese = "zh-Hant"

    private static let key = "FinifyLanguage"

    /// 語言名稱一律用該語言本身的寫法，不翻譯（看不懂目前語言的人也找得到自己的語言）
    var title: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .english: LocalizedStringResource(stringLiteral: "English")
        case .traditionalChinese: LocalizedStringResource(stringLiteral: "繁體中文")
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
