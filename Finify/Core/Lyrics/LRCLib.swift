import Foundation

/// Jellyfin 沒有歌詞時的備援：查 lrclib.net（免費、公開的歌詞資料庫）。
/// 會把歌名、藝人送到外部網站，所以預設關閉（見 D16）。做法改寫自 Kaset（MIT）的 LRCLibProvider。
enum LRCLib {
    struct Result: Decodable, Sendable {
        let duration: TimeInterval?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    static func lyrics(for track: Track, session: URLSession = .shared) async throws -> Lyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.name),
            URLQueryItem(name: "artist_name", value: track.artistName),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        request.setValue("Flione/\(version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let results = try JSONDecoder().decode([Result].self, from: data)
        return best(results, duration: track.duration).flatMap(lyrics(from:))
    }

    /// 有歌詞、不是純音樂的結果中，挑長度最接近的那一筆
    static func best(_ results: [Result], duration: TimeInterval) -> Result? {
        results
            .filter { ($0.syncedLyrics != nil || $0.plainLyrics != nil) && $0.instrumental != true }
            .min { abs(($0.duration ?? 0) - duration) < abs(($1.duration ?? 0) - duration) }
    }

    static func lyrics(from result: Result) -> Lyrics? {
        if let synced = result.syncedLyrics, let parsed = parseLRC(synced) { return parsed }
        guard let plain = result.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty else { return nil }
        return Lyrics(lines: plain.components(separatedBy: .newlines).map { Lyrics.Line(text: $0, start: nil) })
    }

    /// 解析 LRC：`[mm:ss.xx] 歌詞`，一行可以有多個時間標籤；`[ar:…]` 這類標籤略過
    static func parseLRC(_ text: String) -> Lyrics? {
        var lines: [Lyrics.Line] = []
        for raw in text.components(separatedBy: .newlines) {
            var rest = Substring(raw)
            var times: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let time = parseTime(tag) { times.append(time) }
                rest = rest[rest.index(after: close)...]
            }
            let lyric = rest.trimmingCharacters(in: .whitespaces)
            lines += times.map { Lyrics.Line(text: lyric, start: $0) }
        }
        guard !lines.isEmpty else { return nil }
        return Lyrics(lines: lines.sorted { ($0.start ?? 0) < ($1.start ?? 0) })
    }

    private static func parseTime(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
        return minutes * 60 + seconds
    }
}
