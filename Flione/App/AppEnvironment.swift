import AppKit
import Network
import Observation

enum AppMode: String, Sendable {
    case standard, overflow
}

/// 使用者看到的三種模式。Infinity 與 Cover Flow 共用 Overflow 的畫面（深色、封面為主），只是版面不同。
enum ViewMode: CaseIterable, Sendable {
    case standard, infinity, coverFlow

    var title: String {
        switch self {
        case .standard: "Modern"
        case .infinity: "Infinity"
        case .coverFlow: "Cover Flow"
        }
    }

    var icon: Reicon {
        switch self {
        case .standard: .menu
        case .infinity: .infinite
        case .coverFlow: .carouselH
        }
    }

    var shortcut: Character {
        switch self {
        case .standard: "1"
        case .infinity: "2"
        case .coverFlow: "3"
        }
    }
}

/// 音樂來源（D39）：Jellyfin 伺服器或 YouTube Music，可隨時切換，兩邊的登入都保留
enum MusicSource: String, CaseIterable, Sendable {
    case jellyfin, youtube

    /// 產品名稱，不翻譯
    var title: String {
        switch self {
        case .jellyfin: "Jellyfin"
        case .youtube: "YouTube Music"
        }
    }
}

/// App 層的狀態與依賴：登入、repository、artwork、播放器、目前 mode。
@MainActor @Observable
final class AppEnvironment {
    private(set) var session: JellyfinSession?
    private(set) var repository: (any MusicRepository)?
    private(set) var images: ImagePipeline?
    let player = PlayerManager()
    let library = LibraryStore()
    let favorites = FavoritesStore()
    let playlists = PlaylistStore()
    /// YouTube Music 帳號（youtube-music 分支，docs/youtube/DESIGN.md）
    let youtube = YouTubeAccount()
    /// YouTube Music 的網頁播放器（第二階段）
    let youtubePlayer = YouTubeWebPlayer()
    /// Chromecast 投放（D43）
    let cast = CastManager()

    /// nil = 尚未選擇（首次登入後顯示 mode picker）
    var mode: AppMode? {
        didSet {
            if rememberMode { UserDefaults.standard.set(mode?.rawValue, forKey: Self.modeKey) }
        }
    }
    /// Overflow 畫面的版面：Infinity（封面牆）或 Cover Flow
    var overflowLayout: OverflowLayout = OverflowLayout(rawValue: UserDefaults.standard.string(forKey: "FinifyOverflowLayout") ?? "") ?? .wall {
        didSet { UserDefaults.standard.set(overflowLayout.rawValue, forKey: "FinifyOverflowLayout") }
    }

    var viewMode: ViewMode {
        get {
            guard mode == .overflow else { return .standard }
            return overflowLayout == .flow ? .coverFlow : .infinity
        }
        set {
            switch newValue {
            case .standard: mode = .standard
            case .infinity: overflowLayout = .wall; mode = .overflow
            case .coverFlow: overflowLayout = .flow; mode = .overflow
            }
        }
    }

    var rememberMode: Bool {
        didSet {
            UserDefaults.standard.set(rememberMode, forKey: Self.rememberKey)
            if !rememberMode { UserDefaults.standard.removeObject(forKey: Self.modeKey) }
        }
    }
    /// 回到登入畫面的原因（例如登入過期），顯示在 ConnectView
    var signOutReason: String?
    /// 網路恢復時遞增；失敗中的畫面據此重新載入
    private(set) var reconnectCount = 0
    var isSearchPresented = false
    /// 設定卡片（浮在主視窗上，⌘, 或側欄的齒輪打開）
    var isSettingsPresented = false
    /// 使用者選的配色（D37）。換配色時各視窗以 `.id(colorTheme)` 重建，所有顏色重新取值
    var colorTheme: ColorTheme = ColorTheme.current {
        didSet { ColorTheme.apply(colorTheme) }
    }
    /// 要建立新 playlist 時的曲目（非 nil 時顯示命名對話框）
    var newPlaylistTracks: [Track]?
    /// `finify://album/<id>` 要打開的專輯；由目前的 mode 打開後清掉
    var requestedAlbumID: String?
    var isQueuePresented = false {
        didSet { if isQueuePresented { isLyricsPresented = false } }
    }
    var isLyricsPresented = false {
        didSet { if isLyricsPresented { isQueuePresented = false } }
    }

