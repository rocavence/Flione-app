#if DEBUG || BENCHMARK
import AppKit

/// 開發用：以啟動參數把 app 帶到指定狀態，方便無人值守時截圖驗證。Release build 不包含。
///
///     -FinifyMuted YES              播放音量 0
///     -FinifyDemoPlay "<專輯名>"     播放該專輯
///     -FinifyDemoOpen "<專輯名>"     打開該專輯頁
///     -FinifyDemoSearch "<關鍵字>"   打開 ⌘K 並搜尋
///     -FinifyDemoImmersive YES      Overflow 進入 Fullscreen
///     -FinifyDemoSeekToEnd 5        播放後跳到第一首結尾前 5 秒
@MainActor
enum DebugDemo {
    static var defaults: UserDefaults { .standard }

    static func run(app: AppEnvironment, openAlbum: @escaping (Album) -> Void, immersive: (() -> Void)? = nil) async {
        if defaults.bool(forKey: "FinifyMuted") { app.player.muteForTesting() }
        let wantsLibrary = ["FinifyDemoPlay", "FinifyDemoOpen"].contains { defaults.string(forKey: $0) != nil }
        if wantsLibrary {
            for _ in 0..<100 where app.library.albums.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
        }
        if let name = defaults.string(forKey: "FinifyDemoPlay"), let album = find(name, in: app),
           var tracks = try? await app.repository?.tracks(inAlbum: album.id) {
            // -FinifyDemoBrokenFirst YES：最前面插入不存在的曲目，驗證播放失敗的處理
            if defaults.bool(forKey: "FinifyDemoBrokenFirst"), let first = tracks.first {
                tracks.insert(Track(id: "does-not-exist", name: "Missing Song", albumID: first.albumID, albumName: first.albumName,
                                    artistName: first.artistName, artistID: first.artistID, trackNumber: 0, discNumber: 1,
                                    duration: 100, container: "mp3", artwork: first.artwork), at: 0)
            }
            app.player.play(tracks)
            // -FinifyDemoSeekToEnd <秒>：跳到第一首結尾前 N 秒，用來驗證自動換曲
            let seconds = defaults.double(forKey: "FinifyDemoSeekToEnd")
            if seconds > 0, let first = tracks.first {
                try? await Task.sleep(for: .seconds(2))
                app.player.seek(to: first.duration - seconds)
            }
        }
        if let name = defaults.string(forKey: "FinifyDemoOpen"), let album = find(name, in: app) {
            openAlbum(album)
        }
        if defaults.string(forKey: "FinifyDemoSearch") != nil { app.isSearchPresented = true }
        if defaults.bool(forKey: "FinifyDumpViews") {
            try? await Task.sleep(for: .seconds(6))
            if let root = NSApp.windows.first(where: \.isVisible)?.contentView { dump(root, depth: 0) }
        }
        if defaults.bool(forKey: "FinifyDemoImmersive") {
            try? await Task.sleep(for: .seconds(1))
            immersive?()
        }
    }

    private static func dump(_ view: NSView, depth: Int) {
        guard depth < 14 else { return }
        FileHandle.standardError.write(Data((String(repeating: "  ", count: depth) + "\(type(of: view)) \(view.frame.integral) hidden=\(view.isHidden) alpha=\(view.alphaValue) z=\(view.layer?.zPosition ?? 0)\n").utf8))
        for sub in view.subviews { dump(sub, depth: depth + 1) }
    }

    static var searchTerm: String? { defaults.string(forKey: "FinifyDemoSearch") }

    private static func find(_ name: String, in app: AppEnvironment) -> Album? {
        app.library.albums.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }
}
#endif
