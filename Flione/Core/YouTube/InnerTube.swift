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

    /// POST `youtubei/v1/<endpoint>`，回傳解析後的 JSON
    @MainActor
    static func post(_ endpoint: String, body: [String: Any] = [:]) async throws -> [String: Any] {
        let all = await cookies().filter { $0.domain.hasSuffix("youtube.com") }
        guard let sapisid = all.first(where: { $0.name == "SAPISID" })?.value else { throw Failure.signedOut }

        var request = URLRequest(url: URL(string: "\(origin)/youtubei/v1/\(endpoint)?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(all.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
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
        try? data.write(to: URL(fileURLWithPath: "/tmp/flione-youtube-\(endpoint.replacingOccurrences(of: "/", with: "-")).json"))
        #endif
        return json
    }
}
