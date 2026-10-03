import Foundation
import Network

/// 一次投放：在裝置上開啟 Google 的預設媒體接收器（Default Media Receiver），把 Jellyfin 的串流網址交給它播。
/// 裝置自己向伺服器抓音樂；Flione 只送指令、每秒查一次狀態（D43）
@MainActor
final class CastSession: RemotePlaybackEngine {
    /// Google 的 Default Media Receiver
    private static let mediaReceiverAppID = "CC1AD845"

    var volume: Float = 1 { didSet { sendVolume() } }
    var onUpdate: ((RemotePlaybackUpdate) -> Void)?
    /// 連線中斷或接收器被別的 app 取代；參數為 false 表示一開始就連不上（裝置關機或待機）
    var onEnded: ((Bool) -> Void)?
    /// 把串流網址換成裝置連得到的伺服器位址
    var rewriteURL: (URL) -> URL = { $0 }

    private let channel: CastChannel
    private var transportID: String?
    private var sessionID: String?
    private var mediaSessionID: Int?
    private var requestID = 1
    private var pendingLoad: [String: Any]?
    private var poll: Task<Void, Never>?
    private var lastTime: Double = 0
    private var lastDuration: Double = 0

    init(endpoint: NWEndpoint) {
        channel = CastChannel(endpoint: endpoint)
        channel.onReady = { [weak self] in self?.connected() }
        channel.onMessage = { [weak self] in self?.received($0) }
        channel.onClose = { [weak self] _ in self?.closed() }
        channel.open()
    }

    // MARK: RemotePlaybackEngine

    func load(_ track: Track, url: URL?, artwork: URL?, at position: TimeInterval) {
        guard let url else { return }
        var metadata: [String: Any] = ["metadataType": 3, "title": track.name, "artist": track.artistName, "albumName": track.albumName]
        if let artwork { metadata["images"] = [["url": rewriteURL(artwork).absoluteString]] }
        let media: [String: Any] = [
            "contentId": rewriteURL(url).absoluteString,
            "contentType": Self.contentType(for: track.container),
            "streamType": "BUFFERED",
            "metadata": metadata,
        ]
        mediaSessionID = nil
        lastTime = position
        lastDuration = track.duration
        let request: [String: Any] = ["type": "LOAD", "media": media, "autoplay": true, "currentTime": position]
        if transportID == nil { pendingLoad = request } else { sendMedia(request) }
    }

    func pause() { sendMediaCommand("PAUSE") }
    func resume() { sendMediaCommand("PLAY") }

    func seek(to seconds: Double) {
        lastTime = seconds
        sendMediaCommand("SEEK", extra: ["currentTime": seconds])
    }

    /// 停止投放：關掉裝置上的接收器並斷線
    func stop() {
        poll?.cancel()
        onEnded = nil
        if let sessionID {
            channel.send(["type": "STOP", "sessionId": sessionID, "requestId": nextRequestID()], namespace: CastChannel.Namespace.receiver)
        }
        channel.close()
    }

    // MARK: 協定流程

    private func connected() {
        channel.send(["type": "CONNECT"], namespace: CastChannel.Namespace.connection)
        channel.send(["type": "LAUNCH", "appId": Self.mediaReceiverAppID, "requestId": nextRequestID()], namespace: CastChannel.Namespace.receiver)
    }

    private func received(_ message: CastChannel.Message) {
        let type = message.payload["type"] as? String
        switch message.namespace {
        case CastChannel.Namespace.receiver where type == "RECEIVER_STATUS":
            receiverStatus(message.payload)
        case CastChannel.Namespace.media where type == "MEDIA_STATUS":
            mediaStatus(message.payload)
        case CastChannel.Namespace.media where type == "LOAD_FAILED" || type == "INVALID_REQUEST":
            onUpdate?(RemotePlaybackUpdate(playing: false, time: lastTime, duration: lastDuration, trackID: nil, ended: false, failed: true))
        case CastChannel.Namespace.connection where type == "CLOSE":
            closed()
        default:
            break
        }
    }

    private func receiverStatus(_ payload: [String: Any]) {
        let apps = (payload["status"] as? [String: Any])?["applications"] as? [[String: Any]] ?? []
        guard let app = apps.first(where: { $0["appId"] as? String == Self.mediaReceiverAppID }),
              let transport = app["transportId"] as? String else {
            // 接收器被別的 app 取代（例如有人從手機投放）
            if transportID != nil { closed() }
            return
        }
        sessionID = app["sessionId"] as? String
        guard transport != transportID else { return }
        transportID = transport
        channel.send(["type": "CONNECT"], namespace: CastChannel.Namespace.connection, to: transport)
        if let pendingLoad {
            self.pendingLoad = nil
            sendMedia(pendingLoad)
        }
        startPolling()
    }

    private func mediaStatus(_ payload: [String: Any]) {
        guard let status = (payload["status"] as? [[String: Any]])?.first else { return }
        if let id = status["mediaSessionId"] as? Int, id != mediaSessionID {
            mediaSessionID = id
            sendVolume()
        }
        let state = status["playerState"] as? String ?? "IDLE"
        let idleReason = status["idleReason"] as? String
        if let time = status["currentTime"] as? Double { lastTime = time }
        if let duration = (status["media"] as? [String: Any])?["duration"] as? Double, duration > 0 { lastDuration = duration }
        onUpdate?(RemotePlaybackUpdate(playing: state == "PLAYING" || state == "BUFFERING", time: lastTime, duration: lastDuration,
                                       trackID: nil, ended: state == "IDLE" && idleReason == "FINISHED",
                                       failed: state == "IDLE" && idleReason == "ERROR"))
    }

    /// 裝置只在狀態改變時主動回報；播放進度每秒問一次
    private func startPolling() {
        poll?.cancel()
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.sendMedia(["type": "GET_STATUS"])
            }
        }
    }

    private func closed() {
        poll?.cancel()
        let ended = onEnded
        onEnded = nil
        ended?(channel.didConnect)
    }

    private func sendMedia(_ request: [String: Any]) {
        guard let transportID else { return }
        var request = request
        request["requestId"] = nextRequestID()
        channel.send(request, namespace: CastChannel.Namespace.media, to: transportID)
    }

    private func sendMediaCommand(_ type: String, extra: [String: Any] = [:]) {
        guard let mediaSessionID else { return }
        sendMedia(extra.merging(["type": type, "mediaSessionId": mediaSessionID]) { $1 })
    }

    /// 只調這段串流的音量，不改電視本身的音量
    private func sendVolume() {
        sendMediaCommand("SET_VOLUME", extra: ["volume": ["level": Double(volume)]])
    }

    private func nextRequestID() -> Int {
        requestID += 1
        return requestID
    }

    private static func contentType(for container: String?) -> String {
        switch container?.lowercased() {
        case "flac": "audio/flac"
        case "m4a", "mp4", "aac", "alac": "audio/mp4"
        case "ogg", "oga", "opus": "audio/ogg"
        case "wav": "audio/wav"
        case "webm": "audio/webm"
        default: "audio/mpeg"
        }
    }
}
