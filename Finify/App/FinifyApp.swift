import SwiftUI

@main
struct FinifyApp: App {
    @State private var app = AppEnvironment.bootstrap()
    @State private var keyboard: KeyboardMonitor?

    var body: some Scene {
        Window("Finify", id: "main") {
            RootView()
                .environment(app)
                .frame(minWidth: 1040, minHeight: 680)
                .onAppear { if keyboard == nil { keyboard = KeyboardMonitor(app: app) } }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 860)
        .commands { FinifyCommands(app: app) }
    }
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: app.mode)
        .animation(Motion.respecting(reduceMotion, Motion.ui), value: app.session)
        .ignoresSafeArea()
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
            Button(app.player.isShuffled ? "Turn Off Shuffle" : "Shuffle") { app.player.toggleShuffle() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Button("Repeat") { app.player.cycleRepeat() }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Divider()
            Button("Volume Up") { app.player.volume = min(1, app.player.volume + 0.1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Volume Down") { app.player.volume = max(0, app.player.volume - 0.1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
        }
        CommandGroup(after: .sidebar) {
            Button("Standard") { app.mode = .standard }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(app.session == nil)
            Button("Overflow") { app.mode = .overflow }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(app.session == nil)
            Divider()
            Button("Search") { app.isSearchPresented = true }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(app.session == nil)
            Button("Find") { app.isSearchPresented = true }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(app.session == nil)
            Button("Show Queue") { app.isQueuePresented.toggle() }
                .disabled(app.session == nil)
        }
        CommandGroup(after: .appSettings) {
            Button("Sign Out of Jellyfin…") { app.signOut() }
                .disabled(app.session == nil)
        }
    }
}
