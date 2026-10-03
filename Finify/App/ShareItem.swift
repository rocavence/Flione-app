import AppKit
import SwiftUI

/// 分享歌曲或專輯：文字是「名稱 — 藝人」，連結是 Jellyfin 網頁版的項目頁
/// （只有同一台 server 的使用者打得開；見 D15）。
struct ShareItem {
    let text: String
    let url: URL?

    var items: [Any] { [text] + (url.map { [$0] } ?? []) }
}

extension AppEnvironment {
    func shareItem(for track: Track) -> ShareItem {
        ShareItem(text: "\(track.name) — \(track.artistName)", url: webURL(itemID: track.id))
    }

    func shareItem(for album: Album) -> ShareItem {
        ShareItem(text: "\(album.name) — \(album.artistName)", url: webURL(itemID: album.id))
    }

    private func webURL(itemID: String) -> URL? {
        guard let server = session?.serverURL else { return nil }
        return URL(string: server.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/web/#/details?id=\(itemID)")
    }
}

/// SwiftUI 右鍵選單用的「Share」子選單
struct ShareMenu: View {
    let item: ShareItem

    var body: some View {
        if let url = item.url {
            ShareLink(item: url, subject: Text(item.text), message: Text(item.text)) { Text("Share…") }
        } else {
            ShareLink(item: item.text) { Text("Share…") }
        }
    }
}
