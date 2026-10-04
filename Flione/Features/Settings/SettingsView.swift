import SwiftUI

enum ThemePreference: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var title: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// 設定鍵集中定義，避免各處拼錯字串
enum SettingsKey {
    static let theme = "FinifyTheme"
    /// Modern 的背景光暈（迷你播放器也跟著這個）
    static let ambient = "FinifyAmbient"
    /// Infinity 的模糊封面背景
    static let wallAmbient = "FinifyWallAmbient"
    static let menuBar = "FinifyMenuBar"
    static let floatingOnTop = "FinifyFloatingOnTop"
    static let wallDrift = "FinifyWallDrift"
    /// Infinity 漂移速度倍率（0.5／1／2）
    static let wallDriftSpeed = "FinifyWallDriftSpeed"
    /// Infinity 一直自動捲動（滑鼠在牆上也不停）；頂部列的開關
    static let wallAutoScroll = "FinifyWallAutoScroll"
    /// Infinity 封面圓角；關掉時封面之間也沒有間距
    static let wallRounded = "FinifyWallRounded"
    /// Cover Flow 封面圓角
    static let flowRounded = "FinifyFlowRounded"
    /// Cover Flow 兩側封面變暗的程度（0 = 不變暗，預設 0.25）
    static let flowDim = "FinifyFlowDim"
    /// Cover Flow 停下來後背景光暈暗下來的程度（0 = 不變暗，維持移動時的亮度）
    static let flowSettleDim = "FinifyFlowSettleDim"
    static let trackNotifications = "FinifyTrackNotifications"
    static let onlineLyrics = "FinifyOnlineLyrics"
    /// 睫狀肌舒適：Modern 文字放大的級數（TextComfort）
    static let textComfort = "FinifyTextComfort"
}

/// 設定卡片：浮在主視窗上（⌘, 或側欄齒輪打開，Esc 或點外面關閉）。
/// 版面：標題、分頁膠囊、關閉鈕；每一列左邊是名稱與說明，右邊是控制項。
struct SettingsCard: View {
    enum Tab: String, CaseIterable {
        case general, modern, infinity, coverFlow, jellyfin, youtube, about

        var title: LocalizedStringResource {
            switch self {
            case .general: "General"
            // 模式與音樂來源的名稱是產品名，不翻譯
            case .modern: LocalizedStringResource(stringLiteral: ViewMode.standard.title)
            case .infinity: LocalizedStringResource(stringLiteral: ViewMode.infinity.title)
            case .coverFlow: LocalizedStringResource(stringLiteral: ViewMode.coverFlow.title)
            case .jellyfin: LocalizedStringResource(stringLiteral: MusicSource.jellyfin.title)
            case .youtube: LocalizedStringResource(stringLiteral: MusicSource.youtube.title)
            case .about: "About"
            }
        }

        var icon: Reicon {
            switch self {
            case .general: .setting2
            case .modern: ViewMode.standard.icon
            case .infinity: ViewMode.infinity.icon
            case .coverFlow: ViewMode.coverFlow.icon
            case .jellyfin: .server
            case .youtube: .music
            case .about: .infoCircle
            }
        }

        /// 側欄的分組：一般／顯示模式／音樂來源／關於
        static let groups: [(title: LocalizedStringResource?, tabs: [Tab])] = [
            (nil, [.general]),
            ("View Modes", [.modern, .infinity, .coverFlow]),
            ("Music Sources", [.jellyfin, .youtube]),
            (nil, [.about]),
        ]
    }

    @Environment(AppEnvironment.self) private var app
    @State private var tab: Tab = {
        #if DEBUG
        // -FinifyDemoSettingsTab <分頁>：截圖用，直接打開指定分頁
        if let raw = UserDefaults.standard.string(forKey: "FinifyDemoSettingsTab"), let tab = Tab(rawValue: raw) { return tab }
        #endif
        return .general
    }()

