import XCTest
@testable import Flione

/// AI 控制（D54）：JSON-RPC 協定、本機 socket，以及對真實 server 的工具流程（只用暫存 playlist）
@MainActor
final class MCPTests: XCTestCase {
    private func request(_ controller: MCPController, _ method: String, _ params: [String: Any] = [:], id: Int = 1) async throws -> [String: Any] {
        let line = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        let handled = await controller.handle(line)
        let reply = try XCTUnwrap(handled)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: reply) as? [String: Any])
    }

    /// tools/call 的結果：(內容解析成 JSON, 是否錯誤)
    private func call(_ controller: MCPController, _ tool: String, _ arguments: [String: Any] = [:]) async throws -> (Any, Bool) {
        let reply = try await request(controller, "tools/call", ["name": tool, "arguments": arguments])
        let result = try XCTUnwrap(reply["result"] as? [String: Any], "\(reply)")
        let text = try XCTUnwrap((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        let value = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) ?? text
        return (value, result["isError"] as? Bool ?? false)
    }

    private func signedOutApp() -> AppEnvironment {
        AppEnvironment(sessionStore: DevelopmentSessionStore(directory: FileManager.default.temporaryDirectory.appending(path: "FlioneMCPTest-\(UUID().uuidString)")))
    }

    // MARK: - 協定

    func testInitializeAndToolList() async throws {
        let controller = MCPController(socketPath: "")
        controller.attach(signedOutApp())
        let initialize = try await request(controller, "initialize", ["protocolVersion": "2025-06-18", "clientInfo": ["name": "Claude", "version": "1"]])
        let result = try XCTUnwrap(initialize["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-06-18")
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "flione")
        XCTAssertEqual(controller.clientName, "Claude")

        // 不認得的版本：回覆我們支援的版本
        let old = try await request(controller, "initialize", ["protocolVersion": "1999-01-01"])
        XCTAssertTrue(MCPController.protocolVersions.contains((old["result"] as? [String: Any])?["protocolVersion"] as? String ?? ""))

        let list = try await request(controller, "tools/list")
        let names = ((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        XCTAssertTrue(names.contains("play"))
        XCTAssertTrue(names.contains("delete_playlist"))
        // 每個工具都有合法的 JSON Schema 物件
        for tool in MCPController.tools {
            XCTAssertEqual((tool["inputSchema"] as? [String: Any])?["type"] as? String, "object", "\(tool["name"] ?? "")")
        }
    }

    func testNotificationsAndErrors() async throws {
        let controller = MCPController(socketPath: "")
        controller.attach(signedOutApp())
        // 通知沒有 id，不回覆
        let notification = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "notifications/initialized"])
        let none = await controller.handle(notification)
        XCTAssertNil(none)

        let unknown = try await request(controller, "resources/list")
        XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32601)

        let badTool = try await request(controller, "tools/call", ["name": "format_disk"])
        XCTAssertEqual((badTool["error"] as? [String: Any])?["code"] as? Int, -32602)

        let garbage = await controller.handle(Data("not json".utf8))
        let parsed = try XCTUnwrap(garbage.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual((parsed["error"] as? [String: Any])?["code"] as? Int, -32700)
    }

    func testToolsNeedASignedInSource() async throws {
        let controller = MCPController(socketPath: "")
        controller.attach(signedOutApp())
        let (state, stateError) = try await call(controller, "get_now_playing")
        XCTAssertFalse(stateError)
        XCTAssertEqual((state as? [String: Any])?["state"] as? String, "stopped")

        let (message, isError) = try await call(controller, "search_library", ["query": "a"])
        XCTAssertTrue(isError)
        XCTAssertTrue((message as? String ?? "").contains("signed in"))
    }

    // MARK: - socket

    func testSocketRoundTrip() async throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "mcp-\(UUID().uuidString.prefix(8)).sock").path
        let server = MCPSocketServer(path: path) { line, reply in reply(Data("echo:".utf8) + line) }
        try server.start()
        defer { server.stop() }
        var attributes = try FileManager.default.attributesOfItem(atPath: path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        let fd = MCPSocket.connect(path)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        // 兩則訊息一次送：要逐行分開處理
        XCTAssertTrue(MCPSocket.write(Data("one\ntwo\n".utf8), to: fd))
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        let deadline = Date().addingTimeInterval(3)
        while received.filter({ $0 == 0x0A }).count < 2, Date() < deadline {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 { received.append(contentsOf: buffer[0..<count]) }
        }
        XCTAssertEqual(String(decoding: received, as: UTF8.self), "echo:one\necho:two\n")

        server.stop()
        attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
        XCTAssertTrue(attributes.isEmpty, "停止後 socket 檔要刪掉")
        XCTAssertEqual(MCPSocket.connect(path), -1)
    }

    // MARK: - 真實 server

    func testPlaylistToolsAgainstServer() async throws {
        guard let secrets = DevelopmentSessionStore.repoSecrets else { throw XCTSkip("沒有 .secrets/") }
        // test host 和 app 共用設定：暫時切到 Jellyfin，結束後還原使用者選的來源
        let sourceKey = "FlioneSource"
        let originalSource = UserDefaults.standard.string(forKey: sourceKey)
        defer { UserDefaults.standard.set(originalSource, forKey: sourceKey) }
        UserDefaults.standard.set("jellyfin", forKey: sourceKey)
        let app = AppEnvironment(sessionStore: DevelopmentSessionStore(directory: secrets))
        guard app.session?.isYouTube == false else { throw XCTSkip("測試用的登入不是 Jellyfin") }
        app.player.muteForTesting()
        let controller = MCPController(socketPath: "")
        controller.attach(app)
        var asked: [String] = []
        var answer = false
        controller.confirmDelete = { playlist, _ in asked.append(playlist.name); return answer }

        // 從音樂庫挑一張專輯的歌
        let repository = try XCTUnwrap(app.repository as? JellyfinRepository)
        let pick = try await IntegrationFixture.album(from: repository)
        let (songsValue, songsError) = try await call(controller, "get_tracks", ["album_id": pick.album.id])
        XCTAssertFalse(songsError)
        let songs = try XCTUnwrap((songsValue as? [String: Any])?["songs"] as? [[String: Any]])
        let ids = songs.prefix(2).compactMap { $0["id"] as? String }
        XCTAssertEqual(ids.count, 2)

        // 沒看過的 id 要拒絕，不能亂播
        let (_, unknownError) = try await call(controller, "add_to_queue", ["track_ids": ["made-up-id"]])
        XCTAssertTrue(unknownError)

        let (created, createError) = try await call(controller, "create_playlist", ["name": "Flione Test (MCP)", "track_ids": ids])
        XCTAssertFalse(createError, "\(created)")
        let playlistID = try XCTUnwrap(((created as? [String: Any])?["playlist"] as? [String: Any])?["id"] as? String)

        let (_, addError) = try await call(controller, "add_to_playlist", ["playlist_id": playlistID, "track_ids": [ids[0]]])
        XCTAssertFalse(addError)
        let stored = try await repository.playlistTracks(playlistID).map(\.id)
        XCTAssertEqual(stored, ids + [ids[0]])

        // 使用者拒絕：不刪
        let (_, declined) = try await call(controller, "delete_playlist", ["playlist_id": playlistID])
        XCTAssertTrue(declined)
        XCTAssertEqual(asked, ["Flione Test (MCP)"])
        let stillThere = try await repository.playlists().contains { $0.id == playlistID }
        XCTAssertTrue(stillThere)

        // 使用者同意：刪除
        answer = true
        let (_, deleteError) = try await call(controller, "delete_playlist", ["playlist_id": playlistID])
        XCTAssertFalse(deleteError)
        let gone = try await repository.playlists().contains { $0.id == playlistID }
        XCTAssertFalse(gone)
    }
}
