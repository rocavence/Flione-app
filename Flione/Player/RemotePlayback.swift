import Foundation

/// 佇列由 PlayerManager 管、一次只播一首的外部播放引擎：YouTube Music 的網頁播放器、Chromecast（D43）
@MainActor
protocol RemotePlaybackEngine: AnyObject {
    var volume: Float { get set }
    var onUpdate: ((RemotePlaybackUpdate) -> Void)? { get set }
    /// 開始播放這首；`url` 是 Jellyfin 串流網址（YouTube Music 不用），`position` 是開始的秒數
    func load(_ track: Track, url: URL?, artwork: URL?, at position: TimeInterval)
    func pause()
    func resume()
    func seek(to seconds: Double)
    func stop()
}

/// 外部引擎回報的播放狀態
struct RemotePlaybackUpdate {
    let playing: Bool
    let time: Double
    let duration: Double
    /// 目前播的曲目 id；與 Flione 要播的不同時，代表引擎自己換到別首（YouTube 自動播放）。nil 表示不回報
    let trackID: String?
    let ended: Bool
    /// 播放失敗（例如投放裝置連不到伺服器）
    var failed = false
}