    var body: some View {
        // 左側分頁（像系統設定），右側內容；標題與關閉鈕在最上面
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings").finifyFont(.title).foregroundStyle(FinifyColor.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, Spacing.s8)
                    .padding(.bottom, Spacing.s20)
                TabSidebar(selection: $tab)
                Spacer(minLength: 0)
            }
            .frame(width: 184, alignment: .leading)
            .padding(.trailing, Spacing.s16)

            FinifyColor.hairline.frame(width: 1).padding(.vertical, -Spacing.s32)

            VStack(alignment: .leading, spacing: 0) {
                Text(tab.title).finifyFont(.heading).foregroundStyle(FinifyColor.ink)
                    .frame(height: 36, alignment: .leading)
                    .padding(.bottom, Spacing.s4)
                content
            }
            .padding(.leading, Spacing.s24)
            // 右側只用剩下的寬度，內容再寬也不會把整張卡片撐開、擠掉左邊的留白
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.s32)
        // 固定大小：切換分頁時卡片不會因為內容長短而上下跳動
        .frame(width: 900, height: 600)
        .background {
            ZStack {
                FinifyColor.elevated
                // 卡片內的淡淡光暈，和 Modern 的背景光暈同一個語彙
                RadialGradient(colors: [FinifyColor.accent.opacity(0.08), .clear], center: .top, startRadius: 0, endRadius: 420)
                RadialGradient(colors: [FinifyColor.violet.opacity(0.08), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 360)
            }
        }
        .overlay(alignment: .topTrailing) {
            CloseButton { app.isSettingsPresented = false }
                .padding(Spacing.s16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(FinifyColor.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 40, y: 20)
        .tint(FinifyColor.accent)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
    }
}

extension SettingsCard {
    @ViewBuilder
    fileprivate var content: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 0) {
                switch tab {
                case .general: GeneralSettings()
                case .modern: ModernSettings()
                case .infinity: InfinitySettings()
                case .coverFlow: CoverFlowSettings()
                case .jellyfin: SourceSettings(source: .jellyfin)
                case .youtube: SourceSettings(source: .youtube)
                case .about: AboutSettings()
                }
                Color.clear.frame(height: 0).id("bottom")
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        // 「永遠顯示捲軸」時系統會畫一條粗的捲軸貼著內容；設定的內容不長，改用底部漸隱提示還有更多
        .scrollIndicators(.never)
        .mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 28)
            }
        }
        #if DEBUG
        // -FinifyDemoSettingsScroll YES：截圖用，打開後捲到最下面
        .task {
            guard UserDefaults.standard.bool(forKey: "FinifyDemoSettingsScroll") else { return }
            try? await Task.sleep(for: .seconds(1))
            proxy.scrollTo("bottom", anchor: .bottom)
        }
        #endif
        }
    }
}

/// 一列設定：左邊名稱與說明，右邊控制項；列與列之間用細線分隔
private struct SettingRow<Control: View>: View {
    let title: LocalizedStringResource
    var detail: LocalizedStringResource?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.s24) {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text(title).finifyFont(.subheading).foregroundStyle(FinifyColor.ink)
                if let detail {
                    Text(detail).finifyFont(.body).foregroundStyle(FinifyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            control
        }
        .padding(.vertical, Spacing.s16)
        .overlay(alignment: .bottom) { FinifyColor.hairline.frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

private struct SettingToggle: View {
    let title: LocalizedStringResource
    var detail: LocalizedStringResource?
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(title: title, detail: detail) {
            Toggle(isOn: $isOn) { Text(title) }.labelsHidden().toggleStyle(PillSwitchStyle())
        }
    }
}

/// 開關：開啟時是主色。系統的 switch 在視窗不在前景時會變灰，這裡固定顯示顏色
private struct PillSwitchStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                // 開啟時用主色（與選取的分頁、主要按鈕相同），各種配色都清楚；強調色在「寂靜」是灰色，開著也像關著
                .fill(configuration.isOn ? FinifyColor.primary : FinifyColor.glassHighlight)
                .overlay(Capsule().strokeBorder(FinifyColor.hairline, lineWidth: configuration.isOn ? 0 : 1))
                .frame(width: 42, height: 24)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(configuration.isOn ? FinifyColor.onPrimary : .white)
                        .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1).padding(3)
                }
                .animation(reduceMotion ? nil : Motion.micro, value: configuration.isOn)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// 右側的膠囊按鈕（例如 Clear、Refresh）：淡淡的 accent 底
