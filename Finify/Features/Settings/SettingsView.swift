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
    static let autoHideControls = "FinifyAutoHideControls"
    static let menuBar = "FinifyMenuBar"
    static let floatingOnTop = "FinifyFloatingOnTop"
    static let wallDrift = "FinifyWallDrift"
    static let trackNotifications = "FinifyTrackNotifications"
}

/// macOS 設定視窗（⌘,）
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label { Text("General") } icon: { Image("Reicon/setting2.outline") } }
            AppearanceSettings()
                .tabItem { Label { Text("Appearance") } icon: { Image("Reicon/grid.outline") } }
            AccountSettings()
                .tabItem { Label { Text("Jellyfin") } icon: { Image("Reicon/server.outline") } }
        }
        .frame(width: 480)
        .scenePadding()
    }
}

private struct GeneralSettings: View {
    @Environment(AppEnvironment.self) private var app
    @State private var cacheSize: String = "…"
    @AppStorage(SettingsKey.menuBar) private var showsMenuBar = true
    @AppStorage(SettingsKey.trackNotifications) private var trackNotifications = true

    var body: some View {
        @Bindable var app = app
        Form {
            Picker("Open Finify in", selection: Binding(get: { app.mode ?? .standard }, set: { app.mode = $0 })) {
                Text("Standard").tag(AppMode.standard)
                Text("Overflow").tag(AppMode.overflow)
            }
            Toggle("Remember my choice", isOn: $app.rememberMode)
            Toggle("Show player in menu bar", isOn: $showsMenuBar)
            Toggle("Notify when a new song starts", isOn: $trackNotifications)
            LabeledContent("Artwork cache") {
                HStack {
                    Text(cacheSize).foregroundStyle(.secondary)
                    Button("Clear") {
                        ImagePipeline.clearDiskCache()
                        cacheSize = ImagePipeline.diskCacheSizeDescription()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { cacheSize = ImagePipeline.diskCacheSizeDescription() }
    }
}

private struct AppearanceSettings: View {
    @AppStorage(SettingsKey.theme) private var theme: ThemePreference = .system
    @AppStorage(SettingsKey.ambient) private var ambient = true
    @AppStorage(SettingsKey.autoHideControls) private var autoHide = true
    @AppStorage(SettingsKey.wallDrift) private var wallDrift = true
    @AppStorage("FinifyOverflowLayout") private var layout: OverflowLayout = .wall
    @AppStorage("FinifyWallDensity") private var density = WallDensity.medium.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(ThemePreference.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Overflow is always dark.").foregroundStyle(.secondary)
            }
            Section("Overflow") {
                Picker("Layout", selection: $layout) {
                    ForEach(OverflowLayout.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Album size", selection: $density) {
                    ForEach(WallDensity.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Ambient background", isOn: $ambient)
                Toggle("Drift album wall when the pointer is away", isOn: $wallDrift)
                Toggle("Hide controls in fullscreen", isOn: $autoHide)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AccountSettings: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Form {
            if let session = app.session {
                LabeledContent("Server", value: session.serverName)
                LabeledContent("Address", value: session.serverURL.absoluteString)
                LabeledContent("Signed in as", value: session.userName)
                LabeledContent("Albums", value: "\(app.library.albums.count)")
                HStack {
                    Button("Refresh Library") { Task { await app.library.refresh() } }
                        .disabled(app.library.state == .loading)
                    Spacer()
                    Button("Sign Out", role: .destructive) { app.signOut() }
                }
            } else {
                Text("Not connected.").foregroundStyle(.secondary)
            }
            Section {
                Text("Finify talks only to your Jellyfin server. It has no account, no analytics, and no tracking.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
