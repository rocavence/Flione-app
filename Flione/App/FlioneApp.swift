import SwiftUI

@main
struct FlioneApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var app = AppEnvironment.bootstrap()
    @State private var keyboard: KeyboardMonitor?
    @AppStorage(SettingsKey.menuBar) private var showsMenuBar = true

    var body: some Scene {
        Window("Flione", id: "main") {
            RootView()
                .environment(app)
                .frame(minWidth: 1040, minHeight: 680)
                .onOpenURL { app.handle($0) }
                .onAppear {
                    delegate.app = app
                    if keyboard == nil { keyboard = KeyboardMonitor(app: app) }
                    #if DEBUG || BENCHMARK
                    LaunchMark.record("window")
                    WallBenchmark.startIfRequested()
                    DebugDemo.scheduleModeSwitch(app: app)
                    #endif
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 860)
        .commands { FinifyCommands(app: app) }

        Window("Mini Player", id: "floating") {
            FloatingPlayerView()
                .environment(app)
                .tint(FinifyColor.accent)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 280, height: 280)
        .defaultPosition(.bottomTrailing)
        .commandsRemoved()

        MenuBarExtra(isInserted: $showsMenuBar) {
            MenuBarPlayer()
                .environment(app)
                .tint(FinifyColor.accent)
        } label: {
            // 平常是 template（跟著選單列變黑／白），播放中換成 Finity Blue 加小點
            Image(app.player.isPlaying ? "MenuBarIconPlaying" : "MenuBarIcon")
                .accessibilityLabel("Flione")
        }
        .menuBarExtraStyle(.window)

    }
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.theme) private var theme: ThemePreference = .system

    var body: some View {
        Group {
            if app.session == nil {
                ConnectView()
            } else if let mode = app.mode {
                switch mode {
                case .standard: StandardRootView()
                case .overflow: OverflowRootView()
                }
            } else {
                ModePickerView()
            }
        }
        .transition(.opacity)
        .overlay(alignment: .bottom) {
            if let message = app.favorites.failureMessage {
                Toast(message: message) { app.favorites.failureMessage = nil }
                    .padding(.bottom, 104)
            } else if let message = app.playlists.failureMessage {
                Toast(message: message) { app.playlists.failureMessage = nil }
                    .padding(.bottom, 104)
            } else if let notice = app.player.notice {
                Toast(message: notice.message) { app.player.dismissNotice() }
                    .id(notice.id)
                    .padding(.bottom, 104)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if app.isSettingsPresented {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { app.isSettingsPresented = false }
                    SettingsCard().padding(Spacing.s32)
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: app.isSettingsPresented)
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: app.player.notice)
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: app.mode)
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: app.session)
        .ignoresSafeArea()
        .modifier(NewPlaylistPrompt())
        .preferredColorScheme(theme.colorScheme)
        .tint(FinifyColor.accent)
    }
}

/// 選單與快捷鍵
struct FinifyCommands: Commands {
    let app: AppEnvironment

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu("Playback") {
            // Space 由 KeyboardMonitor 處理，避免攔截文字欄位的空白鍵
            Button(app.player.isPlaying ? "Pause (Space)" : "Play (Space)") { app.player.togglePlayPause() }
                .disabled(app.player.currentTrack == nil)
            Button("Next") { app.player.next() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous") { app.player.previous() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Divider()
            Button(app.player.isSmartShuffle ? "Turn Off Shuffle" : app.player.isShuffled ? "Smart Shuffle" : "Shuffle") { app.player.toggleShuffle() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Button("Repeat") { app.player.cycleRepeat() }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button("Favorite Current Song") { if let track = app.player.currentTrack, !track.isPlaceholder { app.favorites.toggle(track.id) } }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(app.player.currentTrack == nil)
            Divider()
            Button("Volume Up") { app.player.volume = min(1, app.player.volume + 0.1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Volume Down") { app.player.volume = max(0, app.player.volume - 0.1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
        }
        CommandGroup(after: .sidebar) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button(mode.title) { app.viewMode = mode }
                    .keyboardShortcut(KeyEquivalent(mode.shortcut), modifiers: .command)
                    .disabled(app.session == nil)
            }
            Divider()
            Button("Search") { app.isSearchPresented = true }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(app.session == nil)
            Button("Find") { app.isSearchPresented = true }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(app.session == nil)
            Button("Show Queue") { app.isQueuePresented.toggle() }
                .disabled(app.session == nil)
            OpenWindowButton(title: "Mini Player", windowID: "floating")
                .keyboardShortcut("m", modifiers: [.command, .option])
        }
        // 設定是主視窗裡的卡片，不是獨立視窗
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { app.isSettingsPresented = true }
                .keyboardShortcut(",", modifiers: .command)
            Button("Sign Out of Jellyfin…") { app.signOut() }
                .disabled(app.session == nil)
        }
    }
}

/// 選單中開啟其他視窗（Commands 裡不能直接用 openWindow environment）
private struct OpenWindowButton: View {
    let title: String
    let windowID: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(title) { openWindow(id: windowID) }
    }
}
