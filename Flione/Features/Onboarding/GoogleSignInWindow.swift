import AppKit
import WebKit

/// 用 Google 帳號登入 YouTube Music 的瀏覽器視窗（docs/youtube/DESIGN.md）。
/// 不用 Safari：Safari 的 cookie 只屬於 Safari，Flione 讀不到。登入頁就是 Google 的正式頁面，兩步驟驗證、通行金鑰都照常可用。
enum GoogleSignIn {
    /// 用 Safari 的 User-Agent，避免 Google 判定為「不安全的瀏覽器」而拒絕登入
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    static let url = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&uilel=3&passive=true&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Ddesktop%26next%3Dhttps%253A%252F%252Fmusic.youtube.com%252F")!

    @MainActor private static var current: GoogleSignInWindowController?

    /// 打開登入視窗；登入成功時呼叫 `onSuccess`，使用者關掉視窗則不呼叫
    @MainActor
    static func present(onSuccess: @escaping @MainActor () -> Void) {
        if let current { current.window?.makeKeyAndOrderFront(nil); return }
        let controller = GoogleSignInWindowController { success in
            current = nil
            if success { onSuccess() }
        }
        current = controller
        controller.showWindow(nil)
        controller.window?.center()
        NSApp.activate()
    }
}

@MainActor
private final class GoogleSignInWindowController: NSWindowController, WKNavigationDelegate, NSWindowDelegate {
    private let completion: (Bool) -> Void
    private var finished = false

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 640), configuration: WKWebViewConfiguration())
        webView.customUserAgent = GoogleSignIn.userAgent
        let window = NSWindow(contentRect: webView.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = String(localized: "Sign in to YouTube Music")
        window.contentView = webView
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        webView.navigationDelegate = self
        #if DEBUG
        webView.isInspectable = true
        #endif
        webView.load(URLRequest(url: GoogleSignIn.url))
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 導到 music.youtube.com 且拿到 SAPISID，就算登入完成
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView.url?.host()?.contains("music.youtube.com") == true else { return }
        Task { @MainActor in
            // cookie 寫入可能比頁面載入完成晚一點
            for _ in 0..<10 {
                if await InnerTube.sapisid() != nil { finish(true); return }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        finish(false)
    }

    private func finish(_ success: Bool) {
        guard !finished else { return }
        finished = true
        if success { window?.close() }
        completion(success)
    }
}
