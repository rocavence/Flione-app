#if DEBUG || BENCHMARK
import AppKit
import AVFoundation

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
        if defaults.string(forKey: "FinifyGaplessProbe") != nil {
            for _ in 0..<100 where app.library.albums.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
            await gaplessProbe(app: app)
            return
        }
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
        if defaults.string(forKey: "FinifySoak") != nil { await soak(app: app) }
        if defaults.bool(forKey: "FinifyDemoImmersive") {
            try? await Task.sleep(for: .seconds(1))
            immersive?()
        }
    }

    /// -FinifySoak <輸出檔>：連續換曲 40 次（每 8 秒一次），記錄記憶體，用來找長時間使用的洩漏
    static func soak(app: AppEnvironment) async {
        guard let path = defaults.string(forKey: "FinifySoak") else { return }
        try? await Task.sleep(for: .seconds(4))
        var lines = ["start \(Int(WallBenchmark.footprintMB())) MB"]
        for i in 1...40 {
            app.player.next()
            try? await Task.sleep(for: .seconds(8))
            if i % 5 == 0 {
                lines.append("after \(i) changes: \(Int(WallBenchmark.footprintMB())) MB, track=\(app.player.currentTrack?.name ?? "-"), playing=\(app.player.isPlaying)")
                try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        NSApp.terminate(nil)
    }

    /// -FinifyGaplessProbe <輸出檔>：在真正的 PlayerManager 上量測換曲停頓（與 S2 時鐘法相同）
    /// 依序播放 -FinifyDemoPlay 指定專輯的每一個換曲：跳到該曲結尾前 3 秒，量測換到下一首時多出來的時間
    static func gaplessProbe(app: AppEnvironment) async {
        guard let path = defaults.string(forKey: "FinifyGaplessProbe"),
              let name = defaults.string(forKey: "FinifyDemoPlay"), let album = find(name, in: app),
              let tracks = try? await app.repository?.tracks(inAlbum: album.id) else { return }
        let player = app.player.debugQueuePlayer
        var lines: [String] = []
        for index in 0..<min(tracks.count - 1, 8) {
            app.player.play(tracks, startAt: index)
            app.player.muteForTesting()
            // 等目前曲目與預載的下一首都就緒（實際使用時下一首有整首歌的時間緩衝）
            for _ in 0..<200 {
                let items = player.items()
                if items.count >= 2, items.allSatisfy({ $0.status == .readyToPlay }), items[1].isPlaybackLikelyToKeepUp { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            let duration = player.currentItem?.duration.seconds ?? tracks[index].duration
            await player.seek(to: CMTime(seconds: duration - 3, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            let first = player.currentItem
            var samples: [(wall: Double, changed: Bool, t: Double)] = []
            let end = CACurrentMediaTime() + 6
            while CACurrentMediaTime() < end {
                samples.append((CACurrentMediaTime(), player.currentItem !== first, player.currentTime().seconds))
                try? await Task.sleep(for: .milliseconds(5))
            }
            var gap = "n/a"
            if let lastA = samples.last(where: { !$0.changed }), let firstB = samples.first(where: { $0.changed && $0.t >= 0.5 }) {
                let wall = firstB.wall - lastA.wall
                let media = (duration - lastA.t) + firstB.t
                gap = String(format: "%.1f", (wall - media) * 1000)
            }
            lines.append("\(index + 1)→\(index + 2) \(tracks[index].container ?? "?")→\(tracks[index + 1].container ?? "?") gapMs=\(gap)")
        }
        app.player.pause()
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
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
