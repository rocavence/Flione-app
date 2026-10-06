import AppKit

/// `Flione --mcp`：AI app（Claude、Cursor…）用 stdio 啟動的 MCP server（D54）。
/// 本身不做事，只把 stdin／stdout 的訊息轉給正在執行的 Flione；Flione 沒開就在背景打開它。
/// 這個行程不建立 NSApplication，不會出現在 Dock
enum MCPProxy {
    static func run() -> Never {
        signal(SIGPIPE, SIG_IGN)
        let path = MCPController.defaultSocketPath
        var fd = MCPSocket.connect(path)
        if fd < 0 {
            // 設定裡沒打開：不用打開 Flione 等它，直接告訴 AI app 怎麼打開
            guard UserDefaults.standard.bool(forKey: MCPController.enabledKey) else { serveUnavailable() }
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                .contains { $0.processIdentifier != getpid() }
            if !running { launchApp() }
            // 剛打開的 Flione 要一點時間啟動；已經開著但連不上，多半是 AI 控制沒打開
            let deadline = Date().addingTimeInterval(running ? 1 : 20)
            while fd < 0, Date() < deadline {
                usleep(250_000)
                fd = MCPSocket.connect(path)
            }
        }
        guard fd >= 0 else { serveUnavailable() }

        // stdin → Flione
        let input = fd
        Thread.detachNewThread {
            while let line = readLine(strippingNewline: true) {
                guard !line.isEmpty, MCPSocket.write(Data((line + "\n").utf8), to: input) else { continue }
            }
            exit(0)
        }
        // Flione → stdout
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { exit(0) }
            FileHandle.standardOutput.write(Data(buffer[0..<count]))
        }
    }

    private static func launchApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in done.signal() }
        _ = done.wait(timeout: .now() + 10)
    }

    /// 連不上 Flione：每個請求都回錯誤，讓 AI app 顯示原因
    private static func serveUnavailable() -> Never {
        while let line = readLine(strippingNewline: true) {
            guard let request = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = request["id"] else { continue }
            let reply: [String: Any] = [
                "jsonrpc": "2.0", "id": id,
                "error": ["code": -32000, "message": "Flione isn't accepting AI connections. Open Flione → Settings → AI Control and turn on “Let AI apps control Flione”."],
            ]
            if let data = try? JSONSerialization.data(withJSONObject: reply) {
                FileHandle.standardOutput.write(data + Data([0x0A]))
            }
        }
        exit(0)
    }
}