private struct PillButton: View {
    let title: LocalizedStringResource
    var destructive = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .finifyFont(.bodyEmphasis)
                .foregroundStyle(color)
                .padding(.horizontal, Spacing.s16)
                .frame(height: 32)
                .background(color.opacity(hovering && isEnabled ? 0.2 : 0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
    }

    private var color: Color { destructive ? FinifyColor.danger : FinifyColor.accent }
}

/// 右側的選單（目前值＋上下箭頭），外觀與 PillButton 一致
private struct PillMenu<Value: Hashable>: View {
    let title: LocalizedStringResource
    @Binding var selection: Value
    let options: [(Value, LocalizedStringResource)]

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            } label: { Text(title) }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: Spacing.s4) {
                if let current = options.first(where: { $0.0 == selection }) { Text(current.1) }
                FinifyIcon(.chevronDown, size: .compact).scaleEffect(0.75)
            }
            .finifyFont(.bodyEmphasis)
            .foregroundStyle(FinifyColor.accent)
            .padding(.horizontal, Spacing.s12)
            .frame(height: 32)
            .background(FinifyColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text(title))
    }
}

/// 頂端的分頁膠囊
/// 左側的分頁：圖示＋名稱，分成一般／顯示模式／音樂來源／關於幾組，像系統設定的側欄
private struct TabSidebar: View {
    @Binding var selection: SettingsCard.Tab

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(SettingsCard.Tab.groups.enumerated()), id: \.offset) { index, group in
                if let title = group.title {
                    Text(title)
                        .finifyFont(.micro)
                        .foregroundStyle(FinifyColor.faint)
                        .padding(.horizontal, Spacing.s8)
                        .padding(.top, Spacing.s16)
                        .padding(.bottom, Spacing.s4)
                        .accessibilityAddTraits(.isHeader)
                } else if index > 0 {
                    Spacer().frame(height: Spacing.s16)
                }
                ForEach(group.tabs, id: \.self) { tab in
                    TabSidebarRow(tab: tab, selected: tab == selection) { selection = tab }
                }
            }
        }
        .animation(Motion.micro, value: selection)
    }
}

private struct TabSidebarRow: View {
    let tab: SettingsCard.Tab
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s8) {
                FinifyIcon(tab.icon, weight: selected ? .filled : .outline, size: .compact)
                    .frame(width: 20)
                Text(tab.title)
                    .finifyFont(selected ? .bodyEmphasis : .body)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? FinifyColor.onPrimary : FinifyColor.ink.opacity(0.82))
            .padding(.horizontal, Spacing.s8)
            .frame(height: 32)
            .background(selected ? FinifyColor.primary : (hovering ? FinifyColor.glassHighlight : .clear),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct CloseButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            // 小而安靜：平常只有圖示，滑過才出現淡淡的圓底（與視窗的關閉鈕同一個份量）
            FinifyIcon(.x, size: .compact)
                .scaleEffect(0.8)
                .foregroundStyle(hovering ? FinifyColor.ink : FinifyColor.muted)
                .frame(width: 28, height: 28)
                .background(hovering ? FinifyColor.glassHighlight : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .help("Close (Esc)")
        .accessibilityLabel("Close Settings")
    }
}

