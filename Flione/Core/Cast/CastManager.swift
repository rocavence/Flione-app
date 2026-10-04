import Foundation
import Network
import Observation

/// 區域網路上的 Chromecast（含內建 Cast 的電視）
struct CastDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
}

/// 投放：找裝置、開始與停止投放。一次只從一個裝置出聲：投放時 Mac 停止播放（D43）。
/// 目前只支援 Jellyfin；YouTube Music 的音訊在網頁播放器裡，沒有網址可以交給裝置
@MainActor @Observable
final class CastManager {
    private(set) var devices: [CastDevice] = []
    /// 正在投放的裝置
    private(set) var activeDevice: CastDevice?

    /// 投放用的伺服器位址（設定 → 音樂來源）：Jellyfin 的位址裝置連不到時（例如 Tailscale），改用這個
    static let serverKey = "FlioneCastServer"

    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var session: CastSession?

    /// 開始在區域網路找裝置（打開選單列時呼叫；已經在找就不重複）
    func startDiscovery() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_googlecast._tcp", domain: nil), using: NWParameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.update(results) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        devices = results.compactMap { result -> CastDevice? in
            guard case .service(let name, _, _, _) = result.endpoint else { return nil }
            var friendly = name
            var id = name
            if case .bonjour(let txt) = result.metadata {
                if let fn = txt.dictionary["fn"], !fn.isEmpty { friendly = fn }
                if let value = txt.dictionary["id"], !value.isEmpty { id = value }
            }
            return CastDevice(id: id, name: friendly, endpoint: result.endpoint)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func cast(to device: CastDevice, player: PlayerManager) {
        if activeDevice != nil { stop(player: player, resumeLocally: false) }
        let session = CastSession(endpoint: device.endpoint)
        session.rewriteURL = Self.rewrite
        session.onEnded = { [weak self, weak player] connected in
            guard let self, self.session === session else { return }
            self.session = nil
            self.activeDevice = nil
            // 一開始就連不上：回到 Mac 繼續播放並提示；投放中斷線：停在原位置，不突然從 Mac 出聲
            player?.stopCasting(resumeLocally: !connected)
            player?.post(notice: connected
                ? String(localized: "Lost connection to \(device.name).")
                : String(localized: "Couldn't connect to \(device.name). Make sure it's turned on and on the same network."))
        }
        self.session = session
        activeDevice = device
        player.startCasting(session)
    }

    func stop(player: PlayerManager, resumeLocally: Bool = true) {
        guard activeDevice != nil else { return }
        session?.onEnded = nil
        session = nil
        activeDevice = nil
        player.stopCasting(resumeLocally: resumeLocally)
    }

    #if DEBUG
    @ObservationIgnored private var probeChannel: CastChannel?

    /// -FlioneDemoCastProbe <檔案>：連到第一台裝置、只問接收器狀態（不開啟任何 app，電視不會被喚醒），把結果寫進檔案
    func runProbeIfRequested(player: PlayerManager) {
        // -FlioneDemoCastTo <秒>：幾秒後投放到第一台找到的裝置（搭配 -FlioneDemoPlay）
        let castDelay = UserDefaults.standard.double(forKey: "FlioneDemoCastTo")
        if castDelay > 0 {
            startDiscovery()
            Task {
                try? await Task.sleep(for: .seconds(castDelay))
                if let device = devices.first { cast(to: device, player: player) }
            }
        }
        guard let path = UserDefaults.standard.string(forKey: "FlioneDemoCastProbe") else { return }
        startDiscovery()
        func note(_ line: String) {
            let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            try? (existing + line + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
        Task {
            for _ in 0..<20 where devices.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            guard let device = devices.first else { note("no devices"); return }
            note("device: \(device.name)")
            let channel = CastChannel(endpoint: device.endpoint)
            channel.onReady = {
                note("tls ready")
                channel.send(["type": "CONNECT"], namespace: CastChannel.Namespace.connection)
                channel.send(["type": "GET_STATUS", "requestId": 1], namespace: CastChannel.Namespace.receiver)
            }
            channel.onMessage = { message in
                let apps = ((message.payload["status"] as? [String: Any])?["applications"] as? [[String: Any]])?.compactMap { $0["displayName"] as? String } ?? []
                note("message \(message.namespace.split(separator: ".").last ?? "") \(message.payload["type"] ?? "") apps=\(apps)")
            }
            channel.onClose = { error in note("closed \(error.map { "\($0)" } ?? "")") }
            channel.onState = { note("state \($0)") }
            channel.open()
            probeChannel = channel
            try? await Task.sleep(for: .seconds(12))
            note("still open after 12s (heartbeat ok)")
            channel.close()
        }
    }
    #endif

    /// 把網址的伺服器部分換成投放用的位址；沒設定時照原樣
    private static func rewrite(_ url: URL) -> URL {
        guard let value = UserDefaults.standard.string(forKey: serverKey)?.trimmingCharacters(in: .whitespaces), !value.isEmpty,
              let base = URL(string: value.contains("://") ? value : "http://\(value)"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = base.scheme
        components.host = base.host
        components.port = base.port
        return components.url ?? url
    }
}
