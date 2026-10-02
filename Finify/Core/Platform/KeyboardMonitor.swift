import AppKit

/// 全域鍵盤：Space 播放／暫停、Esc 關閉浮層。
/// 用 local event monitor 而非選單快捷鍵，這樣在文字欄位輸入空白時不會被攔截。
@MainActor
final class KeyboardMonitor {
    private var monitor: Any?

    init(app: AppEnvironment) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak app] event in
            guard let app else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
            let editingText = NSApp.keyWindow?.firstResponder is NSText
            switch event.keyCode {
            case 49 where modifiers.isEmpty && !editingText:
                app.player.togglePlayPause()
                return nil
            case 53:
                if app.isSearchPresented { app.isSearchPresented = false; return nil }
                if app.isQueuePresented { app.isQueuePresented = false; return nil }
                return event
            default:
                return event
            }
        }
    }
}