private struct GeneralSettings: View {
    @Environment(AppEnvironment.self) private var app
    @State private var cacheSize: String = "…"
    @AppStorage(SettingsKey.menuBar) private var showsMenuBar = true
    @AppStorage(SettingsKey.trackNotifications) private var trackNotifications = true
    @AppStorage(SettingsKey.onlineLyrics) private var onlineLyrics = false
    @AppStorage(ImagePipeline.diskLimitKey) private var cacheLimit = 400

    @State private var language = AppLanguage.saved
    @AppStorage(SettingsKey.textComfort) private var comfort = TextComfort.standard


    /// 200 → 200 MB、1500 → 1.5 GB
    private static func megabytes(_ value: Int) -> String {
        value >= 1000 ? String(format: "%g GB", Double(value) / 1000) : "\(value) MB"
    }
    var body: some View {
        @Bindable var app = app
        ThemePicker(selection: $app.colorTheme)
        SettingRow(title: "Language",
                   detail: language == AppLanguage.launched ? "The language of menus, buttons, and messages." : "Restart Flione to switch languages.") {
            HStack(spacing: Spacing.s8) {
                if language != AppLanguage.launched {
                    PillButton(title: "Restart") { AppLanguage.relaunch() }
                }
                PillMenu(title: "Language", selection: $language, options: AppLanguage.allCases.map { ($0, $0.title) })
            }
        }
        .onChange(of: language) { AppLanguage.save(language) }
        SettingRow(title: "Eye comfort", detail: "Makes titles, menus, and song info a little larger in every view, so long listening sessions are easier on your eyes.") {
            PillMenu(title: "Eye comfort", selection: $comfort, options: TextComfort.allCases.map { ($0, $0.title) })
        }
        SettingRow(title: "Open Flione in", detail: "The view you see when Flione starts.") {
            PillMenu(title: "Open Flione in", selection: $app.viewMode, options: ViewMode.allCases.map { ($0, LocalizedStringResource(stringLiteral: $0.title)) })
        }
        SettingToggle(title: "Remember my choice", detail: "Start in the view you used last.", isOn: $app.rememberMode)
        SettingToggle(title: "Menu bar player", detail: "Control playback from the menu bar.", isOn: $showsMenuBar)
        SettingToggle(title: "Song notifications", detail: "Show the song when a new one starts and Flione is in the background.", isOn: $trackNotifications)
        SettingToggle(title: "Find missing lyrics online",
                      detail: "Searches LRCLIB when your server has no lyrics. Sends the song title and artist to lrclib.net.",
                      isOn: $onlineLyrics)
        SettingRow(title: "Artwork cache", detail: "\(cacheSize) on this Mac. When it reaches the limit, the covers you haven't seen in a while are removed and download again when needed.") {
            HStack(spacing: Spacing.s8) {
                PillMenu(title: "Cache limit", selection: $cacheLimit,
                         options: ImagePipeline.diskLimitOptions.map { ($0, LocalizedStringResource(stringLiteral: Self.megabytes($0))) })
                PillButton(title: "Clear") {
                    ImagePipeline.clearDiskCache()
                    cacheSize = ImagePipeline.diskCacheSizeDescription()
                }
            }
        }
        .task {
            // 背景清理可能還在進行，稍後再更新一次
            cacheSize = ImagePipeline.diskCacheSizeDescription()
            try? await Task.sleep(for: .seconds(2))
            cacheSize = ImagePipeline.diskCacheSizeDescription()
        }
        .onChange(of: cacheLimit) {
            ImagePipeline.trimDiskNow()
            // 清理在背景進行，稍後再更新顯示的大小
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                cacheSize = ImagePipeline.diskCacheSizeDescription()
            }
        }
    }
}

/// 配色：6 張迷你預覽，畫出該配色的底色、側欄、卡片、互動色與播放中的橘色
private struct ThemePicker: View {
    @Binding var selection: ColorTheme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text("Color theme").finifyFont(.subheading).foregroundStyle(FinifyColor.ink)
                Text("The colors of every view. The orange that marks what's playing stays the same.")
                    .finifyFont(.body).foregroundStyle(FinifyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                ForEach(ColorTheme.allCases, id: \.self) { theme in
                    ThemeSwatch(theme: theme, selected: theme == selection) { selection = theme }
                }
            }
        }
        .padding(.vertical, Spacing.s16)
        .overlay(alignment: .bottom) { FinifyColor.hairline.frame(height: 1) }
    }
}

