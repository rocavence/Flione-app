import SwiftUI

/// 進入點：`Flione --mcp` 是給 AI app 啟動的 MCP 轉送程式（D54），其他情況照常開啟 app
@main
enum Main {
    @MainActor static func main() {
        if CommandLine.arguments.dropFirst().first == "--mcp" { MCPProxy.run() }
        FlioneApp.main()
    }
}