    @ObservationIgnored private let sessionStore: any SessionStore
    @ObservationIgnored private var nowPlaying: NowPlayingController?
    @ObservationIgnored private var notifier: TrackNotifier?
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var wasOffline = false
    @ObservationIgnored private var expiryObserver: NSObjectProtocol?
    @ObservationIgnored private var terminateObserver: NSObjectProtocol?
    @ObservationIgnored private var lastSavedPlayback: Data?
    private static let modeKey = "FinifyMode"
    private static let rememberKey = "FinifyRememberMode"

    init(sessionStore: any SessionStore) {
        self.sessionStore = sessionStore
        rememberMode = UserDefaults.standard.object(forKey: Self.rememberKey) as? Bool ?? true
        mode = rememberMode ? UserDefaults.standard.string(forKey: Self.modeKey).flatMap(AppMode.init) : nil
        ImagePipeline.trackDisplayColorSpace()
        nowPlaying = NowPlayingController(player: player) { [weak self] in self?.images }
        let notifier = TrackNotifier { [weak self] in self?.images }
        self.notifier = notifier
        player.onTrackChange = { notifier.trackChanged($0) }
        // YouTube：專輯頁的愛心是加入／移出收藏，寫入後重新讀取音樂庫，封面牆跟著出現或消失
        favorites.onSynced = { [weak self] id in
            guard let self, self.session?.isYouTube == true, id.hasPrefix("MPREb_") else { return }
            Task { await self.library.refresh() }
        }
        // 第一次開啟：有 Jellyfin 登入就用 Jellyfin，沒有就用 YouTube Music
        let stored = sessionStore.load()
        source = UserDefaults.standard.string(forKey: Self.sourceKey).flatMap(MusicSource.init) ?? (stored != nil ? .jellyfin : .youtube)
        if source == .jellyfin, let stored {
            activate(stored)
            // 背景確認 YouTube Music 是否也登入著（設定裡顯示、切換用）；沒登入過的話不會連網
            Task { await youtube.restore() }
        } else {
            Task { await restoreYouTube() }
        }
        expiryObserver = NotificationCenter.default.addObserver(forName: .finifySessionExpired, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.session != nil else { return }
                self.signOut(reason: String(localized: "Your session with the music server ended. Sign in again to keep listening."))
            }
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.networkChanged(online: path.status == .satisfied) }
        }
        pathMonitor.start(queue: .global(qos: .utility))
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.savePlayback() }
        }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                self?.savePlayback()
            }
        }
    }

    private func networkChanged(online: Bool) {
        defer { wasOffline = !online }
        guard online, wasOffline else { return }
        reconnectCount += 1
        if library.state == .failed { Task { await library.refresh() } }
    }

    /// 上次連線的 server 位址（不含帳密），用來預填登入畫面
    static var lastServerAddress: String? { UserDefaults.standard.string(forKey: "FinifyLastServer") }

    static func bootstrap() -> AppEnvironment {
        #if DEBUG || BENCHMARK
        if let path = UserDefaults.standard.string(forKey: "FinifySecrets") {
            let env = AppEnvironment(sessionStore: DevelopmentSessionStore(directory: URL(fileURLWithPath: path)))
            if let mode = UserDefaults.standard.string(forKey: "FinifyStartMode").flatMap(AppMode.init) { env.mode = mode }
            return env
        }
        // 當 test host 時不碰 Keychain：重新簽章後系統會跳授權框，test runner 會一直卡住
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return AppEnvironment(sessionStore: DevelopmentSessionStore(directory: FileManager.default.temporaryDirectory.appending(path: "FinifyTestHost")))
        }
        #endif
        #if DEBUG || BENCHMARK || DEV_LOGIN
        // 開發版與測試版（build-release.sh）：有 repo 的 .secrets 就自動登入，不再顯示登入畫面
        if let secrets = DevelopmentSessionStore.repoSecrets, DevelopmentSessionStore(directory: secrets).load() != nil {
            return AppEnvironment(sessionStore: DevelopmentSessionStore(directory: secrets))
        }
        #endif
        return AppEnvironment(sessionStore: KeychainSessionStore())
    }

    func signIn(_ session: JellyfinSession) throws {
        // 切換來源不登出另一邊（YouTube 的 cookie 保留）
        if self.session != nil { deactivate() }
        try sessionStore.save(session)
        signOutReason = nil
        activate(session)
    }

    // MARK: - 音樂來源（D39）

    private static let sourceKey = "FinifySource"

    /// 使用者選的音樂來源；沒登入時登入畫面也顯示這一邊
    var source: MusicSource = .youtube {
        didSet { UserDefaults.standard.set(source.rawValue, forKey: Self.sourceKey) }
    }

    /// Jellyfin 是否有保存的登入（切換時不用重新登入）
    var hasJellyfinAccount: Bool { sessionStore.load() != nil }

    /// 切換音樂來源：暫停目前這一邊（不登出），已登入過的那一邊直接連線，沒登入過就顯示它的登入畫面
    func switchSource(to target: MusicSource) async {
        guard session == nil || source != target else { return }
        if session != nil { deactivate() }
        source = target
        switch target {
        case .jellyfin: if let stored = sessionStore.load() { activate(stored) }
        case .youtube: await restoreYouTube()
        }
    }

    // MARK: - YouTube Music

    /// 登入視窗完成後：確認帳號並切到 YouTube Music
    func signInYouTube() async {
        await youtube.didSignIn()
        activateYouTubeIfConnected()
    }

    /// 啟動時：之前登入過（cookie 還在）就直接連線
    func restoreYouTube() async {
        await youtube.restore()
        activateYouTubeIfConnected()
    }

    private func activateYouTubeIfConnected() {
        guard session == nil, case .connected(let name, let avatar) = youtube.state else { return }
        activate(JellyfinSession(serverURL: URL(string: InnerTube.origin)!, serverName: "YouTube Music", userID: "youtube",
                                 userName: name, accessToken: "", source: "youtube", avatar: avatar))
    }

    /// 登出目前的音樂來源；另一邊的登入保留
    func signOut(reason: String? = nil) {
        signOutReason = reason
        if session?.isYouTube == true { Task { await youtube.signOut() } } else { sessionStore.clear() }
        try? FileManager.default.removeItem(at: playbackFile)
        deactivate()
    }

    /// 停止播放、清掉目前來源的資料，但不清除登入
    private func deactivate() {
        cast.stop(player: player, resumeLocally: false)
        player.stop()
        session = nil
        repository = nil
        images = nil
        library.reset()
        favorites.reset()
        playlists.reset()
    }

    // MARK: - 播放狀態保存

    private var playbackFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.finify.Finify/playback.json")
    }

    private var sessionOwner: String? { session.map { $0.serverURL.absoluteString + "|" + $0.userID } }

    /// 每 10 秒與關閉 app 時保存；只恢復同一個 server 與使用者的狀態
    func savePlayback() {
        guard let owner = sessionOwner else { return }
        guard let snapshot = player.snapshot(owner: owner) else {
            try? FileManager.default.removeItem(at: playbackFile)
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot), data != lastSavedPlayback else { return }
        try? data.write(to: playbackFile, options: .atomic)
        lastSavedPlayback = data
    }

    private func restorePlayback() {
        guard let owner = sessionOwner, let data = try? Data(contentsOf: playbackFile),
              let snapshot = try? JSONDecoder().decode(PlaybackSnapshot.self, from: data), snapshot.owner == owner else { return }
        player.restore(snapshot)
    }

    private func activate(_ session: JellyfinSession) {
        self.session = session
        source = session.isYouTube ? .youtube : .jellyfin
        let repository: any MusicRepository
        if session.isYouTube {
            repository = YouTubeMusicRepository()
            player.attach(webPlayer: youtubePlayer)
        } else {
            UserDefaults.standard.set(session.serverURL.absoluteString, forKey: "FinifyLastServer")
            repository = JellyfinRepository(session: session)
            player.attach(webPlayer: nil)
        }
        self.repository = repository
        images = ImagePipeline { ref, size in repository.artworkURL(ref, maxPixelSize: size) }
        player.attach(repository: repository)
        library.attach(repository: repository, serverID: session.serverURL.absoluteString + session.userID)
        favorites.attach(repository: repository)
        playlists.attach(repository: repository)
        restorePlayback()
    }
}