private struct ThemeSwatch: View {
    let theme: ColorTheme
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let p = theme.palette
        Button(action: action) {
            VStack(spacing: Spacing.s8) {
                // 迷你視窗：左側欄、右邊一張卡片、互動色的選取與橘色的播放進度
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: p.active)).frame(height: 7)
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: p.surface2)).frame(width: 14, height: 4)
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: p.surface2)).frame(width: 10, height: 4)
                        Spacer(minLength: 0)
                    }
                    .padding(5)
                    .frame(width: 22)
                    .frame(maxHeight: .infinity)
                    .background(Color(hex: p.surface1))
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [Color(hex: p.surface3), Color(hex: p.surface2)], startPoint: .top, endPoint: .bottom))
                            .frame(height: 22)
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: p.accent)).frame(width: 8, height: 8)
                            Capsule().fill(Color(hex: p.surface2)).frame(height: 3)
                                .overlay(alignment: .leading) { Capsule().fill(FinifyColor.orange).frame(width: 16, height: 3) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(hex: p.abyss))
                }
                .frame(width: 70, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Color(hex: p.accent) : FinifyColor.hairline, lineWidth: selected ? 2 : 1)
                }
                .padding(3)
                .overlay {
                    // 選取：外圈再一道細環
                    if selected {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Color(hex: p.accent).opacity(0.35), lineWidth: 1)
                    }
                }
                .scaleEffect(hovering && !selected ? 1.04 : 1)
                Text(theme.title)
                    .finifyFont(selected ? .bodyEmphasis : .caption)
                    .foregroundStyle(selected ? FinifyColor.ink : FinifyColor.muted)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .accessibilityLabel(Text(theme.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ModernSettings: View {
    @AppStorage(SettingsKey.theme) private var theme: ThemePreference = .system
    @AppStorage(SettingsKey.ambient) private var ambient = true

    var body: some View {
        SettingRow(title: "Theme", detail: "Light or dark. Infinity and Cover Flow are always dark.") {
            PillMenu(title: "Theme", selection: $theme, options: ThemePreference.allCases.map { ($0, $0.title) })
        }
        SettingToggle(title: "Ambient background", detail: "A glow in the colors of the album behind album and playlist pages.", isOn: $ambient)
    }
}

private struct InfinitySettings: View {
    @AppStorage(SettingsKey.wallAmbient) private var ambient = true
    @AppStorage(SettingsKey.wallRounded) private var rounded = true
    @AppStorage(SettingsKey.wallDrift) private var wallDrift = true
    @AppStorage(SettingsKey.wallDriftSpeed) private var wallDriftSpeed = 1.0
    @AppStorage("FinifyWallDensity") private var density = -1

    /// 漂移：關閉＝0，其餘是速度倍率
    private var drift: Binding<Double> {
        Binding(get: { wallDrift ? wallDriftSpeed : 0 },
                set: { wallDrift = $0 > 0; if $0 > 0 { wallDriftSpeed = $0 } })
    }

    var body: some View {
        SettingToggle(title: "Rounded covers", detail: "Turn off for square covers that touch each other, with no gaps.", isOn: $rounded)
        SettingRow(title: "Album size", detail: "How large the covers are.") {
            PillMenu(title: "Album size", selection: $density,
                     options: [(-1, "Auto")] + WallDensity.allCases.map { ($0.rawValue, $0.label) })
        }
        SettingRow(title: "Drift", detail: "How fast the wall moves on its own when the pointer is away.") {
            PillMenu(title: "Drift", selection: drift, options: [(0, "Off"), (0.5, "Slow"), (1, "Normal"), (2, "Fast")])
        }
        SettingToggle(title: "Ambient background", detail: "The blurred cover of the song that's playing, behind the wall.", isOn: $ambient)
    }
}

private struct CoverFlowSettings: View {
    @AppStorage(SettingsKey.flowRounded) private var rounded = true
    @AppStorage(SettingsKey.flowDim) private var flowDim = 0.25
    @AppStorage(SettingsKey.flowSettleDim) private var flowSettleDim = 0.0
    @AppStorage("FinifyFlowSize") private var flowSize = -1

    var body: some View {
        SettingToggle(title: "Rounded covers", detail: "Turn off for square covers.", isOn: $rounded)
        SettingRow(title: "Cover size", detail: "How large the center album is.") {
            PillMenu(title: "Cover size", selection: $flowSize,
                     options: [(-1, "Auto")] + (0..<AlbumFlowView.sizeSteps).map { ($0, "\($0 + 1) of \(AlbumFlowView.sizeSteps)") })
        }
        SettingRow(title: "Glow brightness", detail: "The glow behind the covers is brightest while you move between albums. Choose how much it dims after you stop.") {
            PillMenu(title: "Glow brightness", selection: $flowSettleDim, options: [(0, "Don't dim"), (0.3, "Subtle"), (0.5, "Medium"), (0.9, "Strong")])
        }
        SettingRow(title: "Dim side covers", detail: "The center cover is always the brightest. Choose how dark the others get as they move away from it.") {
            PillMenu(title: "Dim side covers", selection: $flowDim, options: [(0, "Off"), (0.15, "Subtle"), (0.25, "Medium"), (0.45, "Strong")])
        }
    }
}

/// 音樂來源（D39）：YouTube Music 與 Jellyfin 各一列，目前使用的標「使用中」，另一邊可切換；登入都保留
/// 關於：版本、開發與命名的故事、特別感謝與用到的開源專案
private struct AboutSettings: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s24) {
            DeveloperCard()
                .padding(.top, Spacing.s16)
            HStack(spacing: Spacing.s16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    Text(verbatim: "Flione").finifyFont(.subheading).foregroundStyle(FinifyColor.ink)
                    Text("Listen well. Collect well.").finifyFont(.body).foregroundStyle(FinifyColor.muted)
                    Text("Version \(version)").finifyFont(.caption).foregroundStyle(FinifyColor.faint)
                }
            }

            section("How it started", [
                "Flione began with a self-hosted Jellyfin server. An iTunes library built over twenty-some years was re-imported and became a private music stream.",
                "The music was back, but the players that worked with it looked plain and dated. So Flione was made.",
                "It needed a sidebar like Spotify's, for managing the whole library with ease. That's Modern.",
                "It needed a wall of covers that lays out years of collecting and taste, drifting slowly so you can wander through it. That's Infinity.",
                "And it needed the original Cover Flow from early Mac OS X back, the feeling of flipping through covers one by one. That's Cover Flow.",
                "Flione is a renaissance for collecting music: truly owning your music, not just streaming it.",
            ])
            section("The name", [
                    "Flione = Jellyfin + Infinity + Clione. Jellyfin and Infinity share \"fin\", which gives the F; \"lione\" comes from Clione, the sea angel. The three views are three ways a sea angel moves through an ocean of music: Modern is everyday drifting, Infinity heads into the deep, and Cover Flow glides through a floating swarm."])

            VStack(alignment: .leading, spacing: Spacing.s12) {
                heading("Special thanks")
                credit("Kaset", url: "https://github.com/sozercan/kaset",
                       detail: "A native YouTube Music app for macOS. It inspired Flione's sidebar glow, YouTube Music support, lyrics lookup, Dock menu, and more. MIT License.")
                credit("Reicon", url: "https://github.com/dqev/reicon",
                       detail: "Every icon in Flione's interface comes from Reicon.")
            }


            VStack(alignment: .leading, spacing: Spacing.s12) {
                heading("Open source")
                credit("Jellyfin", url: "https://jellyfin.org", detail: "The free media server Flione was first built for.")
                credit("BlurHash", url: "https://github.com/woltapp/blurhash", detail: "Cover colors for glows, placeholders, and Magic sort.")
                credit("LRCLIB", url: "https://lrclib.net", detail: "Open lyrics database, used when your server has no lyrics.")
                credit("XcodeGen", url: "https://github.com/yonaskolb/XcodeGen", detail: "Generates the Xcode project.")
                credit("Potrace", url: "https://potrace.sourceforge.net", detail: "Traced the menu bar icon.")
            }
        }
        .padding(.bottom, Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heading(_ title: LocalizedStringResource) -> some View {
        Text(title).finifyFont(.micro).textCase(.uppercase).foregroundStyle(FinifyColor.muted)
    }

    private func section(_ title: LocalizedStringResource, _ paragraphs: [LocalizedStringResource]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            heading(title)
            ForEach(paragraphs.indices, id: \.self) { index in
                Text(paragraphs[index]).finifyFont(.body).foregroundStyle(FinifyColor.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
        }
    }

    private func credit(_ name: String, url: String, detail: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Link(destination: URL(string: url)!) {
                HStack(spacing: Spacing.s4) {
                    Text(verbatim: name).finifyFont(.bodyEmphasis)
                    Text(verbatim: "↗").finifyFont(.caption)
                }
                .foregroundStyle(FinifyColor.accent)
            }
            .buttonStyle(.plain)
            Text(detail).finifyFont(.body).foregroundStyle(FinifyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 作者小卡：與 Findly 介紹頁同款的膠囊卡片，點了開 GitHub 個人頁。頭像打包在 app 裡，不連網載入
private struct DeveloperCard: View {
    @State private var hovering = false

    var body: some View {
        Link(destination: URL(string: "https://github.com/rocavence")!) {
            HStack(spacing: Spacing.s12) {
                Image("DeveloperAvatar")
                    .resizable()
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "@rocavence").font(.system(size: 15, weight: .semibold)).foregroundStyle(FinifyColor.ink)
                    Text("Author · GitHub").font(.system(size: 12.5)).foregroundStyle(FinifyColor.muted)
                }
            }
            .padding(.leading, Spacing.s8)
            .padding(.trailing, Spacing.s16)
            .padding(.vertical, Spacing.s8)
            .overlay(CapsuleRing().fill(hovering ? Color.white.opacity(0.2) : FinifyColor.hairline, style: FillStyle(eoFill: true)))
            .contentShape(Capsule())
            .background {
                // 陰影只在 hover 時出現，平時不留陰影圖層
                if hovering { Capsule().fill(FinifyColor.elevated).shadow(color: .black.opacity(0.3), radius: 16, y: 8) }
            }
            .offset(y: hovering ? -2 : 0)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: hovering)
        .accessibilityLabel("rocavence on GitHub")
    }
}

/// 1pt 的膠囊外框，用內外兩個膠囊相減填色畫出；strokeBorder 在大圓角時左右兩端會多畫出直線
private struct CapsuleRing: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: rect.height / 2)
        let inner = rect.insetBy(dx: 1, dy: 1)
        path.addPath(Path(roundedRect: inner, cornerRadius: inner.height / 2))
        return path
    }
}

