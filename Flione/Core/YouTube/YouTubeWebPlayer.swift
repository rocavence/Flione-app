import AppKit
import Observation
import WebKit

/// YouTube Music 的播放引擎（第二階段，docs/youtube/DESIGN.md）。
/// 音訊有加密與簽章保護，AVQueuePlayer 無法播放，所以在看不見的 WKWebView 裡跑 YouTube Music 網頁播放器，
/// 用 JavaScript 控制播放並每 0.5 秒回報狀態。cookie 與登入視窗共用（WKWebsiteDataStore.default()）。
@MainActor @Observable
final class YouTubeWebPlayer: NSObject, WKScriptMessageHandler {
    private(set) var title = ""
    private(set) var artist = ""
    private(set) var artwork: URL?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    /// 已經開始載入過歌曲（播放列才顯示）
    private(set) var hasTrack = false
    /// 正在用 AirPlay 播放（網頁的 video 回報 webkitCurrentPlaybackTargetIsWireless）
    private(set) var isWireless = false
    /// 最近一次回報的影片，用來確認頁面內換歌有沒有成功
    @ObservationIgnored private var reportedVideoId: String?
    @ObservationIgnored private var fallbackTask: Task<Void, Never>?

    @ObservationIgnored private var webView: WKWebView?

    /// 給 PlayerManager 的狀態回報（每 0.5 秒）
    struct Update {
        let playing: Bool
        let time: Double
        let duration: Double
        /// 網頁目前播放的影片：與 Flione 要播的不同時，代表 YouTube 自己換到別首（自動播放）
        let videoId: String?
        let ended: Bool
    }
    @ObservationIgnored var onUpdate: ((Update) -> Void)?
    /// 音量 0–1；每次載入新頁面後重新套用
    @ObservationIgnored var volume: Float = 1 { didSet { appliedVolume = nil } }
    @ObservationIgnored private var appliedVolume: Float?

    /// 頁面載入後每 0.5 秒把網頁播放器的狀態送回來
    private static let observer = """
    (function () {
        if (window.__flione) { return; }
        window.__flione = true;
        setInterval(function () {
            try {
                var v = document.querySelector('video');
                if (window.__flioneMute && v) { v.muted = true; }
                // 歌名等資訊讀 Media Session：YouTube Music 會寫入目前播放的歌，網頁看不見時也有
                var meta = navigator.mediaSession && navigator.mediaSession.metadata;
                var art = meta && meta.artwork && meta.artwork.length ? meta.artwork[meta.artwork.length - 1].src : '';
                window.webkit.messageHandlers.flione.postMessage({
                    playing: !!(v && !v.paused && !v.ended),
                    time: v ? v.currentTime : 0,
                    duration: v && isFinite(v.duration) ? v.duration : 0,
                    ended: !!(v && v.ended),
                    wireless: !!(v && v.webkitCurrentPlaybackTargetIsWireless),
                    videoId: new URLSearchParams(location.search).get('v') || '',
                    title: meta ? meta.title : '',
                    artist: meta ? meta.artist : '',
                    artwork: art
                });
            } catch (e) {}
        }, 500);
    })();
    """

    /// 第一次播放時才建立，掛在主視窗裡（1×1、透明）：不在視窗中的網頁可能被系統暫停
    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // AirPlay：用 WebKit 自己的裝置選單（與 Kaset 相同，ADR-0010）
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.userContentController.add(self, name: "flione")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.observer, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        #if DEBUG
        // -FinifyMuted YES 的測試不出聲
        if UserDefaults.standard.bool(forKey: "FinifyMuted") {
            configuration.userContentController.addUserScript(WKUserScript(source: "window.__flioneMute = true;", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        #endif
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        view.customUserAgent = GoogleSignIn.userAgent
        view.alphaValue = 0
        #if DEBUG
        view.isInspectable = true
        #endif
        if let content = (NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible })?.contentView {
            content.addSubview(view)
        }
        webView = view
        return view
    }

    /// 播放：帶 playlistId 時，網頁播放器會接著播清單後面的歌（上一首／下一首也由它處理）
    func play(videoId: String, playlistId: String? = nil) {
        var components = URLComponents(string: "\(InnerTube.origin)/watch")!
        components.queryItems = [URLQueryItem(name: "v", value: videoId)] + (playlistId.map { [URLQueryItem(name: "list", value: $0)] } ?? [])
        hasTrack = true
        isPlaying = true
        ensureWebView().load(URLRequest(url: components.url!))
    }

    /// 只播單首（佇列由 PlayerManager 管）。
    /// 頁面已經載入時，用 YouTube Music 自己的 router 在同一個頁面換歌：不重新載入，AirPlay 連線不會斷，換歌也比較快。
    /// 5 秒內網頁沒有換到這首（router 不在、YouTube 改版），就退回整頁重新載入
    func load(videoId: String) {
        fallbackTask?.cancel()
        guard let webView, webView.url?.host == URL(string: InnerTube.origin)?.host, !webView.isLoading else {
            appliedVolume = nil
            play(videoId: videoId)
            return
        }
        hasTrack = true
        isPlaying = true
        // 影片 ID 以參數傳入，不拼進程式碼：ID 來自 YouTube 回傳的資料，不能讓它被當成程式執行
        let script = """
        const app = document.querySelector('ytmusic-app');
        if (!app || typeof app.resolveCommand !== 'function') { return false; }
        app.resolveCommand({ watchEndpoint: { videoId: id } });
        return true;
        """
        webView.callAsyncJavaScript(script, arguments: ["id": videoId], in: nil, in: .page) { [weak self] outcome in
            let result: Any? = try? outcome.get()
            MainActor.assumeIsolated {
                guard let self else { return }
                #if DEBUG
                Self.debugNote("in-page=\(result as? Bool == true) \(videoId)")
                #endif
                guard result as? Bool == true else {
                    self.appliedVolume = nil
                    self.play(videoId: videoId)
                    return
                }
                self.fallbackTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    guard let self, !Task.isCancelled, self.reportedVideoId != videoId else { return }
                    #if DEBUG
                    Self.debugNote("fallback to full load \(videoId)")
                    #endif
                    self.appliedVolume = nil
                    self.play(videoId: videoId)
                }
            }
        }
    }

