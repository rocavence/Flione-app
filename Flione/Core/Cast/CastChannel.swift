import Foundation
import Network

/// Cast 協定（CASTV2）的連線層：TLS 連到裝置的 8009 埠，每則訊息是「4 位元組長度＋protobuf CastMessage」。
/// Mac 沒有 Google 官方的 Cast SDK，訊息格式依 Chromium 的 cast_channel.proto 自行實作（D43）。
@MainActor
final class CastChannel {
    struct Message {
        let source: String
        let destination: String
        let namespace: String
        let payload: [String: Any]
    }

    enum Namespace {
        static let connection = "urn:x-cast:com.google.cast.tp.connection"
        static let heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
        static let receiver = "urn:x-cast:com.google.cast.receiver"
        static let media = "urn:x-cast:com.google.cast.media"
    }

    var onMessage: ((Message) -> Void)?
    var onReady: (() -> Void)?
    var onClose: ((Error?) -> Void)?
    #if DEBUG
    var onState: ((String) -> Void)?
    #endif

    private let connection: NWConnection
    private var heartbeat: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var closed = false
    /// 曾經連上過（逾時與連線後中斷的提示不同）
    private(set) var didConnect = false

    init(endpoint: NWEndpoint) {
        // 裝置用自簽憑證，Google 的 sender 也不驗證；連線只在區域網路內
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, .main)
        connection = NWConnection(to: endpoint, using: NWParameters(tls: tls, tcp: NWProtocolTCP.Options()))
    }

    func open() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                #if DEBUG
                self.onState?("\(state)")
                #endif
                switch state {
                case .ready:
                    self.didConnect = true
                    self.timeout?.cancel()
                    self.receiveNext()
                    self.startHeartbeat()
                    self.onReady?()
                case .failed(let error):
                    self.finish(error)
                case .cancelled:
                    self.finish(nil)
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        // 裝置關機或待機時，連線會一直停在「準備中」不會失敗；8 秒沒連上就放棄
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled, !self.didConnect else { return }
            self.connection.cancel()
        }
    }

    func close() {
        guard !closed else { return }
        heartbeat?.cancel()
        connection.cancel()
    }

    func send(_ payload: [String: Any], namespace: String, from source: String = "sender-0", to destination: String = "receiver-0") {
        guard !closed, let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        var body = Data()
        body.appendVarintField(1, 0)            // protocol_version = CASTV2_1_0
        body.appendStringField(2, source)
        body.appendStringField(3, destination)
        body.appendStringField(4, namespace)
        body.appendVarintField(5, 0)            // payload_type = STRING
        body.appendStringField(6, json)
        var frame = Data()
        var length = UInt32(body.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(body)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func finish(_ error: Error?) {
        guard !closed else { return }
        closed = true
        heartbeat?.cancel()
        timeout?.cancel()
        onClose?(error)
    }

    /// 裝置約 10 秒收不到訊息就斷線；每 5 秒送一次 PING
    private func startHeartbeat() {
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                self?.send(["type": "PING"], namespace: Namespace.heartbeat)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] header, _, _, error in
            MainActor.assumeIsolated {
                guard let self, error == nil, let header, header.count == 4 else {
                    self?.finish(error)
                    return
                }
                let length = header.reduce(0) { $0 << 8 | Int($1) }
                guard length > 0, length < 1 << 20 else { self.finish(nil); return }
                self.connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] body, _, _, error in
                    MainActor.assumeIsolated {
                        guard let self, error == nil, let body else { self?.finish(error); return }
                        self.handle(body)
                        self.receiveNext()
                    }
                }
            }
        }
    }

    private func handle(_ body: Data) {
        let fields = ProtobufReader.strings(in: body)
        guard let namespace = fields[4], let json = fields[6], let data = json.data(using: .utf8),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        let message = Message(source: fields[2] ?? "", destination: fields[3] ?? "", namespace: namespace, payload: payload)
        // 裝置送來的 PING 要回 PONG，否則會被斷線
        if namespace == Namespace.heartbeat, payload["type"] as? String == "PING" {
            send(["type": "PONG"], namespace: Namespace.heartbeat, to: message.source)
            return
        }
        onMessage?(message)
    }
}

// MARK: - protobuf（只需要 CastMessage 用到的 varint 與字串欄位）

private extension Data {
    mutating func appendVarint(_ value: UInt64) {
        var value = value
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            append(byte)
        } while value != 0
    }

    mutating func appendVarintField(_ field: UInt64, _ value: UInt64) {
        appendVarint(field << 3)
        appendVarint(value)
    }

    mutating func appendStringField(_ field: UInt64, _ value: String) {
        let bytes = Data(value.utf8)
        appendVarint(field << 3 | 2)
        appendVarint(UInt64(bytes.count))
        append(bytes)
    }
}

private enum ProtobufReader {
    /// 讀出長度分隔（wire type 2）的欄位當字串；varint 欄位略過
    static func strings(in data: Data) -> [Int: String] {
        var result: [Int: String] = [:]
        let bytes = [UInt8](data)
        var index = 0
        func varint() -> UInt64? {
            var value: UInt64 = 0, shift: UInt64 = 0
            while index < bytes.count {
                let byte = bytes[index]; index += 1
                value |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
                if shift > 63 { return nil }
            }
            return nil
        }
        while index < bytes.count, let key = varint() {
            let field = Int(key >> 3)
            switch key & 7 {
            case 0:
                guard varint() != nil else { return result }
            case 2:
                guard let length = varint(), index + Int(length) <= bytes.count else { return result }
                result[field] = String(decoding: bytes[index..<index + Int(length)], as: UTF8.self)
                index += Int(length)
            default:
                return result
            }
        }
        return result
    }
}
