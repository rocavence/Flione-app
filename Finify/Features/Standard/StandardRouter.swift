import Observation

enum StandardTab: Hashable, Sendable {
    case home
    case library(LibrarySection)
    /// 依加入時間排序的專輯
    case recentlyAdded
}

enum StandardRoute: Hashable, Sendable {
    case album(Album)
    case artist(id: String, name: String)
    case playlist(Playlist)
    case genre(Genre)
}

/// Standard mode 的導覽狀態：側欄選的頁面（tab）＋疊在上面的詳細頁（path），可上一頁／下一頁。
@MainActor @Observable
final class StandardRouter {
    var tab: StandardTab = .home {
        didSet {
            guard oldValue != tab else { return }
            path.removeAll()
            forward.removeAll()
        }
    }
    private(set) var path: [StandardRoute] = []
    /// 上一頁之後可以「下一頁」回去的頁面
    private(set) var forward: [StandardRoute] = []

    var canGoBack: Bool { !path.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    func open(_ route: StandardRoute) {
        guard path.last != route else { return }
        path.append(route)
        forward.removeAll()
    }

    func openAlbum(_ album: Album) { open(.album(album)) }

    func openArtist(id: String?, name: String) {
        guard let id else { return }
        open(.artist(id: id, name: name))
    }

    func back() {
        guard let last = path.popLast() else { return }
        forward.append(last)
    }

    func goForward() {
        guard let next = forward.popLast() else { return }
        path.append(next)
    }

    /// 回到目前頁面的根（側欄再點一次同一項）
    func popToRoot() {
        path.removeAll()
        forward.removeAll()
    }
}