/// 投放用的伺服器位址：Chromecast 會自己連到伺服器抓音樂，連不到 Flione 用的位址（例如 Tailscale）時改用這個（D43）
private struct CastServerRow: View {
    let serverURL: URL?
    @AppStorage(CastManager.serverKey) private var castServer = ""

    var body: some View {
        SettingRow(title: "Server address for casting",
                   detail: "Cast devices fetch music from your server themselves. If they can't reach \(serverURL?.absoluteString ?? "the server") (for example over Tailscale), enter a local network address, such as http://192.168.1.10:8096.") {
            TextField("", text: $castServer, prompt: Text(verbatim: "http://192.168.1.10:8096"))
                .textFieldStyle(.plain)
                .finifyFont(.body)
                .padding(.horizontal, Spacing.s12)
                .frame(width: 210, height: 32)
                .background(FinifyColor.surface, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
        }
    }
}

/// Jellyfin 與 YouTube Music 各自一頁：帳號、音樂庫、各自的設定、登出
private struct SourceSettings: View {
    let source: MusicSource
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        sourceRow(source)
        // 有登入就顯示這個來源的設定，不用先切換過去；音樂庫的數量與重新整理只對目前使用中的來源有意義
        if active(source) {
            SettingRow(title: "Library", detail: "\(app.library.albums.count) albums. Refresh after adding music.") {
                PillButton(title: app.library.state == .loading ? "Refreshing…" : "Refresh") { Task { await app.library.refresh() } }
                    .disabled(app.library.state == .loading)
            }
        }
        switch source {
        case .jellyfin:
            if let session = app.storedJellyfinSession { CastServerRow(serverURL: session.serverURL) }
        case .youtube:
            SettingRow(title: "Sync play counts with iCloud",
                       detail: LocalPlayCounts.isCloudAvailable
                           ? "YouTube Music doesn't keep play counts, so Flione counts them on this Mac. Turn this on to add up the counts from all your Macs through iCloud Drive. Turning it off removes this Mac's copy from iCloud."
                           : "Turn on iCloud Drive in System Settings to sync play counts between your Macs.") {
                Toggle(isOn: Binding(get: { app.youtubePlays.isSyncing }, set: { app.youtubePlays.setSyncing($0) })) {
                    Text("Sync play counts with iCloud")
                }
                .labelsHidden()
                .toggleStyle(PillSwitchStyle())
                .disabled(!LocalPlayCounts.isCloudAvailable)
            }
        }
        if isSignedIn(source) {
            SettingRow(title: "Sign out of \(source.title)",
                       detail: active(source) ? "Stops playback. Your other music source stays signed in." : "What's playing now isn't affected.") {
                PillButton(title: "Sign Out", destructive: true) {
                    if active(source) { app.isSettingsPresented = false }
                    app.signOut(source)
                }
            }
        }
        Text("Flione connects only to the music source you choose. No Flione account, no analytics, no tracking.")
            .finifyFont(.caption)
            .foregroundStyle(FinifyColor.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.s16)
    }

