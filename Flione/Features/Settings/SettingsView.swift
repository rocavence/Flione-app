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
}

/// 設定卡片：浮在主視窗上（⌘, 或側欄齒輪打開，Esc 或點外面關閉）。
/// 版面：標題、分頁膠囊、關閉鈕；每一列左邊是名稱與說明，右邊是控制項。
struct SettingsCard: View {
    enum Tab: String, CaseIterable {
        case general, modern, infinity, coverFlow, jellyfin

        var title: LocalizedStringResource {
            switch self {
            case .general: "General"
            // 模式名稱是產品名，不翻譯
            case .modern: LocalizedStringResource(stringLiteral: ViewMode.standard.title)
            case .infinity: LocalizedStringResource(stringLiteral: ViewMode.infinity.title)
            case .coverFlow: LocalizedStringResource(stringLiteral: ViewMode.coverFlow.title)
            case .jellyfin: "Server"
            }
        }
    }

    @Environment(AppEnvironment.self) private var app
    @State private var tab: Tab = .general

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings").finifyFont(.title).foregroundStyle(FinifyColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                CloseButton { app.isSettingsPresented = false }
            }
            .padding(.bottom, Spacing.s16)
            // 五個分頁放在標題下方一整列，不和標題擠在一起
            TabPicker(selection: $tab)
                .padding(.bottom, Spacing.s8)

            ScrollView {
                VStack(spacing: 0) {
                    switch tab {
                    case .general: GeneralSettings()
                    case .modern: ModernSettings()
                    case .infinity: InfinitySettings()
                    case .coverFlow: CoverFlowSettings()
                    case .jellyfin: AccountSettings()
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(Spacing.s32)
        // 固定大小：切換分頁時卡片不會因為內容長短而上下跳動
        .frame(width: 640, height: 600)
        .background {
            ZStack {
                FinifyColor.elevated
                // 卡片內的淡淡光暈，和 Modern 的背景光暈同一個語彙
                RadialGradient(colors: [FinifyColor.accent.opacity(0.08), .clear], center: .top, startRadius: 0, endRadius: 420)
                RadialGradient(colors: [FinifyColor.violet.opacity(0.08), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 360)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(FinifyColor.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 40, y: 20)
        .tint(FinifyColor.accent)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
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

/// 開關：開啟時是 Flione Blue。系統的 switch 在視窗不在前景時會變灰，這裡固定顯示顏色
private struct PillSwitchStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? FinifyColor.accent : FinifyColor.glassHighlight)
                .overlay(Capsule().strokeBorder(FinifyColor.hairline, lineWidth: configuration.isOn ? 0 : 1))
                .frame(width: 42, height: 24)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).shadow(color: .black.opacity(0.2), radius: 1.5, y: 1).padding(3)
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
private struct TabPicker: View {
    @Binding var selection: SettingsCard.Tab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsCard.Tab.allCases, id: \.self) { tab in
                let selected = tab == selection
                Button { selection = tab } label: {
                    Text(tab.title)
                        .finifyFont(selected ? .bodyEmphasis : .body)
                        .foregroundStyle(selected ? FinifyColor.onPrimary : FinifyColor.muted)
                        .padding(.horizontal, Spacing.s16)
                        .frame(height: 30)
                        .background(selected ? FinifyColor.primary : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(FinifyColor.glassHighlight, in: Capsule())
        .animation(Motion.micro, value: selection)
    }
}

private struct CloseButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            FinifyIcon(.x, size: .compact)
                .foregroundStyle(FinifyColor.muted)
                .frame(width: 36, height: 36)
                .background(hovering ? FinifyColor.glassHighlight : FinifyColor.glass, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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

    @State private var language = AppLanguage.saved

    var body: some View {
        @Bindable var app = app
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
        SettingRow(title: "Open Flione in", detail: "The view you see when Flione starts.") {
            PillMenu(title: "Open Flione in", selection: $app.viewMode, options: ViewMode.allCases.map { ($0, LocalizedStringResource(stringLiteral: $0.title)) })
        }
        SettingToggle(title: "Remember my choice", detail: "Start in the view you used last.", isOn: $app.rememberMode)
        SettingToggle(title: "Menu bar player", detail: "Control playback from the menu bar.", isOn: $showsMenuBar)
        SettingToggle(title: "Song notifications", detail: "Show the song when a new one starts and Flione is in the background.", isOn: $trackNotifications)
        SettingToggle(title: "Find missing lyrics online",
                      detail: "Searches LRCLIB when your server has no lyrics. Sends the song title and artist to lrclib.net.",
                      isOn: $onlineLyrics)
        SettingRow(title: "Artwork cache", detail: "\(cacheSize) on this Mac. Covers download again when needed.") {
            PillButton(title: "Clear") {
                ImagePipeline.clearDiskCache()
                cacheSize = ImagePipeline.diskCacheSizeDescription()
            }
        }
        .onAppear { cacheSize = ImagePipeline.diskCacheSizeDescription() }
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

private struct AccountSettings: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        if let session = app.session {
            SettingRow(title: "\(session.userName)", detail: "Signed in to \(session.serverName)") {
                UserAvatar(session: session, size: 40)
            }
            SettingRow(title: "Server address", detail: "\(session.serverURL.absoluteString)") { EmptyView() }
            SettingRow(title: "Library", detail: "\(app.library.albums.count) albums. Refresh after adding music on the server.") {
                PillButton(title: app.library.state == .loading ? "Refreshing…" : "Refresh") { Task { await app.library.refresh() } }
                    .disabled(app.library.state == .loading)
            }
            SettingRow(title: "Sign out", detail: "Stops playback and returns to the sign-in screen.") {
                PillButton(title: "Sign Out", destructive: true) {
                    app.isSettingsPresented = false
                    app.signOut()
                }
            }
        } else {
            SettingRow(title: "Not connected", detail: "Sign in to your Jellyfin server first.") { EmptyView() }
        }
        Text("Flione talks only to your Jellyfin server. It has no account, no analytics, and no tracking.")
            .finifyFont(.caption)
            .foregroundStyle(FinifyColor.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.s16)
    }
}
