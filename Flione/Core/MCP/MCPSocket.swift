import Foundation

/// AI 控制（D54）的本機連線：Flione 在 Application Support 開一個 Unix socket，`Flione --mcp`（MCPProxy）連進來轉送訊息。
/// 一行一則 JSON-RPC 訊息。只有這台 Mac 上同一個使用者的程式能連（檔案權限 600），不開網路連接埠
enum MCPSocket {
    static var path: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.rocavence.Flione/mcp.sock").path
    }

    static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        return address
    }

    /// 連到 Flione；Flione 沒開或沒打開 AI 控制時回傳 -1
    static func connect(_ path: String = MCPSocket.path) -> Int32 {
        guard var address = address(path) else { return -1 }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { close(fd); return -1 }
        return fd
    }

    /// 寫完整筆資料（write 一次可能只寫一部分）
    @discardableResult
    static func write(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 { if errno == EINTR { continue }; return false }
                offset += written
            }
            return true
        }
    }
}

/// App 這一端：接受連線、逐行交給 handler、把回覆寫回去
final class MCPSocketServer: @unchecked Sendable {
    typealias Handler = @Sendable (Data, @escaping @Sendable (Data?) -> Void) -> Void

    private let path: String
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.rocavence.Flione.mcp")
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Int32: (source: DispatchSourceRead, buffer: Data)] = [:]
    /// 連線數改變時通知（設定頁顯示「已連線」）
    var onClientCountChange: (@Sendable (Int) -> Void)?

    init(path: String = MCPSocket.path, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    func start() throws {
        try queue.sync {
            guard listenFD < 0 else { return }
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            unlink(path)
            guard var address = MCPSocket.address(path) else { throw POSIXError(.ENAMETOOLONG) }
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw POSIXError(.EIO) }
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
                close(fd)
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            listenFD = fd
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.accept() }
            source.resume()
            acceptSource = source
        }
    }

    func stop() {
        queue.sync {
            for fd in clients.keys { drop(fd) }
            acceptSource?.cancel()
            acceptSource = nil
            if listenFD >= 0 { close(listenFD) }
            listenFD = -1
            unlink(path)
        }
    }

    private func accept() {
        let fd = Darwin.accept(listenFD, nil, nil)
        guard fd >= 0 else { return }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.read(fd) }
        clients[fd] = (source, Data())
        source.resume()
        onClientCountChange?(clients.count)
    }

    private func read(_ fd: Int32) {
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        let count = Darwin.read(fd, &chunk, chunk.count)
        guard count > 0, var client = clients[fd] else { drop(fd); return }
        client.buffer.append(contentsOf: chunk[0..<count])
        while let newline = client.buffer.firstIndex(of: 0x0A) {
            let line = client.buffer[client.buffer.startIndex..<newline]
            client.buffer.removeSubrange(client.buffer.startIndex...newline)
            guard !line.isEmpty else { continue }
            handler(Data(line)) { [weak self] reply in
                guard let reply, let self else { return }
                self.queue.async {
                    guard self.clients[fd] != nil else { return }
                    MCPSocket.write(reply + Data([0x0A]), to: fd)
                }
            }
        }
        clients[fd] = client
    }

    private func drop(_ fd: Int32) {
        guard let client = clients.removeValue(forKey: fd) else { return }
        client.source.cancel()
        close(fd)
        onClientCountChange?(clients.count)
    }
}