    /// 叫出 WebKit 的 AirPlay 裝置選單。WebKit 以網頁最後一次收到的滑鼠位置當選單位置，
    /// 先送一個不按下的 mouseUp 把位置設到按鈕上（與 Kaset 相同，ADR-0010）
    func showAirPlayPicker(at screenPoint: CGPoint?) {
        guard let webView else { return }
        if let screenPoint, let window = webView.window, let contentView = window.contentView {
            let point = contentView.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
            if let event = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                              context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
                webView.mouseUp(with: event)
            }
        }
        run("var v = document.querySelector('video'); if (v && v.webkitShowPlaybackTargetPicker) { v.webkitShowPlaybackTargetPicker(); }")
    }

    func pause() { run("document.querySelector('video').pause()"); isPlaying = false }
    func resume() { run("document.querySelector('video').play()"); isPlaying = true }

    func togglePlayPause() {
        run(isPlaying ? "document.querySelector('video').pause()" : "document.querySelector('video').play()")
        isPlaying.toggle()
    }

    func next() { run("document.querySelector('ytmusic-player-bar .next-button').click()") }
    func previous() { run("document.querySelector('ytmusic-player-bar .previous-button').click()") }

    func seek(to seconds: Double) {
        run("document.querySelector('video').currentTime = \(seconds)")
        currentTime = seconds
    }

    private func run(_ script: String) {
        webView?.evaluateJavaScript("try { \(script) } catch (e) {}")
    }

    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        MainActor.assumeIsolated {
            if appliedVolume != volume {
                appliedVolume = volume
                run("document.querySelector('video').volume = \(volume)")
            }
            onUpdate?(Update(playing: body["playing"] as? Bool ?? false, time: body["time"] as? Double ?? 0,
                             duration: body["duration"] as? Double ?? 0,
                             videoId: (body["videoId"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                             ended: body["ended"] as? Bool ?? false))
            isPlaying = body["playing"] as? Bool ?? false
            isWireless = body["wireless"] as? Bool ?? false
            reportedVideoId = (body["videoId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            currentTime = body["time"] as? Double ?? 0
            duration = body["duration"] as? Double ?? 0
            if let value = body["title"] as? String, !value.isEmpty { title = value }
            if let value = body["artist"] as? String, !value.isEmpty { artist = value }
            if let value = body["artwork"] as? String, let url = URL(string: value), value.hasPrefix("http") {
                // 播放列的縮圖很小，換成大尺寸
                artwork = URL(string: value.replacingOccurrences(of: #"=w\d+-h\d+"#, with: "=w544-h544", options: .regularExpression)) ?? url
            }
        }
    }

    #if DEBUG
    /// -FinifyRouterLog <檔案>：記錄 YouTube 換歌走頁面內 router 或整頁重新載入
    private static func debugNote(_ line: String) {
        guard let path = UserDefaults.standard.string(forKey: "FinifyRouterLog") else { return }
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        handle.seekToEndOfFile(); handle.write(Data((line + "\n").utf8)); try? handle.close()
    }
    #endif

    func stop() {
        fallbackTask?.cancel()
        isWireless = false
        webView?.load(URLRequest(url: URL(string: "about:blank")!))
        webView?.removeFromSuperview()
        webView = nil
        hasTrack = false
        isPlaying = false
        title = ""; artist = ""; artwork = nil; currentTime = 0; duration = 0
    }
}
