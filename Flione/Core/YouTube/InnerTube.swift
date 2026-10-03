import CryptoKit
import Foundation
import WebKit

/// YouTube Music 網頁版使用的 InnerTube API（沒有公開文件，做法參考 Kaset，MIT）。
/// 登入資訊就是 Google／YouTube 的 cookie，存在 app 的 WebKit 資料裡；每次請求用 SAPISID 算出 SAPISIDHASH。
enum InnerTube {
    static let origin = "https://music.youtube.com"
    /// WEB_REMIX（YouTube Music 網頁版）的用戶端版本
    static let clientVersion = "1.20251001.01.00"

    enum Failure: Error, Equatable {
        case signedOut
        case badResponse(Int)
    }

    /// app 的 WebKit cookie（登入視窗與之後的網頁播放器共用）
    @MainActor
    static func cookies() async -> [HTTPCookie] {
        await WKWebsiteDataStore.default().httpCookieStore.allCookies()
    }

    /// 已登入：有 YouTube 網域的 SAPISID cookie 且未過期
    @MainActor
    static func sapisid() async -> String? {
        await cookies().first { cookie in
            cookie.name == "SAPISID" && cookie.domain.hasSuffix("youtube.com")
                && (cookie.expiresDate ?? .distantFuture) > .now
        }?.value
    }

    static func sapisidHash(_ sapisid: String, timestamp: Int = Int(Date().timeIntervalSince1970)) -> String {
        let digest = Insecure.SHA1.hash(data: Data("\(timestamp) \(sapisid) \(origin)".utf8))
        return "\(timestamp)_" + digest.map { String(format: "%02x", $0) }.joined()
    }

    /// cookie 標頭與 SAPISID（讀 WebKit 的 cookie 要在 main thread）
    @MainActor
    private static func credentials() async -> (cookie: String, sapisid: String)? {
        let all = await cookies().filter { $0.domain.hasSuffix("youtube.com") }
        guard let sapisid = all.first(where: { $0.name == "SAPISID" })?.value else { return nil }
        return (all.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), sapisid)
    }

    /// POST `youtubei/v1/<endpoint>`，回傳解析後的 JSON。網路請求與解析在背景進行
    static func post(_ endpoint: String, body: [String: Any] = [:], continuation: String? = nil) async throws -> [String: Any] {
        guard let credentials = await credentials() else { throw Failure.signedOut }
        let sapisid = credentials.sapisid

        var components = URLComponents(string: "\(origin)/youtubei/v1/\(endpoint)")!
        components.queryItems = [URLQueryItem(name: "prettyPrint", value: "false")]
            // 下一頁：帶上一頁回應裡的 continuation token
            + (continuation.map { [URLQueryItem(name: "ctoken", value: $0), URLQueryItem(name: "continuation", value: $0), URLQueryItem(name: "type", value: "next")] } ?? [])
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.cookie, forHTTPHeaderField: "Cookie")
        request.setValue("SAPISIDHASH \(sapisidHash(sapisid))", forHTTPHeaderField: "Authorization")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue(origin, forHTTPHeaderField: "X-Origin")
        request.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
        request.setValue(GoogleSignIn.userAgent, forHTTPHeaderField: "User-Agent")

        var payload = body
        payload["context"] = [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": clientVersion,
                "hl": Locale.preferredLanguages.first ?? "en",
                "utcOffsetMinutes": TimeZone.current.secondsFromGMT() / 60,
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.badResponse(status)
        }
        #if DEBUG
        // 開發用：保留原始回應，分析 YouTube Music 的資料格式
        let target = (body["browseId"] as? String) ?? (body["query"] as? String) ?? (body["playlistId"] as? String) ?? ""
        let name = [endpoint.replacingOccurrences(of: "/", with: "-"), target].filter { !$0.isEmpty }.joined(separator: "-")
        try? data.write(to: URL(fileURLWithPath: "/tmp/flione-youtube-\(name).json"))
        #endif
        return json
    }
}
