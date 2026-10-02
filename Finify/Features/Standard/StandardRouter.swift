import Observation

enum StandardTab: String, CaseIterable, Sendable {
    case home = "Home"
    case library = "Library"
}

enum StandardRoute: Hashable, Sendable {
    case album(Album)
    case artist(id: String, name: String)
    case playlist(Playlist)
}

/// Standard mode 的導覽狀態。tab 根畫面常駐（保留捲動位置），詳細頁疊在上面。
@MainActor @Observable
final class StandardRouter {
    var tab: StandardTab = .home {
        didSet { if oldValue != tab { path.removeAll() } }
    }
    private(set) var path: [StandardRoute] = []

    var canGoBack: Bool { !path.isEmpty }

    func open(_ route: StandardRoute) {
        guard path.last != route else { return }
        path.append(route)
    }

    func openAlbum(_ album: Album) { open(.album(album)) }

    func openArtist(id: String?, name: String) {
        guard let id else { return }
        open(.artist(id: id, name: name))
    }

    func back() {
        _ = path.popLast()
    }
}
