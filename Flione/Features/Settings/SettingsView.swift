import SwiftUI

enum ThemePreference: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

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
    static let ambient = "FinifyAmbient"
    static let menuBar = "FinifyMenuBar"
    static let floatingOnTop = "FinifyFloatingOnTop"
    static let wallDrift = "FinifyWallDrift"
    static let trackNotifications = "FinifyTrackNotifications"
    static let onlineLyrics = "FinifyOnlineLyrics"
}

/// 設定卡片：浮在主視窗上（⌘, 或側欄齒輪打開，Esc 或點外面關閉）。
/// 版面：標題、分頁膠囊、關閉鈕；每一列左邊是名稱與說明，右邊是控制項。
struct SettingsCard: View {
    enum Tab: String, CaseIterable {
        case general = "General"
        case appearance = "Appearance"
        case jellyfin = "Jellyfin"
    }

    @Environment(AppEnvironment.self) private var app
    @State private var tab: Tab = .general

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                HStack {
                    Text("Settings").finifyFont(.title).foregroundStyle(FinifyColor.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    CloseButton { app.isSettingsPresented = false }
                }
                TabPicker(selection: $tab)
            }
            .padding(.bottom, Spacing.s16)

            ScrollView {
                VStack(spacing: 0) {
                    switch tab {
                    case .general: GeneralSettings()
                    case .appearance: AppearanceSettings()
                    case .jellyfin: AccountSettings()
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(Spacing.s32)
        .frame(width: 640)
        .frame(maxHeight: 620)
        .fixedSize(horizontal: false, vertical: true)
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
    let title: String
    var detail: String?
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
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(title: title, detail: detail) {
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(PillSwitchStyle())
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
    let title: String
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
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: Spacing.s4) {
                Text(options.first { $0.0 == selection }?.1 ?? "")
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
        .accessibilityLabel(title)
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
                    Text(tab.rawValue)
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

    var body: some View {
        @Bindable var app = app
        SettingRow(title: "Open Flione in", detail: "The view you see when Flione starts.") {
            PillMenu(title: "Open Flione in", selection: $app.viewMode, options: ViewMode.allCases.map { ($0, $0.title) })
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

private struct AppearanceSettings: View {
    @AppStorage(SettingsKey.theme) private var theme: ThemePreference = .system
    @AppStorage(SettingsKey.ambient) private var ambient = true
    @AppStorage(SettingsKey.wallDrift) private var wallDrift = true
    @AppStorage("FinifyWallDensity") private var density = -1
    @AppStorage("FinifyFlowSize") private var flowSize = -1

    var body: some View {
        SettingRow(title: "Theme", detail: "Infinity and Cover Flow are always dark.") {
            PillMenu(title: "Theme", selection: $theme, options: ThemePreference.allCases.map { ($0, $0.rawValue) })
        }
        SettingToggle(title: "Ambient background",
                      detail: "A glow in the colors of the album behind Modern, and blurred artwork behind Infinity and Cover Flow.",
                      isOn: $ambient)
        SettingRow(title: "Album size", detail: "How large the covers are in Infinity.") {
            PillMenu(title: "Album size", selection: $density,
                     options: [(-1, "Auto")] + WallDensity.allCases.map { ($0.rawValue, $0.label) })
        }
        SettingRow(title: "Cover Flow size", detail: "How large the center album is in Cover Flow.") {
            PillMenu(title: "Cover Flow size", selection: $flowSize,
                     options: [(-1, "Auto")] + (0..<AlbumFlowView.sizeSteps).map { ($0, "\($0 + 1) of \(AlbumFlowView.sizeSteps)") })
        }
        SettingToggle(title: "Drifting album wall", detail: "The wall in Infinity slowly moves when the pointer is away.", isOn: $wallDrift)
    }
}

private struct AccountSettings: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        if let session = app.session {
            SettingRow(title: session.userName, detail: "Signed in to \(session.serverName)") {
                UserAvatar(session: session, size: 40)
            }
            SettingRow(title: "Server address", detail: session.serverURL.absoluteString) { EmptyView() }
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
