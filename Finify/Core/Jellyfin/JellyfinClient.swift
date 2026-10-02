import Foundation

struct JellyfinSession: Codable, Sendable, Equatable {
    let serverURL: URL
    let serverName: String
    let userID: String
    let userName: String
    let accessToken: String
}

enum JellyfinError: Error, Equatable {
    /// 連不到 server（網路、網址錯誤、server 關機）
    case unreachable
    /// 帳號或密碼錯誤
    case invalidCredentials
    /// token 失效，需要重新登入
    case sessionExpired
    /// server 回應了，但不是預期的格式或狀態
    case unexpectedResponse(Int)
}

/// Jellyfin HTTP API。View 不直接使用，一律經過 `JellyfinRepository`。
final class JellyfinClient: Sendable {
    static let clientName = "Finify"
    static let clientVersion = "0.1.0"

    let serverURL: URL
    let accessToken: String?
    private let urlSession: URLSession

    init(serverURL: URL, accessToken: String? = nil, urlSession: URLSession = .shared) {
        self.serverURL = serverURL
        self.accessToken = accessToken
        self.urlSession = urlSession
    }

    static let deviceID: String = {
        let key = "FinifyDeviceID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    /// Jellyfin 12 只接受標準 Authorization header（X-Emby-Authorization 已無效）
    static func authorizationHeader(token: String?) -> String {
        var parts = [
            "Client=\"\(clientName)\"",
            "Device=\"Mac\"",
            "DeviceId=\"\(deviceID)\"",
            "Version=\"\(clientVersion)\"",
        ]
        if let token { parts.append("Token=\"\(token)\"") }
        return "MediaBrowser " + parts.joined(separator: ", ")
    }

    // MARK: - Server discovery

    /// 使用者可能只輸入 `mediabox`、`mediabox:8096` 或完整網址。依序嘗試可能的網址，回傳第一個回應 Jellyfin 的。
    static func candidateURLs(for input: String) -> [URL] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return [] }
        let hasScheme = trimmed.contains("://")
        let schemes = hasScheme ? [""] : ["http://", "https://"]
        var urls: [URL] = []
        for scheme in schemes {
            guard let url = URL(string: scheme + trimmed), let host = url.host, !host.isEmpty else { continue }
            // 沒指定 port 時先試 Jellyfin 預設 port（http 8096 / https 8920），再試原網址
            if url.port == nil, url.path.isEmpty {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                components.port = url.scheme == "https" ? 8920 : 8096
                if let withPort = components.url { urls.append(withPort) }
            }
            urls.append(url)
        }
        return urls
    }

    static func discover(_ input: String, urlSession: URLSession = .shared) async throws -> (URL, PublicSystemInfo) {
        for url in candidateURLs(for: input) {
            let client = JellyfinClient(serverURL: url, urlSession: urlSession)
            if let info: PublicSystemInfo = try? await client.get("/System/Info/Public", timeout: 4), info.id != nil {
                return (url, info)
            }
        }
        throw JellyfinError.unreachable
    }

    func authenticate(user: String, password: String, serverName: String) async throws -> JellyfinSession {
        let body = try JSONSerialization.data(withJSONObject: ["Username": user, "Pw": password])
        do {
            let response: AuthenticationResponse = try await send("POST", "/Users/AuthenticateByName", body: body)
            return JellyfinSession(
                serverURL: serverURL,
                serverName: serverName,
                userID: response.user.id,
                userName: response.user.name,
                accessToken: response.accessToken
            )
        } catch JellyfinError.sessionExpired {
            throw JellyfinError.invalidCredentials
        }
    }

    // MARK: - Requests

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], timeout: TimeInterval = 20) async throws -> T {
        try await send("GET", path, query: query, timeout: timeout)
    }

    func post(_ path: String, json: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: json)
        _ = try await sendRaw("POST", path, body: body, timeout: 10)
    }

    private func send<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil, timeout: TimeInterval = 20) async throws -> T {
        let data = try await sendRaw(method, path, query: query, body: body, timeout: timeout)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw JellyfinError.unexpectedResponse(200)
        }
    }

    private func sendRaw(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url(path, query: query), timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(Self.authorizationHeader(token: accessToken), forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw JellyfinError.unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return data
        case 401, 403:
            // 已登入的請求被拒絕：token 失效，通知 app 回到登入畫面
            if accessToken != nil { NotificationCenter.default.post(name: .finifySessionExpired, object: nil) }
            throw JellyfinError.sessionExpired
        default: throw JellyfinError.unexpectedResponse(status)
        }
    }

    func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: serverURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query
            // URLComponents 不會編碼「+」，server 會把它當空白（例如搜尋 C++）
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        return components.url!
    }

    /// Jellyfin 的日期有 7 位小數秒，ISO8601DateFormatter 不支援，先截到 3 位
    /// ISO8601DateFormatter 的解析是 thread-safe 的，但型別沒有標成 Sendable
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            var value = raw
            if let dot = raw.firstIndex(of: ".") {
                let fraction = raw[raw.index(after: dot)...].prefix { $0.isNumber }
                let rest = raw[raw.index(after: dot)...].dropFirst(fraction.count)
                value = String(raw[..<dot]) + "." + fraction.prefix(3) + rest
            }
            if let date = JellyfinClient.withFraction.date(from: value) ?? JellyfinClient.plain.date(from: value) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(raw)"))
        }
        return decoder
    }()
}

extension Notification.Name {
    static let finifySessionExpired = Notification.Name("FinifySessionExpired")
}
