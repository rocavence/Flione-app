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

    @ObservationIgnored private var webView: WKWebView?

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
            isPlaying = body["playing"] as? Bool ?? false
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

    func stop() {
        webView?.load(URLRequest(url: URL(string: "about:blank")!))
        webView?.removeFromSuperview()
        webView = nil
        hasTrack = false
        isPlaying = false
        title = ""; artist = ""; artwork = nil; currentTime = 0; duration = 0
    }
}
