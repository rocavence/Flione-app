import AppKit

/// Dock 圖示的右鍵選單：目前播放的歌與播放控制。做法參考 Kaset（MIT）。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var app: AppEnvironment?

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let player = app?.player, let track = player.currentTrack else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = NSMenuItem(title: "\(track.name) — \(track.artistName)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(player.isPlaying ? "Pause" : "Play") { player.togglePlayPause() })
        menu.addItem(ClosureMenuItem("Next") { player.next() })
        menu.addItem(ClosureMenuItem("Previous") { player.previous() })
        return menu
    }
}