    private func active(_ source: MusicSource) -> Bool { app.session != nil && app.source == source }

    private func sourceRow(_ source: MusicSource) -> some View {
        let active = app.session != nil && app.source == source
        // 組標題已經是來源名稱，這一列叫「帳號」
        return SettingRow(title: "Account", detail: detail(for: source)) {
            if active {
                Text("In use")
                    .finifyFont(.bodyEmphasis)
                    .foregroundStyle(FinifyColor.muted)
                    .padding(.horizontal, Spacing.s16)
                    .frame(height: 32)
            } else {
                PillButton(title: isSignedIn(source) ? "Switch" : "Sign In") {
                    app.isSettingsPresented = false
                    Task { await app.switchSource(to: source) }
                }
            }
        }
    }

    private func isSignedIn(_ source: MusicSource) -> Bool {
        switch source {
        case .youtube: if case .connected = app.youtube.state { return true } else { return false }
        case .jellyfin: return app.hasJellyfinAccount
        }
    }

    private func detail(for source: MusicSource) -> LocalizedStringResource {
        if let session = app.session, app.source == source {
            return source == .youtube ? "Signed in as \(session.userName)" : "\(session.userName) on \(session.serverName) (\(session.serverURL.host() ?? ""))"
        }
        switch source {
        case .youtube:
            if case .connected(let name, _) = app.youtube.state { return "Signed in as \(name)" }
            return "Sign in with your Google account."
        case .jellyfin:
            return app.hasJellyfinAccount ? "Signed in. Switch to play from your server." : "Connect your own Jellyfin server."
        }
    }
}
